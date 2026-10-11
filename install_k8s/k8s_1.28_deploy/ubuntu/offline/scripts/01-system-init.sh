#!/bin/bash
# ============================================================
# 01-system-init.sh
# 执行节点：全部节点
# 功能：系统初始化（Ubuntu 离线版，基础工具优先用本地 deb 源）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi
export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo " 系统初始化: $(hostname)  (Ubuntu ${UBUNTU_CODENAME})"
echo "=========================================="

# --- 1. 设置 hostname ---
LOCAL_IP=$(hostname -I | awk '{print $1}')
HOSTNAME_SET=""
for i in "${!ALL_NODES[@]}"; do
    if [ "${ALL_NODES[$i]}" == "$LOCAL_IP" ]; then
        HOSTNAME_SET="${ALL_NODE_NAMES[$i]}"
        break
    fi
done
if [ -n "$HOSTNAME_SET" ]; then
    hostnamectl set-hostname "$HOSTNAME_SET"
    echo "[✓] hostname: $HOSTNAME_SET"
else
    echo "[!] IP $LOCAL_IP 不在节点列表，跳过 hostname"
fi

# --- 2. 配置 /etc/hosts ---
awk '
    /# K8S-DEPLOY-MANAGED-BEGIN/ {skip=1; next}
    /# K8S-DEPLOY-MANAGED-END/ {skip=0; next}
    !skip {print}
' /etc/hosts > /etc/hosts.k8s-deploy.tmp
{
    echo "# K8S-DEPLOY-MANAGED-BEGIN"
    for i in "${!ALL_IPS[@]}"; do echo "${ALL_IPS[$i]} ${ALL_NAMES[$i]}"; done
    if [ "${MASTER_COUNT}" -gt 1 ]; then echo "${VIP} k8s-api"; else echo "${MASTER1_IP} k8s-api"; fi
    echo "# K8S-DEPLOY-MANAGED-END"
} >> /etc/hosts.k8s-deploy.tmp
mv /etc/hosts.k8s-deploy.tmp /etc/hosts
echo "[✓] /etc/hosts 已更新"

# --- 3. 关闭 Swap ---
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
    swapoff -a; echo "[✓] swap 已关闭"
else
    echo "[=] swap 已关闭"
fi
sed -i -E '/swap/s/^([^#])/#\1/' /etc/fstab

# --- 4. AppArmor ---
command -v aa-status &>/dev/null && echo "[✓] AppArmor 已启用" || echo "[=] 无 AppArmor"

# --- 5. 关闭 ufw ---
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw disable >/dev/null 2>&1; echo "[✓] ufw 已关闭"
else
    echo "[=] ufw 未运行"
fi

# --- 6. 内核模块 ---
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF
for mod in overlay br_netfilter ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack; do
    modprobe $mod 2>/dev/null || true
done
echo "[✓] 内核模块已加载"

# --- 7. 内核参数 ---
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.tcp_keepalive_time         = 600
net.ipv4.tcp_keepalive_intvl        = 30
net.ipv4.tcp_keepalive_probes       = 10
vm.swappiness                       = 0
net.ipv4.conf.all.arp_ignore        = 1
net.ipv4.conf.all.arp_announce      = 2
EOF
sysctl --system > /dev/null 2>&1
echo "[✓] 内核参数已生效"

# --- 8. 安装基础工具（优先本地 deb 源）---
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
[ -n "${OFFLINE_SOURCE_DIR:-}" ] && [ -d "${OFFLINE_SOURCE_DIR}/packages" ] && OFFLINE_BASE="${OFFLINE_SOURCE_DIR}"
DEBS_DIR="${OFFLINE_BASE}/packages"
if compgen -G "${DEBS_DIR}/*.deb" > /dev/null; then
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
    echo "[✓] 已配置本地 deb 源: file:${DEBS_DIR}"
else
    echo "[✗] 未找到本地 deb 包，离线部署不能继续: ${DEBS_DIR}"
    exit 1
fi
apt-get update > /dev/null 2>&1
apt-get install -y conntrack socat ipset ipvsadm chrony \
    wget curl net-tools bash-completion ca-certificates gnupg > /dev/null 2>&1
echo "[✓] 基础工具已安装"

# --- 9. 时间同步 ---
systemctl enable chrony --now 2>/dev/null || true
echo "[✓] chrony 已启动"

echo ""
echo "--- 验证 ---"
echo "hostname: $(hostname)"
echo "swap: $(free -m | awk '/Swap/{print $2}')MB"
echo "ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "br_netfilter: $(lsmod | grep br_netfilter | wc -l) (>0 已加载)"
echo ""
echo "[完成] 系统初始化完毕"
