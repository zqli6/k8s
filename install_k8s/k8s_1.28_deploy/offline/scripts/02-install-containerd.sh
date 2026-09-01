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

# --- 1. 配置软件包源 ---
# 优先使用本目录 packages/ 中的离线 RPM；没有完整离线包时才回退在线源。
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/packages" ]; then
    OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
fi
RPMS_DIR="${OFFLINE_BASE}/packages"
YUM_LOCAL_ARGS=()

if [ -f "${RPMS_DIR}/repodata/repomd.xml" ] && compgen -G "${RPMS_DIR}/*.rpm" > /dev/null; then
    cat > /etc/yum.repos.d/k8s-local.repo <<EOF
[k8s-local]
name=Kubernetes Local Offline Repo
baseurl=file://${RPMS_DIR}
enabled=1
gpgcheck=0
EOF
    yum clean metadata >/dev/null 2>&1 || true
    yum makecache --disablerepo='*' --enablerepo=k8s-local >/dev/null 2>&1
    YUM_LOCAL_ARGS=(--disablerepo='*' --enablerepo=k8s-local)
    echo "[✓] 使用本地 RPM 源: file://${RPMS_DIR}"
else
    echo "[!] 未找到完整本地 RPM 源，containerd 将使用配置的在线 yum 源"
    # 在线回退只在目标环境允许联网时可用。
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        yum-config-manager --add-repo "$DOCKER_CE_REPO"
        sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
        echo "[✓] docker-ce yum 源已配置（阿里云）"
    else
        echo "[=] docker-ce repo 已存在"
    fi
fi

# --- 2. 安装 containerd ---
yum "${YUM_LOCAL_ARGS[@]}" install -y containerd.io > /dev/null 2>&1
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
