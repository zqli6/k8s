#!/bin/bash
# ============================================================
# 03-install-k8s.sh
# 执行节点：全部节点（9台都要跑）
# 功能：安装 kubeadm、kubelet、kubectl（阿里云 kubernetes-new 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 安装 K8s 组件: $(hostname)"
echo "=========================================="

# --- 幂等检查 ---
if command -v kubeadm &>/dev/null; then
    CURRENT_VER=$(kubeadm version -o short 2>/dev/null)
    if [ "$CURRENT_VER" == "v${KUBE_VERSION}" ]; then
        echo "[=] kubeadm 已安装且版本正确: $CURRENT_VER"
        echo "[完成] 跳过安装"
        exit 0
    else
        echo "[!] kubeadm 已安装但版本不符: $CURRENT_VER (期望 v${KUBE_VERSION})"
        echo "    如需重装请先: yum remove kubelet kubeadm kubectl"
        exit 1
    fi
fi

# --- 1. 配置阿里云 kubernetes-new 源 ---
# 注意：1.28 必须用 kubernetes-new 新路径，旧的 mirrors.aliyun.com/kubernetes/ 已冻结
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes v${KUBE_VERSION_SHORT}
baseurl=${KUBE_REPO_URL}
enabled=1
gpgcheck=1
gpgkey=${KUBE_REPO_GPGKEY}
EOF
echo "[✓] kubernetes yum 源已配置（阿里云 kubernetes-new）"
echo "    baseurl: ${KUBE_REPO_URL}"

# --- 2. 安装 kubelet kubeadm kubectl ---
yum install -y kubelet-${KUBE_VERSION} kubeadm-${KUBE_VERSION} kubectl-${KUBE_VERSION}
echo "[✓] kubelet/kubeadm/kubectl ${KUBE_VERSION} 已安装"

# --- 3. 锁定版本防止意外升级 ---
if rpm -q yum-plugin-versionlock &>/dev/null || yum install -y yum-plugin-versionlock > /dev/null 2>&1; then
    yum versionlock add kubelet kubeadm kubectl 2>/dev/null || true
    echo "[✓] 版本已锁定"
fi

# --- 4. 启用 kubelet（此时还不会真正运行，等 kubeadm init/join） ---
systemctl enable kubelet
echo "[✓] kubelet 已设为开机启动"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "kubeadm: $(kubeadm version -o short 2>/dev/null)"
echo "kubelet: $(kubelet --version 2>/dev/null)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
echo ""
echo "[完成] K8s 组件安装完毕"
