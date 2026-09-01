#!/bin/bash
# ============================================================
# 06-join-worker.sh
# 执行节点：仅 node1-node6（可并行执行）
# 功能：加入集群作为 worker 节点
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 加入 Worker: $(hostname)"
echo "=========================================="

# --- 前置检查 ---
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[!] 本节点已加入集群（/etc/kubernetes/kubelet.conf 存在）"
    echo "    如需重新加入: kubeadm reset -f && rm -rf /etc/kubernetes"
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    echo "[✗] containerd 未运行"
    exit 1
fi

if ! command -v kubeadm &>/dev/null; then
    echo "[✗] kubeadm 未安装"
    exit 1
fi

# 读取 join 信息
JOIN_ENV="/etc/kubernetes/deploy/join.env"
if [ ! -f "$JOIN_ENV" ]; then
    echo "[✗] 未找到 $JOIN_ENV"
    echo "    请从 master1 拷贝: scp master1:/etc/kubernetes/deploy/join.env /etc/kubernetes/deploy/"
    exit 1
fi
source "$JOIN_ENV"

if [ -z "$JOIN_CMD" ]; then
    echo "[✗] join.env 中 JOIN_CMD 为空"
    exit 1
fi
echo "[✓] join 信息已加载"

# --- 加入集群 ---
echo ""
echo "--- 执行 kubeadm join (worker) ---"
${JOIN_CMD} --cri-socket unix:///var/run/containerd/containerd.sock

# --- 验证 ---
echo ""
echo "--- 验证 ---"
sleep 3
if systemctl is-active --quiet kubelet; then
    echo "[完成] $(hostname) 已加入集群作为 worker"
    echo "    在 master 上执行 kubectl get nodes 查看状态"
else
    echo "[!] kubelet 未正常运行，检查日志: journalctl -u kubelet -f"
    exit 1
fi
