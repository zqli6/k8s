#!/bin/bash
# ============================================================
# 02-install-containerd.sh
# 执行节点：全部节点
# 功能：安装 containerd 并配置 SWR 认证（Ubuntu 版）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi
export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 安装 containerd: $(hostname)  (Ubuntu ${UBUNTU_CODENAME})"
echo "=========================================="

# --- 1. 配置阿里云 docker-ce apt 源 ---
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL "$DOCKER_CE_GPGKEY" | gpg --batch --dearmor -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_CE_REPO} ${UBUNTU_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update > /dev/null 2>&1
    echo "[✓] docker-ce apt 源已配置（阿里云，${UBUNTU_CODENAME}）"
else
    echo "[=] docker-ce apt 源已存在"
fi

# --- 2. 安装 containerd（Ubuntu 系统包，非 containerd.io）---
apt-get install -y containerd > /dev/null 2>&1
echo "[✓] Ubuntu containerd 已安装"

# --- 3. 生成并修改配置 ---
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo "[✓] SystemdCgroup 已设为 true"

# 兼容 containerd 1.x (sandbox_image) 与 2.x (sandbox)
if grep -qE '^[[:space:]]*sandbox_image[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox_image = .*|    sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
elif grep -qE '^[[:space:]]*sandbox[[:space:]]*=' /etc/containerd/config.toml; then
    sed -i "s|^[[:space:]]*sandbox = .*|      sandbox = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
else
    echo "[✗] 未识别 containerd sandbox 配置项"
    exit 1
fi
echo "[✓] sandbox 镜像已设为 ${PAUSE_IMAGE}"

# --- 4. 配置 SWR 拉取认证 ---
# 控制面/kube-vip 是 static pod，由 kubelet 直接拉取，不认 imagePullSecrets，
# 必须在 containerd 层配置认证。
if [ -n "${PRIVATE_REGISTRY}" ]; then
    REG_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)
    CERTS_D="/etc/containerd/certs.d/${REG_HOST}"
    mkdir -p "$CERTS_D"

    # hosts.toml 只管路由与 capabilities（不支持 auth，认证走 config.toml）
    {
        echo "server = \"https://${REG_HOST}\""
        echo ""
        echo "[host.\"https://${REG_HOST}\"]"
        echo "  capabilities = [\"pull\", \"resolve\"]"
    } > "${CERTS_D}/hosts.toml"

    # 确保 config.toml 启用 certs.d
    if grep -q "^[[:space:]]*config_path = ''" /etc/containerd/config.toml; then
        sed -i "s|^[[:space:]]*config_path = ''|      config_path = '/etc/containerd/certs.d'|" /etc/containerd/config.toml
    elif grep -q "^[[:space:]]*config_path = \"\"" /etc/containerd/config.toml; then
        sed -i 's|^[[:space:]]*config_path = ""|      config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
    elif ! grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml; then
        sed -i "s|\(\[plugins.'io.containerd.cri.v1.images'.registry\]\)|\1\n      config_path = '/etc/containerd/certs.d'|" /etc/containerd/config.toml
    fi
    echo "[✓] containerd 已启用 certs.d 目录"

    # private 组织：凭据写进 config.toml
    if [ "${SWR_PRIVATE}" == "true" ]; then
        if [ -z "${SWR_AK}" ] || [ -z "${SWR_LOGIN_KEY}" ]; then
            echo "[✗] SWR 为 private 组织，但 cluster.env 未填 SWR_AK / SWR_LOGIN_KEY" >&2
            exit 1
        fi
        if ! grep -q "registry.configs.\"${REG_HOST}\".auth" /etc/containerd/config.toml; then
            cat >> /etc/containerd/config.toml <<EOF

[plugins."io.containerd.grpc.v1.cri".registry.configs."${REG_HOST}".auth]
  username = "${SWR_USERNAME}"
  password = "${SWR_LOGIN_KEY}"
EOF
        fi
        chmod 600 /etc/containerd/config.toml
        echo "[✓] SWR ${REG_HOST} 已在 config.toml 配置 private 认证（用户 ${SWR_USERNAME}）"
    else
        echo "[✓] SWR ${REG_HOST} 公开组织，匿名拉取"
    fi
fi

# --- 5. 启动 containerd ---
systemctl daemon-reload
systemctl enable containerd --now
systemctl restart containerd
echo "[✓] containerd 已启动"

# --- 6. 配置 crictl ---
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF
echo "[✓] crictl 已配置"

# --- 验证 ---
echo ""
echo "containerd 版本: $(containerd --version)"
echo "containerd 状态: $(systemctl is-active containerd)"
if systemctl is-active --quiet containerd; then
    echo "[完成] containerd 安装配置完毕"
else
    echo "[错误] containerd 未正常运行，检查: journalctl -u containerd"
    exit 1
fi
