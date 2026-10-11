#!/bin/bash
# ============================================================
# 00-env-check.sh
# 执行节点：全部节点
# 功能：部署前环境检查（Ubuntu 离线版），不做任何修改
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ERRORS=0; WARNINGS=0
log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
log_err() { echo -e "${RED}[✗]${NC} $1"; ERRORS=$((ERRORS+1)); }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; WARNINGS=$((WARNINGS+1)); }

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi

echo "=========================================="
echo " K8s 1.28 部署前环境检查 (Ubuntu 离线)"
echo " 节点: $(hostname) / $(hostname -I | awk '{print $1}')"
echo "=========================================="
echo ""

echo "--- 操作系统 ---"
if [ -f /etc/os-release ] && grep -q '^ID=ubuntu' /etc/os-release; then
    . /etc/os-release
    log_ok "Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"
else
    log_err "非 Ubuntu 系统"
fi

ARCH=$(uname -m)
[ "$ARCH" == "x86_64" ] && log_ok "架构: $ARCH" || log_err "架构: $ARCH"

CPU_CORES=$(nproc)
[ "$CPU_CORES" -ge 2 ] && log_ok "CPU: ${CPU_CORES} 核" || log_err "CPU 不足"

MEM_MB=$(free -m | awk '/Mem:/{print $2}')
[ "$MEM_MB" -ge 1800 ] && log_ok "内存: ${MEM_MB}MB" || log_err "内存不足"

DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
[ "$DISK_GB" -ge 20 ] && log_ok "磁盘: ${DISK_GB}GB" || log_warn "磁盘较少"

echo ""
echo "--- 网络 ---"
LOCAL_IP=$(hostname -I | awk '{print $1}')
log_ok "本机 IP: $LOCAL_IP"
DEFAULT_NIC=$(ip route show default | awk '/default/{print $5; exit}')
[ -n "$DEFAULT_NIC" ] && log_ok "默认网卡: $DEFAULT_NIC" || log_warn "无默认路由"
CIDR_PREFIX=$(echo "${NODE_CIDR}" | sed 's|/[0-9]*$||' | sed 's|\.[0-9]*$||')
echo "$LOCAL_IP" | grep -q "^${CIDR_PREFIX}\." && log_ok "IP 在 ${NODE_CIDR}" || log_warn "IP 不在 ${NODE_CIDR}"

echo ""
echo "--- 离线资源 ---"
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
[ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/packages" ] && OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
[ -f "${OFFLINE_BASE}/packages/Packages.gz" ] && log_ok "deb 索引 Packages.gz 存在" || log_warn "Packages.gz 不存在（先跑 import-resources.sh）"
DEB_NUM=$(ls "${OFFLINE_BASE}/packages"/*.deb 2>/dev/null | wc -l)
[ "$DEB_NUM" -gt 0 ] && log_ok "deb 包: ${DEB_NUM} 个" || log_warn "无 deb 包"
TAR_NUM=$(ls "${OFFLINE_BASE}/images"/*.tar 2>/dev/null | wc -l)
[ "$TAR_NUM" -ge 3 ] && log_ok "镜像 tar: ${TAR_NUM} 个" || log_warn "镜像 tar 不足 3 个"

echo ""
echo "--- 已有组件 ---"
command -v kubelet &>/dev/null && log_warn "kubelet 已安装" || log_ok "kubelet 未安装"
command -v containerd &>/dev/null && log_warn "containerd 已安装" || log_ok "containerd 未安装"
[ -f /etc/kubernetes/admin.conf ] && log_warn "集群可能已初始化"

echo ""
echo "--- 系统状态 ---"
SWAP_TOTAL=$(free -m | awk '/Swap:/{print $2}')
[ "$SWAP_TOTAL" -eq 0 ] && log_ok "Swap 已关闭" || log_warn "Swap 未关闭"
if systemctl is-active --quiet ufw 2>/dev/null; then log_warn "ufw 运行中"; else log_ok "ufw 未运行"; fi
if systemctl is-active --quiet chrony 2>/dev/null || systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then log_ok "时间同步运行中"; else log_warn "无时间同步"; fi

echo ""
echo "=========================================="
echo -e " 检查完成: ${RED}${ERRORS} 错误${NC}, ${YELLOW}${WARNINGS} 警告${NC}"
echo "=========================================="
[ $ERRORS -gt 0 ] && exit 1
exit 0
