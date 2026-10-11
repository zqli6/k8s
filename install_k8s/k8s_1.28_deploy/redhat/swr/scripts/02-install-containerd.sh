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

# --- 6. 配置华为云 SWR 拉取（受信 TLS + private 组织认证）---
# SWR 用华为云受信 CA 证书，无需 CA/skip_verify。
# 关键：private 组织时，控制面/kube-vip 是 static pod 由 kubelet 直接拉取，
# 不认 imagePullSecrets，必须在 containerd 层（hosts.toml）配 SWR 登录认证。
if [ -n "${PRIVATE_REGISTRY}" ]; then
    REG_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)   # swr.<region>.myhuaweicloud.com
    CERTS_D="/etc/containerd/certs.d/${REG_HOST}"
    mkdir -p "$CERTS_D"
    HOSTS_TOML="${CERTS_D}/hosts.toml"

    # hosts.toml 只管路由与 capabilities（containerd 的 hosts.toml 不支持 auth 字段，
    # 写了会被静默忽略——已核实 containerd 官方文档，认证必须走 config.toml）
    {
        echo "server = \"https://${REG_HOST}\""
        echo ""
        echo "[host.\"https://${REG_HOST}\"]"
        echo "  capabilities = [\"pull\", \"resolve\"]"
    } > "$HOSTS_TOML"

    # 确保 config.toml 启用 certs.d（替换默认空值，避免重复键导致 containerd 启动失败）
    if grep -q '^[[:space:]]*config_path = ""' /etc/containerd/config.toml; then
        sed -i 's|^[[:space:]]*config_path = ""|      config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
    elif ! grep -q '^[[:space:]]*config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml; then
        sed -i 's|\(\[plugins."io.containerd.grpc.v1.cri".registry\]\)|\1\n      config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
    fi
    echo "[✓] containerd 已启用 certs.d 目录"

    # private 组织：凭据写进 config.toml 的 registry.configs.auth（containerd 1.6 支持）
    # 控制面/kube-vip 是 static pod 由 kubelet 直接拉，不认 imagePullSecrets，故须配在此。
    if [ "${SWR_PRIVATE}" == "true" ]; then
        if [ -z "${SWR_AK}" ] || [ -z "${SWR_LOGIN_KEY}" ]; then
            echo "[✗] SWR 为 private 组织，但 cluster.env 未填 SWR_AK / SWR_LOGIN_KEY" >&2
            echo "    请手动在 SWR 控制台生成登录指令，将 AK 和登录密钥填入 cluster.env 后重新执行本脚本。" >&2
            echo "    未完成认证前，控制面 static pod 无法从 SWR 拉取镜像，kubeadm init 会失败。" >&2
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
