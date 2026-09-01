#!/bin/bash
# ============================================================
# 02-install-containerd.sh
# 执行节点：全部节点（9台都要跑）
# 功能：安装 containerd 并配置为 K8s 运行时
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 安装 containerd: $(hostname)"
echo "=========================================="

# --- 幂等检查 ---
if command -v containerd &>/dev/null; then
    CURRENT_VER=$(containerd --version | awk '{print $3}')
    echo "[=] containerd 已安装: $CURRENT_VER"
    echo "    如需重新安装请先 yum remove containerd.io"
    # 不退出，继续确保配置正确
fi

# --- 1. 配置阿里云 docker-ce 源 ---
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    yum-config-manager --add-repo "$DOCKER_CE_REPO"
    # 替换为阿里云地址（repo 文件中 download.docker.com 替换为 mirrors.aliyun.com/docker-ce）
    sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
    echo "[✓] docker-ce yum 源已配置（阿里云）"
else
    echo "[=] docker-ce repo 已存在"
fi

# --- 2. 安装 containerd ---
yum install -y containerd.io > /dev/null 2>&1
echo "[✓] containerd.io 已安装"

# --- 3. 生成并修改配置 ---
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 修改 SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo "[✓] SystemdCgroup 已设为 true"

# 修改 sandbox_image 为阿里云 pause 镜像
sed -i "s|sandbox_image = .*|sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
echo "[✓] sandbox_image 已设为 ${PAUSE_IMAGE}"

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

# --- 6. 配置私有仓库信任（自签证书 / HTTP / 跳过 TLS）---
# containerd 1.6+ 用 certs.d 目录管理每个仓库的 TLS 与认证。
# 由 cluster.env 的以下变量控制：
#   PRIVATE_REGISTRY       私有仓库地址（含项目，如 harbor.example.com/k8s）
#   REGISTRY_CA_FILE       CA 证书路径（自签证书时填，留空则用下面的 TLS 策略）
#   REGISTRY_TLS_INSECURE  =true 时跳过 TLS 校验（自签又没 CA、或纯 HTTP 时用）
#   REGISTRY_PROTOCOL      https（默认）或 http
if [ -n "${PRIVATE_REGISTRY}" ]; then
    REG_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)     # harbor.example.com[:port]
    CERTS_D="/etc/containerd/certs.d/${REG_HOST}"
    mkdir -p "$CERTS_D"

    PROTO="${REGISTRY_PROTOCOL:-https}"
    HOSTS_TOML="${CERTS_D}/hosts.toml"

    if [ -n "${REGISTRY_CA_FILE}" ] && [ -f "${REGISTRY_CA_FILE}" ]; then
        # 情况 A：提供了自签 CA 证书 → 信任该 CA
        cp "${REGISTRY_CA_FILE}" "${CERTS_D}/ca.crt"
        cat > "$HOSTS_TOML" <<TOML
server = "${PROTO}://${REG_HOST}"

[host."${PROTO}://${REG_HOST}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "${CERTS_D}/ca.crt"
TOML
        echo "[✓] 私有仓库 ${REG_HOST} 已信任自签 CA: ${CERTS_D}/ca.crt"
    elif [ "${REGISTRY_TLS_INSECURE}" == "true" ] || [ "$PROTO" == "http" ]; then
        # 情况 B：跳过 TLS 校验（自签无 CA）或纯 HTTP 仓库
        cat > "$HOSTS_TOML" <<TOML
server = "${PROTO}://${REG_HOST}"

[host."${PROTO}://${REG_HOST}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
TOML
        echo "[✓] 私有仓库 ${REG_HOST} 已配置 skip_verify=true（${PROTO}）"
    else
        # 情况 C：受信任 CA 签发的证书（如 Let's Encrypt），无需额外配置
        cat > "$HOSTS_TOML" <<TOML
server = "https://${REG_HOST}"

[host."https://${REG_HOST}"]
  capabilities = ["pull", "resolve", "push"]
TOML
        echo "[✓] 私有仓库 ${REG_HOST} 使用系统信任的证书（无需额外 CA）"
    fi

    # 确保 config.toml 启用 certs.d（config_path）
    # containerd config default 会生成 config_path = ""，直接替换避免重复
    if grep -q 'config_path = ""' /etc/containerd/config.toml; then
        sed -i 's|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
        echo "[✓] containerd 已启用 certs.d 目录（替换默认空值）"
    elif ! grep -q 'config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml; then
        sed -i 's|\(\[plugins."io.containerd.grpc.v1.cri".registry\]\)|\1\n      config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
        echo "[✓] containerd 已启用 certs.d 目录"
    fi
    systemctl restart containerd
fi

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
