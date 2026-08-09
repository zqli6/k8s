#!/bin/bash
# ============================================================
# 00-env-check.sh
# 执行节点：全部节点（master1 通过 ssh 分发，或各节点本地执行）
# 功能：部署前环境检查，不做任何修改
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
log_err() { echo -e "${RED}[✗]${NC} $1"; ERRORS=$((ERRORS+1)); }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; WARNINGS=$((WARNINGS+1)); }

echo "=========================================="
echo " K8s 1.28 部署前环境检查"
echo " 节点: $(hostname) / $(hostname -I | awk '{print $1}')"
echo "=========================================="
echo ""

# --- 1. 操作系统检查 ---
echo "--- 操作系统 ---"
if [ -f /etc/centos-release ]; then
    OS_VER=$(cat /etc/centos-release)
    log_ok "操作系统: $OS_VER"
else
    log_err "非 CentOS 系统，本脚本仅支持 CentOS 7.x"
fi

ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    log_ok "架构: $ARCH"
else
    log_err "不支持的架构: $ARCH（需要 x86_64）"
fi

# --- 2. 硬件资源 ---
echo ""
echo "--- 硬件资源 ---"
CPU_CORES=$(nproc)
if [ "$CPU_CORES" -ge 2 ]; then
    log_ok "CPU 核数: ${CPU_CORES} (>=2)"
else
    log_err "CPU 核数不足: ${CPU_CORES} (需要 >=2)"
fi

MEM_MB=$(free -m | awk '/Mem:/{print $2}')
if [ "$MEM_MB" -ge 1800 ]; then
    log_ok "内存: ${MEM_MB}MB (>=1800MB)"
else
    log_err "内存不足: ${MEM_MB}MB (需要 >=2GB)"
fi

DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
if [ "$DISK_GB" -ge 20 ]; then
    log_ok "根分区可用空间: ${DISK_GB}GB (>=20GB)"
else
    log_warn "根分区可用空间较少: ${DISK_GB}GB (建议 >=20GB)"
fi

# --- 3. 网络检查 ---
echo ""
echo "--- 网络 ---"
LOCAL_IP=$(hostname -I | awk '{print $1}')
log_ok "本机 IP: $LOCAL_IP"

DEFAULT_NIC=$(ip route show default | awk '/default/{print $5; exit}')
if [ -n "$DEFAULT_NIC" ]; then
    log_ok "默认路由网卡: $DEFAULT_NIC"
else
    log_err "无法探测默认路由网卡"
fi

if echo "$LOCAL_IP" | grep -q "^192\.168\.104\."; then
    log_ok "IP 在目标网段 192.168.104.0/24 内"
else
    log_warn "IP ($LOCAL_IP) 不在 192.168.104.0/24 网段"
fi

# 检查 VIP 是否冲突
if ping -c 1 -W 1 "$VIP" &>/dev/null; then
    log_warn "VIP $VIP 当前可 ping 通，可能已被占用（若集群已部署则正常）"
else
    log_ok "VIP $VIP 当前无响应（未被占用）"
fi

# --- 4. 端口检查 ---
echo ""
echo "--- 端口占用 ---"
PORTS_TO_CHECK="6443 10250 10259 10257 2379 2380"
for port in $PORTS_TO_CHECK; do
    if ss -tlnp | grep -q ":${port} "; then
        log_warn "端口 $port 已被占用"
    fi
done

# --- 5. 已有 K8s 检查 ---
echo ""
echo "--- 已有 K8s 组件 ---"
if command -v kubelet &>/dev/null; then
    KUBELET_VER=$(kubelet --version 2>/dev/null | awk '{print $2}')
    log_warn "kubelet 已安装: $KUBELET_VER"
else
    log_ok "kubelet 未安装"
fi

if [ -f /etc/kubernetes/admin.conf ]; then
    log_warn "/etc/kubernetes/admin.conf 已存在（集群可能已初始化）"
fi

if command -v containerd &>/dev/null; then
    CTR_VER=$(containerd --version 2>/dev/null | awk '{print $3}')
    log_warn "containerd 已安装: $CTR_VER"
else
    log_ok "containerd 未安装"
fi

# --- 6. swap ---
echo ""
echo "--- Swap ---"
SWAP_TOTAL=$(free -m | awk '/Swap:/{print $2}')
if [ "$SWAP_TOTAL" -eq 0 ]; then
    log_ok "Swap 已关闭"
else
    log_warn "Swap 未关闭: ${SWAP_TOTAL}MB（部署前需关闭）"
fi

# --- 7. SELinux ---
echo ""
echo "--- SELinux ---"
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
if [ "$SELINUX_STATUS" == "Enforcing" ]; then
    log_warn "SELinux 为 Enforcing（部署前需设为 Permissive 或 Disabled）"
else
    log_ok "SELinux: $SELINUX_STATUS"
fi

# --- 8. 防火墙 ---
echo ""
echo "--- 防火墙 ---"
if systemctl is-active --quiet firewalld 2>/dev/null; then
    log_warn "firewalld 正在运行（建议关闭或放行端口）"
else
    log_ok "firewalld 未运行"
fi

# --- 9. 时间同步 ---
echo ""
echo "--- 时间 ---"
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log_ok "当前时间: $CURRENT_TIME"
if systemctl is-active --quiet chronyd 2>/dev/null || systemctl is-active --quiet ntpd 2>/dev/null; then
    log_ok "时间同步服务运行中"
else
    log_warn "未检测到时间同步服务（建议安装 chrony）"
fi

# --- 10. 内核模块 ---
echo ""
echo "--- 内核模块 ---"
for mod in overlay br_netfilter; do
    if lsmod | grep -q "^${mod}"; then
        log_ok "模块 $mod 已加载"
    else
        log_warn "模块 $mod 未加载（部署时会自动加载）"
    fi
done

# --- 汇总 ---
echo ""
echo "=========================================="
echo -e " 检查完成: ${RED}${ERRORS} 错误${NC}, ${YELLOW}${WARNINGS} 警告${NC}"
echo "=========================================="

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}存在阻断性错误，需先解决后再部署${NC}"
    exit 1
fi
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}存在警告项，部署脚本会自动处理大部分，请确认后继续${NC}"
fi
exit 0
