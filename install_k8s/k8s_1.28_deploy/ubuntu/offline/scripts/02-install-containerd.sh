#!/bin/bash
# ============================================================
# 02-install-containerd.sh
# 执行节点：全部节点
# 功能：安装 containerd（Ubuntu 离线版，仅使用本地 deb 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env
export DEBIAN_FRONTEND=noninteractive

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi

echo "=========================================="
echo " 安装 containerd: $(hostname)  (Ubuntu ${UBUNTU_CODENAME})"
echo "=========================================="

OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/packages" ]; then
    OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
fi
DEBS_DIR="${OFFLINE_BASE}/packages"

if ! compgen -G "${DEBS_DIR}/*.deb" > /dev/null; then
    echo "[✗] 未找到本地 deb 包，离线部署不能继续: ${DEBS_DIR}"
    exit 1
fi
if [ ! -f "${DEBS_DIR}/Packages.gz" ]; then
    command -v dpkg-scanpackages >/dev/null 2>&1 || { echo "[✗] 缺少 dpkg-scanpackages"; exit 1; }
    dpkg-scanpackages "${DEBS_DIR}" /dev/null | gzip -9c > "${DEBS_DIR}/Packages.gz"
fi

mkdir -p /etc/apt/sources.list.d/backup
if [ -s /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.d/backup/sources.list.bak 2>/dev/null || true
    : > /etc/apt/sources.list
fi
for source in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$source" ] || continue
    [ "$source" = "/etc/apt/sources.list.d/k8s-local.list" ] && continue
    mv "$source" /etc/apt/sources.list.d/backup/
done
cat > /etc/apt/sources.list.d/k8s-local.list <<EOF
deb [trusted=yes] file:${DEBS_DIR} ./
EOF
apt-get update > /dev/null 2>&1
echo "[✓] 使用本地 deb 源: file:${DEBS_DIR}"

apt-get install -y containerd > /dev/null 2>&1
echo "[✓] Ubuntu containerd 已安装"

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if grep -qE '^[[:space:]]*sandbox_image[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox_image = .*|    sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
elif grep -qE '^[[:space:]]*sandbox[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox = .*|      sandbox = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
else
    echo "[✗] 未识别 containerd sandbox 配置项"
    exit 1
fi
systemctl daemon-reload
systemctl enable containerd --now
systemctl restart containerd
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF

echo "[✓] SystemdCgroup 已设为 true"
echo "[✓] sandbox 镜像已设为 ${PAUSE_IMAGE}"
echo "containerd 版本: $(containerd --version)"
echo "containerd 状态: $(systemctl is-active containerd)"
[ "$(systemctl is-active containerd)" = "active" ]
