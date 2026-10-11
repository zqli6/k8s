#!/bin/bash
# ============================================================
# fetch-resources.sh
# 执行节点：一台能访问外网的 Ubuntu 22.04/24.04 机器（制备离线包）
# 功能：下载 deb 包 + 生成 Packages 索引 + 拉取镜像导出 tar + 下载 calico.yaml
# 产物（写入本目录上一级 ubuntu/offline/）：
#   packages/*.deb + Packages.gz   离线 deb 源
#   images/k8s-core.tar / calico.tar / kube-vip.tar   离线镜像
#   manifests/calico.yaml          离线 Calico manifest
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi
export DEBIAN_FRONTEND=noninteractive

OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_DIR="${OFFLINE_BASE}/packages"
IMG_DIR="${OFFLINE_BASE}/images"
MANIFEST_DIR="${OFFLINE_BASE}/manifests"
mkdir -p "$PKG_DIR" "$IMG_DIR" "$MANIFEST_DIR"

echo "=========================================="
echo " 制备 K8s 离线包（Ubuntu ${UBUNTU_CODENAME}）"
echo " 产物目录: $OFFLINE_BASE"
echo "=========================================="

# --- 0. 前置：安装 dpkg-dev（dpkg-scanpackages 用）---
command -v dpkg-scanpackages &>/dev/null || apt-get install -y dpkg-dev > /dev/null 2>&1

# --- 1. 配置阿里云源（若未配）---
echo ""
echo "--- 1. 配置阿里云 apt 源 ---"
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL "$DOCKER_CE_GPGKEY" | gpg --dearmor -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_CE_REPO} ${UBUNTU_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    echo "[✓] docker-ce 源已配（${UBUNTU_CODENAME}）"
fi
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    curl -fsSL "$KUBE_REPO_GPGKEY" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${KUBE_REPO_URL}/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    echo "[✓] kubernetes 源已配"
fi
apt-get update > /dev/null 2>&1
echo "[✓] apt update 完成"

# --- 2. 下载所有 deb 包（含依赖）到本地缓存 ---
echo ""
echo "--- 2. 下载 deb 包（含依赖）---"
# 实际安装这几个（制备机需要 kubeadm 获取镜像清单、containerd 提供 ctr）
apt-get install -y kubeadm=${KUBE_VERSION}-* kubectl=${KUBE_VERSION}-* kubelet=${KUBE_VERSION}-* containerd > /dev/null 2>&1
# 其余仅下载（--download-only），不安装
apt-get install -y --download-only \
    conntrack socat ipset ipvsadm chrony \
    wget curl net-tools bash-completion ca-certificates gnupg > /dev/null 2>&1
echo "[✓] deb 包已下载到 /var/cache/apt/archives/"

# --- 3. 收集 deb 到 packages/ + 生成 Packages 索引 ---
echo ""
echo "--- 3. 生成离线 deb 源 ---"
cp /var/cache/apt/archives/*.deb "$PKG_DIR"/ 2>/dev/null || true
# 说明：apt-get install --download-only 会为每个包下载最新一个版本，archives 里无重复，无需去重
dpkg-scanpackages "$PKG_DIR" /dev/null | gzip -9c > "$PKG_DIR/Packages.gz"
DEB_COUNT=$(ls "$PKG_DIR"/*.deb 2>/dev/null | wc -l)
echo "[✓] 离线 deb 源生成：${DEB_COUNT} 个 deb + Packages.gz"

# --- 4. 拉取镜像并导出 tar ---
echo ""
echo "--- 4. 拉取并导出镜像 ---"
# 启动 containerd 供 ctr 使用
if ! systemctl is-active --quiet containerd; then
    systemctl start containerd 2>/dev/null || true
    sleep 2
fi

# 4.1 K8s 核心镜像（用 kubeadm 动态列出，保证 etcd/coredns tag 与版本匹配）
K8S_IMAGES=$(kubeadm config images list \
    --kubernetes-version "v${KUBE_VERSION}" \
    --image-repository "${IMAGE_REPOSITORY}" 2>/dev/null)
echo "K8s 核心镜像："
echo "$K8S_IMAGES" | sed 's/^/  /'
for img in $K8S_IMAGES; do
    ctr -n k8s.io images pull --platform linux/amd64 "$img" 2>/dev/null || echo "  [!] 拉取失败: $img"
done
ctr -n k8s.io images export "${IMG_DIR}/k8s-core.tar" $K8S_IMAGES 2>/dev/null
echo "[✓] k8s-core.tar 已导出"

# 4.2 Calico 镜像
CALICO_IMAGES=""
for c in node cni kube-controllers; do
    CALICO_IMAGES="${CALICO_IMAGES} ${CALICO_IMAGE_REGISTRY}/calico/${c}:${CALICO_VERSION}"
done
for img in $CALICO_IMAGES; do
    ctr -n k8s.io images pull --platform linux/amd64 "$img" 2>/dev/null || echo "  [!] 拉取失败: $img"
done
ctr -n k8s.io images export "${IMG_DIR}/calico.tar" $CALICO_IMAGES 2>/dev/null
echo "[✓] calico.tar 已导出"

# 4.3 kube-vip 镜像
ctr -n k8s.io images pull --platform linux/amd64 "$KUBEVIP_IMAGE" 2>/dev/null || echo "  [!] 拉取失败: $KUBEVIP_IMAGE"
ctr -n k8s.io images export "${IMG_DIR}/kube-vip.tar" "$KUBEVIP_IMAGE" 2>/dev/null
echo "[✓] kube-vip.tar 已导出"

# --- 5. 下载 Calico manifest ---
echo ""
echo "--- 5. 下载 Calico manifest ---"
curl -sSL --connect-timeout 15 "$CALICO_MANIFEST_URL" -o "$MANIFEST_DIR/calico.yaml"
if [ -s "$MANIFEST_DIR/calico.yaml" ] && grep -q "calico" "$MANIFEST_DIR/calico.yaml"; then
    echo "[✓] calico.yaml 已下载（$(wc -l < "$MANIFEST_DIR/calico.yaml") 行）"
else
    echo "[✗] calico.yaml 下载失败"
    exit 1
fi

# --- 完成 ---
echo ""
echo "=========================================="
echo " 离线包制备完成！"
echo "   packages/: $(ls "$PKG_DIR"/*.deb 2>/dev/null | wc -l) 个 deb + Packages.gz"
echo "   images/:   $(ls "$IMG_DIR"/*.tar 2>/dev/null | tr '\n' ' ')"
echo "   manifests/: calico.yaml"
echo ""
echo " 打包并分发到离线节点："
echo "   cd ${OFFLINE_BASE}/.. && tar czf k8s-offline-ubuntu-${UBUNTU_CODENAME}.tar.gz ubuntu/offline/"
echo "   各节点解压到 /opt/k8s-deploy/ 后执行 scripts/import-resources.sh"
echo "=========================================="
