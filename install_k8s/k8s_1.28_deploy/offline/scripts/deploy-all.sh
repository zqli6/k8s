#!/bin/bash
# ============================================================
# deploy-all.sh
# 执行节点：仅 master1（通过 SSH 免密分发到其他节点）
# 功能：一键部署整个集群（按 phase 编排）
# 用法：
#   ./deploy-all.sh              # 全量部署
#   ./deploy-all.sh --from 4     # 从 phase 4 开始（断点续跑）
#   ./deploy-all.sh --only 7     # 只跑 phase 7
#   ./deploy-all.sh --dry-run    # 只打印计划不执行
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env"

# --- 参数解析 ---
FROM_PHASE=0
ONLY_PHASE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_PHASE="$2"; shift 2;;
        --only) ONLY_PHASE="$2"; shift 2;;
        --dry-run) DRY_RUN=true; shift;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

# --- 工具函数 ---
SSH_OPTS=(-o StrictHostKeyChecking=no)
LOCAL_IP=$(hostname -I | awk '{print $1}')
ssh_node() {
    local node="$1"
    shift
    if [ "$node" == "$LOCAL_IP" ]; then
        bash -c "$*"
    else
        ssh "${SSH_OPTS[@]}" root@"$node" "$@"
    fi
}
scp_node() {
    local source="$1"
    local destination="$2"
    local target="${destination#root@}"
    local node="${target%%:*}"
    local path="${target#*:}"
    if [ "$node" == "$LOCAL_IP" ]; then
        if [ "$(readlink -f "$source" 2>/dev/null)" != "$(readlink -f "$path" 2>/dev/null)" ]; then
            mkdir -p "$(dirname "$path")"
            cp -f "$source" "$path"
        fi
    else
        scp "${SSH_OPTS[@]}" "$source" "$destination"
    fi
}

log() { echo -e "\033[1;36m[DEPLOY $(date +%H:%M:%S)]\033[0m $1"; }
err() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

run_on_nodes() {
    local nodes=("$@")
    local last_index=$((${#nodes[@]} - 1))
    local script="${nodes[$last_index]}"
    unset "nodes[$last_index]"

    for node in "${nodes[@]}"; do
        log "  → $node: $script"
        if [ "$DRY_RUN" == "true" ]; then continue; fi
        ssh_node "$node" "bash /opt/k8s-deploy/offline/scripts/$script"
    done
}

run_on_nodes_parallel() {
    local nodes=("$@")
    local last_index=$((${#nodes[@]} - 1))
    local script="${nodes[$last_index]}"
    unset "nodes[$last_index]"
    local pids=()

    for node in "${nodes[@]}"; do
        log "  → $node: $script (并行)"
        if [ "$DRY_RUN" == "true" ]; then continue; fi
        ssh_node "$node" "bash /opt/k8s-deploy/offline/scripts/$script" &
        pids+=($!)
    done

    if [ "$DRY_RUN" == "true" ]; then return 0; fi

    local fail=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then ((fail++)); fi
    done
    if [ $fail -gt 0 ]; then
        err "$fail 个节点执行失败"
    fi
}

should_run() {
    local phase=$1
    if [ -n "$ONLY_PHASE" ]; then
        [ "$phase" == "$ONLY_PHASE" ]
    else
        [ "$phase" -ge "$FROM_PHASE" ]
    fi
}

refresh_join_env() {
    [ "$DRY_RUN" == "true" ] && return 0
    local f=/etc/kubernetes/deploy/join.env
    local need=0
    if [ ! -f "$f" ]; then need=1; else
        local age=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
        [ "$age" -gt 5400 ] && need=1
    fi
    [ "$need" -eq 0 ] && return 0
    log "join.env 缺失或超 1.5h，在 master1 重新签发..."
    local JOIN_CMD CERT_KEY
    JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
    CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
    mkdir -p /etc/kubernetes/deploy
    cat > "$f" <<EOF
JOIN_CMD="${JOIN_CMD}"
CERT_KEY="${CERT_KEY}"
VIP="${VIP}"
API_SERVER_PORT="${API_SERVER_PORT}"
EOF
    chmod 600 "$f"
    log "join.env 已刷新 ✓"
}

# --- 上传脚本和配置到所有节点 ---
distribute_files() {
    log "分发脚本和配置到所有节点..."
    if [ "$DRY_RUN" == "true" ]; then return 0; fi

    # 代码/配置来自当前 offline 目录；镜像和 RPM 优先从 OFFLINE_SOURCE_DIR 读取，
    # 这样可复用服务器上已有的离线介质，不必从客户端重复上传大文件。
    OFFLINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    if [ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/images" ]; then
        RESOURCE_ROOT="${OFFLINE_SOURCE_DIR}"
    else
        RESOURCE_ROOT="${OFFLINE_ROOT}"
    fi
    for node in "${ALL_NODES[@]}"; do
        log "  → $node: 准备 /opt/k8s-deploy/offline"
        ssh_node "$node" "mkdir -p /opt/k8s-deploy/offline/config /opt/k8s-deploy/offline/scripts /opt/k8s-deploy/offline/tools /opt/k8s-deploy/offline/manifests /opt/k8s-deploy/offline/images /opt/k8s-deploy/offline/packages"
        scp_node "${OFFLINE_ROOT}/config/cluster.env" root@"$node":/opt/k8s-deploy/offline/config/cluster.env
        for resource in "${OFFLINE_ROOT}"/tools/* "${OFFLINE_ROOT}"/manifests/*; do
            [ -f "$resource" ] || continue
            scp_node "$resource" root@"$node":/opt/k8s-deploy/offline/"$(basename "$(dirname "$resource")")"/"$(basename "$resource")"
        done
        for script in "${OFFLINE_ROOT}"/scripts/*.sh; do
            scp_node "$script" root@"$node":/opt/k8s-deploy/offline/scripts/"$(basename "$script")"
        done
        if [ "$node" != "$LOCAL_IP" ]; then
            for image in "${RESOURCE_ROOT}"/images/*.tar; do
                scp_node "$image" root@"$node":/opt/k8s-deploy/offline/images/"$(basename "$image")"
            done
            for rpm in "${RESOURCE_ROOT}"/packages/*.rpm; do
                scp_node "$rpm" root@"$node":/opt/k8s-deploy/offline/packages/"$(basename "$rpm")"
            done
            scp_node "${RESOURCE_ROOT}/packages/repodata/repomd.xml" root@"$node":/opt/k8s-deploy/offline/packages/repodata/repomd.xml
            for metadata in "${RESOURCE_ROOT}"/packages/repodata/*; do
                [ -f "$metadata" ] || continue
                scp_node "$metadata" root@"$node":/opt/k8s-deploy/offline/packages/repodata/"$(basename "$metadata")"
            done
        fi
    done
    echo "[✓] 文件/配置分发完成（资源源: ${RESOURCE_ROOT}）"
}

# ============================================================
# 部署前必须先分发配置和脚本。
# 远程脚本通过 stdin 执行，SCRIPT_DIR 不指向仓库目录，
# 因此依赖 /opt/k8s-deploy/config/cluster.env 等 fallback 路径。
# ============================================================
distribute_files

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Kubernetes v${KUBE_VERSION} 集群一键部署                  ║"
echo "║  ${MASTER_COUNT} Master + ${WORKER_COUNT} Worker | kube-vip HA | Calico CNI ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "集群拓扑："
echo "  Master: ${ALL_MASTERS[*]}"
echo "  Worker: ${ALL_WORKERS[*]}"
echo "  VIP:    ${VIP}"
echo ""
if [ "$DRY_RUN" == "true" ]; then
    echo ">>> DRY RUN 模式：只打印计划，不执行 <<<"
    echo ""
fi

# --- Phase 0: 环境检查 ---
if should_run 0; then
    log "═══ Phase 0: 环境检查（全部节点，并行）═══"
    run_on_nodes_parallel "${ALL_NODES[@]}" "00-env-check.sh"
    log "Phase 0 完成 ✓"
    echo ""
fi

# --- Phase 1: 系统初始化 ---
if should_run 1; then
    log "═══ Phase 1: 系统初始化（全部节点，并行）═══"
    run_on_nodes_parallel "${ALL_NODES[@]}" "01-system-init.sh"
    log "Phase 1 完成 ✓"
    echo ""
fi

# --- Phase 2: 安装 containerd ---
if should_run 2; then
    log "═══ Phase 2: 安装 containerd（全部节点，并行）═══"
    run_on_nodes_parallel "${ALL_NODES[@]}" "02-install-containerd.sh"
    log "Phase 2 完成 ✓"
    echo ""
fi

# --- Phase 2.5: 导入本地离线镜像（离线专属，containerd 就绪后执行）---
if should_run 2; then
    log "═══ Phase 2.5: 导入本地离线镜像（全部节点，并行）═══"
    run_on_nodes_parallel "${ALL_NODES[@]}" "import-resources.sh"
    log "Phase 2.5 完成 ✓"
    echo ""
fi

# --- Phase 3: 安装 K8s 组件 ---
if should_run 3; then
    log "═══ Phase 3: 安装 kubeadm/kubelet/kubectl（全部节点，并行）═══"
    run_on_nodes_parallel "${ALL_NODES[@]}" "03-install-k8s.sh"
    log "Phase 3 完成 ✓"
    echo ""
fi

# --- Phase 4: 初始化 master1 ---
if should_run 4; then
    log "═══ Phase 4: 初始化 master1（kube-vip + kubeadm init）═══"
    if [ "$DRY_RUN" != "true" ]; then
        bash "${SCRIPT_DIR}/04-init-master1.sh"
    else
        log "  → 本地: 04-init-master1.sh"
    fi
    log "Phase 4 完成 ✓"
    echo ""
fi

# --- Phase 5: 加入其余 master（串行）---
if should_run 5; then
    log "═══ Phase 5: 加入其余 master（串行，保护 etcd quorum）═══"

    # 从第 2 个 master 开始（index 1），第 1 个是 init 节点已就绪
    if [ "$MASTER_COUNT" -le 1 ]; then
        log "  只有 1 个 master，无需 join，跳过 Phase 5"
    else
        refresh_join_env
        for idx in $(seq 1 $((MASTER_COUNT - 1))); do
            m_ip="${MASTER_IPS[$idx]}"
            m_name="${MASTER_NAMES[$idx]}"
            if [ "$DRY_RUN" != "true" ]; then
                log "  → $m_ip ($m_name): 分发 join.env + 05-join-master.sh"
                ssh_node "$m_ip" "mkdir -p /etc/kubernetes/deploy"
                scp_node /etc/kubernetes/deploy/join.env root@"$m_ip":/etc/kubernetes/deploy/
                ssh_node "$m_ip" "bash /opt/k8s-deploy/offline/scripts/05-join-master.sh"
                sleep 10
                kubectl get nodes
                # 校验 etcd 健康后再加下一台
                kubectl get --raw='/healthz/etcd' &>/dev/null && log "  → $m_name 加入完成，etcd 健康 ✓" || err "etcd 异常，停止加入 master"
            else
                log "  → $m_ip ($m_name): 05-join-master.sh (串行)"
            fi
        done
    fi
    log "Phase 5 完成 ✓"
    echo ""
fi

# --- Phase 6: 加入 worker（并行）---
if should_run 6; then
    log "═══ Phase 6: 加入 worker 节点（并行）═══"

    if [ "$DRY_RUN" != "true" ]; then
        refresh_join_env
        # 分发 join.env
        for worker in "${ALL_WORKERS[@]}"; do
            ssh_node "$worker" "mkdir -p /etc/kubernetes/deploy"
            scp_node /etc/kubernetes/deploy/join.env root@"$worker":/etc/kubernetes/deploy/
        done

        # 并行 join
        pids=()
        for worker in "${ALL_WORKERS[@]}"; do
            log "  → $worker: 06-join-worker.sh (并行)"
            ssh_node "$worker" "bash /opt/k8s-deploy/offline/scripts/06-join-worker.sh" &
            pids+=($!)
        done
        for pid in "${pids[@]}"; do wait "$pid"; done

        sleep 10
        kubectl get nodes
    else
        for worker in "${ALL_WORKERS[@]}"; do
            log "  → $worker: 06-join-worker.sh (并行)"
        done
    fi
    log "Phase 6 完成 ✓"
    echo ""
fi

# --- Phase 7: 安装 Calico ---
if should_run 7; then
    log "═══ Phase 7: 安装 Calico CNI═══"
    if [ "$DRY_RUN" != "true" ]; then
        bash "${SCRIPT_DIR}/07-install-calico.sh"
    else
        log "  → 本地: 07-install-calico.sh"
    fi
    log "Phase 7 完成 ✓"
    echo ""
fi

# --- Phase 8: 证书续期 10 年 ---
if should_run 8; then
    log "═══ Phase 8: 证书续期 10 年（每 master 串行）═══"

    for master in "${ALL_MASTERS[@]}"; do
        log "  → $master: 08-renew-certs.sh"
        if [ "$DRY_RUN" != "true" ]; then
            if [ "$master" == "$MASTER1_IP" ]; then
                bash "${SCRIPT_DIR}/08-renew-certs.sh"
            else
                ssh_node "$master" "bash /opt/k8s-deploy/offline/scripts/08-renew-certs.sh"
            fi
            sleep 15
            # 校验 etcd 健康
            kubectl get --raw='/healthz/etcd' || err "etcd 异常，停止续期"
            log "  → $master 续期完成，etcd 健康 ✓"
        fi
    done
    log "Phase 8 完成 ✓"
    echo ""
fi

# --- Phase 9: 验收 ---
if should_run 9; then
    log "═══ Phase 9: 全量验收═══"
    if [ "$DRY_RUN" != "true" ]; then
        bash "${SCRIPT_DIR}/09-verify.sh"
    else
        log "  → 本地: 09-verify.sh"
    fi
    log "Phase 9 完成 ✓"
    echo ""
fi

# --- 清理 join 密钥 ---
if [ "$DRY_RUN" != "true" ] && should_run 6; then
    log "清理 join.env 密钥..."
    for node in "${ALL_NODES[@]}"; do
        ssh_node "$node" "rm -f /etc/kubernetes/deploy/join.env" 2>/dev/null || true
    done
    rm -f /etc/kubernetes/deploy/join.env
    echo "[✓] join 密钥已清理"
fi

echo ""
log "═══════════════════════════════════════"
log " 部署完成！"
log "═══════════════════════════════════════"
