#!/bin/bash
# ============================================================
# import-resources.sh
# 执行节点：全部节点（9台都要跑）
# 前置：将 k8s-offline-v1.28.15.tar.gz 解压到 /opt/k8s-offline/
# 功能：配置本地 yum repo + 导入容器镜像
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 离线资源导入: $(hostname)"
echo "=========================================="

# 离线资源根目录 = offline 目录本身（scripts 的上一级），开箱即用
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/images" ]; then
    OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
fi
echo "离线资源目录: $OFFLINE_BASE"
echo "  images/   镜像 tar（k8s-core / calico / kube-vip）"
echo "  packages/ 离线 RPM 包（可选，无则用在线 yum 源）"

# --- 1. 配置本地 yum repo ---
echo ""
echo "--- 配置本地 yum 源 ---"
RPMS_DIR="${OFFLINE_BASE}/packages"

if [ ! -f "${RPMS_DIR}/repodata/repomd.xml" ] || ! compgen -G "${RPMS_DIR}/*.rpm" > /dev/null; then
    echo "[✗] 未找到完整 RPM 仓库: $RPMS_DIR"
    echo "    完全离线部署需要 RPM 文件和 repodata/repomd.xml。"
    exit 1
fi

# 备份并禁用原有在线源
mkdir -p /etc/yum.repos.d/backup
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true

# 创建本地 repo
cat > /etc/yum.repos.d/k8s-local.repo <<EOF
[k8s-local]
name=Kubernetes Local Offline Repo
baseurl=file://${RPMS_DIR}
enabled=1
gpgcheck=0
EOF

yum clean all > /dev/null 2>&1
yum makecache fast > /dev/null 2>&1
echo "[✓] 本地 yum 源已配置: file://${RPMS_DIR}"

# 验证 repo 可用
echo "验证本地 repo..."
if yum --disablerepo='*' --enablerepo='k8s-local' list containerd.io &>/dev/null; then
    echo "[✓] containerd.io 包可用"
else
    echo "[!] containerd.io 包未找到，检查 RPM 目录"
fi
if yum --disablerepo='*' --enablerepo='k8s-local' list kubeadm &>/dev/null; then
    echo "[✓] kubeadm 包可用"
else
    echo "[!] kubeadm 包未找到"
fi

# --- 2. 导入容器镜像 ---
echo ""
echo "--- 导入容器镜像 ---"
IMAGES_DIR="${OFFLINE_BASE}/images"

if [ ! -d "$IMAGES_DIR" ]; then
    echo "[✗] 未找到镜像目录: $IMAGES_DIR"
    exit 1
fi

# 确保 containerd 运行
if ! systemctl is-active --quiet containerd 2>/dev/null; then
    echo "[!] containerd 未运行，先安装..."
    yum install -y containerd.io > /dev/null 2>&1
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sed -i "s|sandbox_image = .*|sandbox_image = \"${PAUSE_IMAGE}\"|" /etc/containerd/config.toml
    systemctl enable containerd --now
    systemctl restart containerd
    sleep 3
fi

# 导入所有 tar 镜像（namespace 必须是 k8s.io，否则 kubelet 看不到）
for tar_file in "${IMAGES_DIR}"/*.tar; do
    if [ -f "$tar_file" ]; then
        echo "  导入: $(basename $tar_file)"
        ctr -n k8s.io images import "$tar_file" 2>/dev/null || {
            echo "  [!] 导入失败: $tar_file"
        }
    fi
done
echo "[✓] 镜像导入完成"

# --- 3. 验证镜像完整性 ---
echo ""
echo "--- 验证镜像 ---"

# 获取 kubeadm 期望的镜像清单
EXPECTED_IMAGES=""
if command -v kubeadm &>/dev/null; then
    EXPECTED_IMAGES=$(kubeadm config images list --kubernetes-version "v${KUBE_VERSION}" --image-repository "${IMAGE_REPOSITORY}" 2>/dev/null)
elif yum list installed kubeadm 2>/dev/null | grep -q kubeadm; then
    EXPECTED_IMAGES=$(kubeadm config images list --kubernetes-version "v${KUBE_VERSION}" --image-repository "${IMAGE_REPOSITORY}" 2>/dev/null)
fi

# 列出已导入镜像
echo "已导入镜像:"
ctr -n k8s.io images list -q 2>/dev/null | head -20
IMPORTED_COUNT=$(ctr -n k8s.io images list -q 2>/dev/null | wc -l)
echo "  总计: $IMPORTED_COUNT 个镜像"

# 对比检查（如果 kubeadm 已安装）
if [ -n "$EXPECTED_IMAGES" ]; then
    echo ""
    echo "镜像清单对比:"
    MISSING=0
    for img in $EXPECTED_IMAGES; do
        if ctr -n k8s.io images list -q | grep -q "$img"; then
            echo "  [✓] $img"
        else
            echo "  [✗] 缺失: $img"
            MISSING=$((MISSING+1))
        fi
    done
    if [ $MISSING -gt 0 ]; then
        echo "[!] 缺少 $MISSING 个镜像，init 可能失败"
    else
        echo "[✓] K8s 核心镜像齐全"
    fi
fi

# --- 4. 安装基础依赖 ---
echo ""
echo "--- 安装基础依赖（从本地 repo）---"
# containerd/kubeadm 先使用的本地仓库已在本脚本开头配置。
yum --disablerepo='*' --enablerepo=k8s-local install -y \
    conntrack-tools socat ipset ipvsadm chrony bash-completion \
    wget curl net-tools yum-utils > /dev/null 2>&1
echo "[✓] 基础依赖已安装"

# --- 5. 恢复在线源（可选） ---
# 如果后续需要恢复在线源，取消下面注释
# mv /etc/yum.repos.d/backup/*.repo /etc/yum.repos.d/ 2>/dev/null
# rm -f /etc/yum.repos.d/k8s-local.repo

echo ""
echo "=========================================="
echo " 离线资源导入完成！"
echo ""
echo " 后续步骤（与在线版相同）："
echo "   1. 执行 01-system-init.sh（跳过 yum install 部分已由本脚本完成）"
echo "   2. 执行 02-install-containerd.sh（containerd 已安装，会跳过）"
echo "   3. 执行 03-install-k8s.sh（使用本地 repo）"
echo "   4. 执行 04-init-master1.sh（跳过 images pull，镜像已导入）"
echo "   5. 后续 05-09 与在线版完全相同"
echo "=========================================="
