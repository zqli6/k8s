#!/bin/bash
# ============================================================
# 00-env-check.sh
# 执行节点：全部节点
# 功能：部署前环境检查（Ubuntu + SWR 版），不做任何修改
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
log_err() { echo -e "${RED}[✗]${NC} $1"; ERRORS=$((ERRORS+1)); }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; WARNINGS=$((WARNINGS+1)); }

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi

echo "=========================================="
echo " K8s 1.28 部署前环境检查 (Ubuntu + SWR)"
echo " 节点: $(hostname) / $(hostname -I | awk '{print $1}')"
echo "=========================================="
echo ""

# --- 1. 操作系统检查 ---
echo "--- 操作系统 ---"
if [ -f /etc/os-release ] && grep -q '^ID=ubuntu' /etc/os-release; then
    . /etc/os-release
    log_ok "操作系统: Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"
    if [ "${VERSION_CODENAME}" != "jammy" ] && [ "${VERSION_CODENAME}" != "noble" ]; then
        log_warn "codename=${VERSION_CODENAME}，本方案验证的是 jammy(22.04)/noble(24.04)"
    fi
else
    log_err "非 Ubuntu 系统，本脚本仅支持 Ubuntu 22.04/24.04"
fi

ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    log_ok "架构: $ARCH"
else
    log_err "不支持的架构: $ARCH（需要 x86_64）"
fi

if [ "${KUBE_PROXY_MODE}" != "ipvs" ] && [ "${KUBE_PROXY_MODE}" != "iptables" ]; then
    log_err "不支持的 kube-proxy 模式: ${KUBE_PROXY_MODE}"
else
    log_ok "kube-proxy 模式: ${KUBE_PROXY_MODE}"
fi

CPU_CORES=$(nproc)
[ "$CPU_CORES" -ge 2 ] && log_ok "CPU 核数: ${CPU_CORES} (>=2)" || log_err "CPU 核数不足: ${CPU_CORES}"

MEM_MB=$(free -m | awk '/Mem:/{print $2}')
[ "$MEM_MB" -ge 1800 ] && log_ok "内存: ${MEM_MB}MB" || log_err "内存不足: ${MEM_MB}MB"

DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
[ "$DISK_GB" -ge 20 ] && log_ok "根分区可用: ${DISK_GB}GB" || log_warn "根分区可用较少: ${DISK_GB}GB"

# --- 2. 网络检查 ---
echo ""
echo "--- 网络 ---"
LOCAL_IP=$(hostname -I | awk '{print $1}')
log_ok "本机 IP: $LOCAL_IP"

DEFAULT_NIC=$(ip route show default | awk '/default/{print $5; exit}')
[ -n "$DEFAULT_NIC" ] && log_ok "默认路由网卡: $DEFAULT_NIC" || log_err "无法探测默认路由网卡"

CIDR_PREFIX=$(echo "${NODE_CIDR}" | sed 's|/[0-9]*$||' | sed 's|\.[0-9]*$||')
if echo "$LOCAL_IP" | grep -q "^${CIDR_PREFIX}\."; then
    log_ok "IP 在目标网段 ${NODE_CIDR} 内"
else
    log_warn "IP ($LOCAL_IP) 不在 ${NODE_CIDR} 网段"
fi

if ping -c 1 -W 1 "$VIP" &>/dev/null; then
    log_warn "VIP $VIP 当前可 ping 通，可能已被占用"
else
    log_ok "VIP $VIP 当前无响应"
fi

# --- 3. SWR 仓库检查 ---
echo ""
echo "--- SWR 仓库 ---"
if [ -n "${PRIVATE_REGISTRY}" ]; then
    REG_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)
    log_ok "SWR 仓库: ${PRIVATE_REGISTRY}"
    if [ "${SWR_PRIVATE}" == "true" ] && { [ -z "${SWR_AK}" ] || [ -z "${SWR_LOGIN_KEY}" ]; }; then
        log_err "SWR 为 private 组织但未填 SWR_AK / SWR_LOGIN_KEY"
    fi
    # 检查能否解析 SWR 域名（能访问外网即可）
    if getent hosts "$REG_HOST" &>/dev/null; then
        log_ok "SWR 域名可解析: $REG_HOST"
    else
        log_warn "SWR 域名解析失败，需能访问 swr.<region>.myhuaweicloud.com"
    fi
else
    log_err "未配置 PRIVATE_REGISTRY"
fi

# --- 4. 端口检查 ---
echo ""
echo "--- 端口占用 ---"
for port in 6443 10250 10259 10257 2379 2380; do
    ss -tlnp | grep -q ":${port} " && log_warn "端口 $port 已被占用"
done

# --- 5. 已有 K8s / containerd ---
echo ""
echo "--- 已有组件 ---"
command -v kubelet &>/dev/null && log_warn "kubelet 已安装: $(kubelet --version 2>/dev/null | awk '{print $2}')" || log_ok "kubelet 未安装"
[ -f /etc/kubernetes/admin.conf ] && log_warn "/etc/kubernetes/admin.conf 已存在"
command -v containerd &>/dev/null && log_warn "containerd 已安装: $(containerd --version 2>/dev/null | awk '{print $3}')" || log_ok "containerd 未安装"

# --- 6. swap / AppArmor / 防火墙 / 时间 ---
echo ""
echo "--- 系统状态 ---"
SWAP_TOTAL=$(free -m | awk '/Swap:/{print $2}')
[ "$SWAP_TOTAL" -eq 0 ] && log_ok "Swap 已关闭" || log_warn "Swap 未关闭: ${SWAP_TOTAL}MB"

command -v aa-status &>/dev/null && log_ok "AppArmor 已启用（Ubuntu 默认）" || log_warn "未检测到 AppArmor"

if systemctl is-active --quiet ufw 2>/dev/null; then
    log_warn "ufw 正在运行"
else
    log_ok "ufw 未运行"
fi

if systemctl is-active --quiet chrony 2>/dev/null || systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
    log_ok "时间同步服务运行中"
else
    log_warn "未检测到时间同步服务"
fi

# --- 7. 内核模块 ---
echo ""
echo "--- 内核模块 ---"
for mod in overlay br_netfilter; do
    lsmod | grep -q "^${mod}" && log_ok "模块 $mod 已加载" || log_warn "模块 $mod 未加载"
done

# --- 汇总 ---
echo ""
echo "=========================================="
echo -e " 检查完成: ${RED}${ERRORS} 错误${NC}, ${YELLOW}${WARNINGS} 警告${NC}"
echo "=========================================="
[ $ERRORS -gt 0 ] && { echo -e "${RED}存在阻断性错误${NC}"; exit 1; }
exit 0
