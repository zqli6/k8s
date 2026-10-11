#!/bin/bash
# ============================================================
# 03-install-k8s.sh
# 执行节点：全部节点
# 功能：安装 kubeadm、kubelet、kubectl（Ubuntu 离线版，优先本地 deb 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 安装 K8s 组件: $(hostname)"
echo "=========================================="

# --- 清理旧版手工 kubelet unit ---
if [ -f /etc/systemd/system/kubelet.service ] && grep -q '/usr/local/bin/kubelet' /etc/systemd/system/kubelet.service; then
    systemctl stop kubelet 2>/dev/null || true
    rm -f /etc/systemd/system/kubelet.service
    rm -rf /etc/systemd/system/kubelet.service.d
    systemctl daemon-reload
    echo "[✓] 已清理旧版 kubelet unit"
fi

# --- 幂等检查 ---
if command -v kubeadm &>/dev/null; then
    CURRENT_VER=$(kubeadm version -o short 2>/dev/null)
    if [ "$CURRENT_VER" == "v${KUBE_VERSION}" ]; then
        echo "[=] kubeadm 已安装且版本正确: $CURRENT_VER"
        exit 0
    else
        echo "[!] kubeadm 版本不符: $CURRENT_VER (期望 v${KUBE_VERSION})"
        echo "    如需重装: apt-get remove -y kubelet kubeadm kubectl"
        exit 1
    fi
fi

# --- 1. 配置软件包源（本地 deb 优先，回退在线 kubernetes 源）---
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
[ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/packages" ] && OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
DEBS_DIR="${OFFLINE_BASE}/packages"

if compgen -G "${DEBS_DIR}/*.deb" > /dev/null; then
    if [ ! -f "${DEBS_DIR}/Packages.gz" ]; then
        dpkg-scanpackages "${DEBS_DIR}" /dev/null | gzip -9c > "${DEBS_DIR}/Packages.gz" 2>/dev/null || true
    fi
    if ! grep -q "file:${DEBS_DIR}" /etc/apt/sources.list.d/k8s-local.list 2>/dev/null; then
        cat > /etc/apt/sources.list.d/k8s-local.list <<EOF
deb [trusted=yes] file:${DEBS_DIR} ./
EOF
    fi
    apt-get update > /dev/null 2>&1
    echo "[✓] 使用本地 deb 源: file:${DEBS_DIR}"
else
    echo "[✗] 未找到本地 deb 包，离线部署不能继续: ${DEBS_DIR}"
    exit 1
fi

# --- 2. 安装 kubelet kubeadm kubectl（固定版本）---
apt-get install -y kubelet=${KUBE_VERSION}-* kubeadm=${KUBE_VERSION}-* kubectl=${KUBE_VERSION}-*
echo "[✓] kubelet/kubeadm/kubectl ${KUBE_VERSION} 已安装"

# --- 3. 锁定版本（apt-mark hold）---
apt-mark hold kubelet kubeadm kubectl
echo "[✓] 版本已锁定"

# --- 4. 启用 kubelet ---
systemctl daemon-reload
systemctl enable kubelet
echo "[✓] kubelet 已设为开机启动"

echo ""
echo "--- 验证 ---"
echo "kubeadm: $(kubeadm version -o short 2>/dev/null)"
echo "kubelet: $(kubelet --version 2>/dev/null)"
echo ""
echo "[完成] K8s 组件安装完毕"
