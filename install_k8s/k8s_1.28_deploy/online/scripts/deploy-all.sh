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
source "${SCRIPT_DIR}/../../config/cluster.env"

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
log() { echo -e "\033[1;36m[DEPLOY $(date +%H:%M:%S)]\033[0m $1"; }
err() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

run_on_nodes() {
    local nodes=("$@")
    local last=$(( ${#nodes[@]} - 1 ))
    local script="${nodes[$last]}"
    unset "nodes[$last]"

    for node in "${nodes[@]}"; do
        log "  → $node: $script"
        if [ "$DRY_RUN" == "true" ]; then continue; fi
        ssh -o StrictHostKeyChecking=no root@"$node" "bash -s" < "${SCRIPT_DIR}/${script}"
    done
}

run_on_nodes_parallel() {
    local nodes=("$@")
    local last=$(( ${#nodes[@]} - 1 ))
    local script="${nodes[$last]}"
    unset "nodes[$last]"
    local pids=()

    for node in "${nodes[@]}"; do
        log "  → $node: $script (并行)"
        if [ "$DRY_RUN" == "true" ]; then continue; fi
        ssh -o StrictHostKeyChecking=no root@"$node" "bash -s" < "${SCRIPT_DIR}/${script}" &
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

# 刷新 join.env（断点续跑保险）：cert-key 有效期 2h、token 24h，
# 若 join.env 缺失或生成超过 1.5h，在 master1 重新签发，避免 --from 续跑时 join 失败。
refresh_join_env() {
    [ "$DRY_RUN" == "true" ] && return 0
    local f=/etc/kubernetes/deploy/join.env
    local need=0
    if [ ! -f "$f" ]; then need=1; else
        local age=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
        [ "$age" -gt 5400 ] && need=1
    fi
    [ "$need" -eq 0 ] && return 0
    log "join.env 缺失或超 1.5h，在 master1 重新签发 token/cert-key..."
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

    for node in "${ALL_NODES[@]}"; do
        ssh -o StrictHostKeyChecking=no root@"$node" "mkdir -p /opt/k8s-deploy/config /opt/k8s-deploy/online/scripts /opt/k8s-deploy/tools" 2>/dev/null
        scp -q "${SCRIPT_DIR}/../../config/cluster.env" root@"$node":/opt/k8s-deploy/config/
        scp -q "${SCRIPT_DIR}/../../tools/update-kubeadm-cert.sh" root@"$node":/opt/k8s-deploy/tools/ 2>/dev/null
        for script in 00-env-check.sh 01-system-init.sh 02-install-containerd.sh 03-install-k8s.sh; do
            scp -q "${SCRIPT_DIR}/${script}" root@"$node":/opt/k8s-deploy/online/scripts/
        done
    done
    echo "[✓] 文件分发完成"
}

# ============================================================
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Kubernetes v${KUBE_VERSION} 集群一键部署                  ║"
echo "║  3 Master + 6 Worker | kube-vip HA | Calico CNI        ║"
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

# 预分发配置和基础脚本到所有节点（远程 ssh bash -s 管道执行时 fallback 用）
distribute_files

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
        refresh_join_env   # 断点续跑保险：join.env 过期则刷新
        for idx in $(seq 1 $((MASTER_COUNT - 1))); do
            m_ip="${MASTER_IPS[$idx]}"
            m_name="${MASTER_NAMES[$idx]}"
            if [ "$DRY_RUN" != "true" ]; then
                log "  → $m_ip ($m_name): 分发 join.env + 05-join-master.sh"
                ssh root@"$m_ip" "mkdir -p /etc/kubernetes/deploy"
                scp -q /etc/kubernetes/deploy/join.env root@"$m_ip":/etc/kubernetes/deploy/
                ssh root@"$m_ip" "bash -s" < "${SCRIPT_DIR}/05-join-master.sh"
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
        refresh_join_env   # 断点续跑保险
        # 分发 join.env
        for worker in "${ALL_WORKERS[@]}"; do
            ssh root@"$worker" "mkdir -p /etc/kubernetes/deploy"
            scp -q /etc/kubernetes/deploy/join.env root@"$worker":/etc/kubernetes/deploy/
        done

        # 并行 join
        pids=()
        for worker in "${ALL_WORKERS[@]}"; do
            log "  → $worker: 06-join-worker.sh (并行)"
            ssh root@"$worker" "bash -s" < "${SCRIPT_DIR}/06-join-worker.sh" &
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
                ssh root@"$master" "bash -s" < "${SCRIPT_DIR}/08-renew-certs.sh"
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
        ssh root@"$node" "rm -f /etc/kubernetes/deploy/join.env" 2>/dev/null || true
    done
    rm -f /etc/kubernetes/deploy/join.env
    echo "[✓] join 密钥已清理"
fi

echo ""
log "═══════════════════════════════════════"
log " 部署完成！"
log "═══════════════════════════════════════"
