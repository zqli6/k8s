#!/bin/bash
# ============================================================
# 02-install-containerd.sh
# 执行节点：全部节点
# 功能：安装 containerd 并配置为 K8s 运行时（Ubuntu 版，阿里云 docker-ce apt 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

# 探测 Ubuntu codename
if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi
export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 安装 containerd: $(hostname)  (Ubuntu ${UBUNTU_CODENAME})"
echo "=========================================="

# --- 幂等检查 ---
if command -v containerd &>/dev/null; then
    CURRENT_VER=$(containerd --version | awk '{print $3}')
    echo "[=] containerd 已安装: $CURRENT_VER"
    echo "    如需重新安装请先: apt-get remove -y containerd.io"
    # 不退出，继续确保配置正确
fi

# --- 1. 使用 Ubuntu 系统仓库中的 containerd ---
# Ubuntu 24.04 提供 containerd（1.7.x），无需依赖 Docker CE 仓库。
# Docker CE 仓库的 containerd.io 在部分镜像环境中不可用，且可能因公钥
# 轮换导致 apt-get update 失败，因此 Ubuntu 版不再主动配置该仓库。
DOCKER_REPO_FILE="/etc/apt/sources.list.d/docker.list"
if [ -f "$DOCKER_REPO_FILE" ]; then
    mv "$DOCKER_REPO_FILE" "${DOCKER_REPO_FILE}.disabled"
    echo "[✓] 已禁用 Docker CE apt 源（Ubuntu 使用系统 containerd 包）"
fi
apt-get update > /dev/null 2>&1

# --- 2. 安装 containerd ---
apt-get install -y containerd > /dev/null 2>&1
echo "[✓] Ubuntu containerd 已安装"

# --- 3. 生成并修改配置 ---
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 修改 SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo "[✓] SystemdCgroup 已设为 true"

# 修改 sandbox 镜像。containerd 1.x 使用 sandbox_image，2.x(v3 config) 使用 sandbox。
if grep -qE '^[[:space:]]*sandbox_image[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox_image = .*|    sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
elif grep -qE '^[[:space:]]*sandbox[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox = .*|      sandbox = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
else
    echo "[✗] 未识别 containerd sandbox 配置项"
    exit 1
fi
echo "[✓] sandbox 镜像已设为 ${PAUSE_IMAGE}"

# --- 4. 启动 containerd ---
systemctl daemon-reload
systemctl enable containerd --now
systemctl restart containerd
echo "[✓] containerd 已启动"

# --- 5. 配置 crictl ---
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF
echo "[✓] crictl 已配置"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "containerd 版本: $(containerd --version)"
echo "SystemdCgroup: $(grep 'SystemdCgroup' /etc/containerd/config.toml | head -1 | xargs)"
echo "sandbox_image: $(grep 'sandbox_image' /etc/containerd/config.toml | xargs)"
echo "containerd 状态: $(systemctl is-active containerd)"

if systemctl is-active --quiet containerd; then
    echo ""
    echo "[完成] containerd 安装配置完毕"
else
    echo ""
    echo "[错误] containerd 未正常运行，请检查日志: journalctl -u containerd"
    exit 1
fi
