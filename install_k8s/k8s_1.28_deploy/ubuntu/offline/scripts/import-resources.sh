#!/bin/bash
# ============================================================
# import-resources.sh
# 执行节点：全部离线节点
# 前置：将 offline 目录（含 packages/images/manifests）分发到各节点
# 功能：配置本地 deb 源 + 导入容器镜像 + 安装基础依赖（Ubuntu 离线版）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 离线资源导入: $(hostname)"
echo "=========================================="

# 离线资源根目录 = offline 目录本身（scripts 的上一级）
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/images" ]; then
    OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
fi
echo "离线资源目录: $OFFLINE_BASE"

# --- 1. 配置本地 deb 源 ---
echo ""
echo "--- 1. 配置本地 deb 源 ---"
DEBS_DIR="${OFFLINE_BASE}/packages"

if ! compgen -G "${DEBS_DIR}/*.deb" > /dev/null; then
    echo "[✗] 未找到 deb 包: $DEBS_DIR"
    exit 1
fi

# 生成 Packages 索引（若 fetch 时未生成）
if [ ! -f "${DEBS_DIR}/Packages.gz" ]; then
    command -v dpkg-scanpackages &>/dev/null || {
        echo "[✗] 未找到 dpkg-scanpackages，无法生成本地 deb 索引"
        exit 1
    }
    dpkg-scanpackages "${DEBS_DIR}" /dev/null | gzip -9c > "${DEBS_DIR}/Packages.gz"
    echo "[✓] 已生成 Packages.gz"
fi

# 禁用在线源（完全离线时避免 apt update 连外网超时）
# Ubuntu 22.04 用 .list、24.04 用 deb822 格式的 .sources，都要处理
mkdir -p /etc/apt/sources.list.d/backup
if [ -s /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.d/backup/sources.list.bak 2>/dev/null || true
    : > /etc/apt/sources.list
fi
mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/backup/ 2>/dev/null || true
# 仅保留本地 deb 源
cat > /etc/apt/sources.list.d/k8s-local.list <<EOF
deb [trusted=yes] file:${DEBS_DIR} ./
EOF
apt-get update > /dev/null 2>&1
echo "[✓] 本地 deb 源已配置: file:${DEBS_DIR}"

# --- 2. 导入容器镜像 ---
echo ""
echo "--- 2. 导入容器镜像 ---"
IMAGES_DIR="${OFFLINE_BASE}/images"

# 确保 containerd 运行（镜像导入需要）
if ! systemctl is-active --quiet containerd 2>/dev/null; then
    echo "[!] containerd 未运行，使用本地 deb 安装..."
    apt-get install -y containerd > /dev/null 2>&1
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    if grep -qE '^[[:space:]]*sandbox_image[[:space:]]*=' /etc/containerd/config.toml; then
        sed -i "s|^[[:space:]]*sandbox_image = .*|    sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
    elif grep -qE '^[[:space:]]*sandbox[[:space:]]*=' /etc/containerd/config.toml; then
        sed -i "s|^[[:space:]]*sandbox = .*|      sandbox = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
    fi
    systemctl enable containerd --now
    systemctl restart containerd
    sleep 3
fi

if [ ! -d "$IMAGES_DIR" ]; then
    echo "[✗] 未找到镜像目录: $IMAGES_DIR"
    exit 1
fi

for tar_file in "${IMAGES_DIR}"/*.tar; do
    if [ -f "$tar_file" ]; then
        echo "  导入: $(basename $tar_file)"
        ctr -n k8s.io images import "$tar_file" 2>/dev/null || echo "  [!] 导入失败: $tar_file"
    fi
done
echo "[✓] 镜像导入完成"

# --- 3. 验证镜像完整性 ---
echo ""
echo "--- 3. 验证镜像 ---"
EXPECTED_IMAGES=""
if command -v kubeadm &>/dev/null; then
    EXPECTED_IMAGES=$(kubeadm config images list --kubernetes-version "v${KUBE_VERSION}" --image-repository "${IMAGE_REPOSITORY}" 2>/dev/null)
fi
echo "已导入镜像:"
ctr -n k8s.io images list -q 2>/dev/null | head -20
IMPORTED_COUNT=$(ctr -n k8s.io images list -q 2>/dev/null | wc -l)
echo "  总计: $IMPORTED_COUNT 个镜像"

if [ -n "$EXPECTED_IMAGES" ]; then
    MISSING=0
    for img in $EXPECTED_IMAGES; do
        if ctr -n k8s.io images list -q | grep -q "$img"; then
            echo "  [✓] $img"
        else
            echo "  [✗] 缺失: $img"
            MISSING=$((MISSING+1))
        fi
    done
    [ $MISSING -gt 0 ] && echo "[!] 缺少 $MISSING 个镜像" || echo "[✓] K8s 核心镜像齐全"
fi

# --- 4. 安装基础依赖（从本地源）---
echo ""
echo "--- 4. 安装基础依赖 ---"
apt-get install -y conntrack socat ipset ipvsadm chrony \
    wget curl net-tools bash-completion ca-certificates gnupg > /dev/null 2>&1 || {
    echo "[!] 部分基础依赖安装失败（可能缺依赖包），继续..."
}
echo "[✓] 基础依赖已安装"

echo ""
echo "=========================================="
echo " 离线资源导入完成！"
echo " 后续步骤："
echo "   1. ./01-system-init.sh   系统初始化"
echo "   2. ./02-install-containerd.sh   安装 containerd（用本地 deb）"
echo "   3. ./03-install-k8s.sh   安装 kubeadm/kubelet/kubectl（用本地 deb）"
echo "   4. ./04-init-master1.sh  ... 后续与在线版相同"
echo "=========================================="
