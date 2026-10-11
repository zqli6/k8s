#!/bin/bash
# ============================================================
# 06-join-worker.sh
# 执行节点：仅 node*（可并行）
# 功能：加入集群作为 worker 节点
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 加入 Worker: $(hostname)"
echo "=========================================="

if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[!] 本节点已加入集群"
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

JOIN_ENV="/etc/kubernetes/deploy/join.env"
if [ ! -f "$JOIN_ENV" ]; then
    echo "[✗] 未找到 $JOIN_ENV"
    exit 1
fi
source "$JOIN_ENV"
[ -z "$JOIN_CMD" ] && { echo "[✗] JOIN_CMD 为空"; exit 1; }

${JOIN_CMD} --cri-socket unix:///var/run/containerd/containerd.sock

echo ""
sleep 3
if systemctl is-active --quiet kubelet; then
    echo "[完成] $(hostname) 已加入集群作为 worker"
else
    echo "[!] kubelet 未正常运行: journalctl -u kubelet -f"
    exit 1
fi
