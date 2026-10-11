#!/bin/bash
# ============================================================
# 03-install-k8s.sh
# 执行节点：全部节点
# 功能：安装 kubeadm、kubelet、kubectl（Ubuntu 版，阿里云 kubernetes-new deb 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 安装 K8s 组件: $(hostname)"
echo "=========================================="

# --- 幂等检查前：清理旧版 kubelet systemd unit ---
if [ -f /etc/systemd/system/kubelet.service ] && grep -q '/usr/local/bin/kubelet' /etc/systemd/system/kubelet.service; then
    systemctl stop kubelet 2>/dev/null || true
    rm -f /etc/systemd/system/kubelet.service
    rm -rf /etc/systemd/system/kubelet.service.d
    systemctl daemon-reload
    echo "[✓] 已清理旧版 kubelet systemd unit"
fi

# --- 幂等检查 ---
if command -v kubeadm &>/dev/null; then
    CURRENT_VER=$(kubeadm version -o short 2>/dev/null)
    if [ "$CURRENT_VER" == "v${KUBE_VERSION}" ]; then
        echo "[=] kubeadm 已安装且版本正确: $CURRENT_VER"
        echo "[完成] 跳过安装"
        exit 0
    else
        echo "[!] kubeadm 已安装但版本不符: $CURRENT_VER (期望 v${KUBE_VERSION})"
        echo "    如需重装请先: apt-get remove -y kubelet kubeadm kubectl"
        exit 1
    fi
fi

# --- 1. 配置阿里云 kubernetes-new deb 源 ---
mkdir -p /etc/apt/keyrings
curl -fsSL "$KUBE_REPO_GPGKEY" | gpg --batch --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${KUBE_REPO_URL}/ /" \
    | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
apt-get update > /dev/null 2>&1
echo "[✓] kubernetes apt 源已配置（阿里云 kubernetes-new）"
echo "    deb: ${KUBE_REPO_URL}"

# --- 2. 安装 kubelet kubeadm kubectl（固定版本）---
apt-get install -y kubelet=${KUBE_VERSION}-* kubeadm=${KUBE_VERSION}-* kubectl=${KUBE_VERSION}-*
echo "[✓] kubelet/kubeadm/kubectl ${KUBE_VERSION} 已安装"

# --- 3. 锁定版本（apt-mark hold）---
apt-mark hold kubelet kubeadm kubectl
echo "[✓] 版本已锁定（apt-mark hold）"

# --- 4. 启用 kubelet ---
systemctl daemon-reload
systemctl enable kubelet
echo "[✓] kubelet 已设为开机启动"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "kubeadm: $(kubeadm version -o short 2>/dev/null)"
echo "kubelet: $(kubelet --version 2>/dev/null)"
echo "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
echo ""
echo "[完成] K8s 组件安装完毕"
