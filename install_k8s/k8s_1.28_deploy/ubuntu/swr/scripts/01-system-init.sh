#!/bin/bash
# ============================================================
# 01-system-init.sh
# 执行节点：全部节点
# 功能：系统初始化 - hostname、hosts、swap、AppArmor、防火墙、内核模块、sysctl、时间同步（Ubuntu 版）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

if [ -z "${UBUNTU_CODENAME:-}" ]; then
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi

echo "=========================================="
echo " 系统初始化: $(hostname)  (Ubuntu ${UBUNTU_CODENAME})"
echo "=========================================="

# --- 1. 设置 hostname（根据 IP 自动匹配）---
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
    echo "[✓] hostname 设置为: $HOSTNAME_SET"
else
    echo "[!] 当前 IP $LOCAL_IP 不在集群节点列表中，跳过 hostname 设置"
fi

# --- 2. 配置 /etc/hosts ---
awk '
    /# K8S-DEPLOY-MANAGED-BEGIN/ {skip=1; next}
    /# K8S-DEPLOY-MANAGED-END/ {skip=0; next}
    !skip {print}
' /etc/hosts > /etc/hosts.k8s-deploy.tmp
{
    echo "# K8S-DEPLOY-MANAGED-BEGIN"
    for i in "${!ALL_IPS[@]}"; do
        echo "${ALL_IPS[$i]} ${ALL_NAMES[$i]}"
    done
    if [ "${MASTER_COUNT}" -gt 1 ]; then
        echo "${VIP} k8s-api"
    else
        echo "${MASTER1_IP} k8s-api"
    fi
    echo "# K8S-DEPLOY-MANAGED-END"
} >> /etc/hosts.k8s-deploy.tmp
mv /etc/hosts.k8s-deploy.tmp /etc/hosts
if [ "${MASTER_COUNT}" -gt 1 ]; then
    echo "[✓] /etc/hosts 已更新：多 Master 使用 VIP ${VIP} k8s-api"
else
    echo "[✓] /etc/hosts 已更新：单 Master 使用 ${MASTER1_IP} k8s-api，不部署 kube-vip"
fi

# --- 3. 关闭 Swap ---
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
    swapoff -a
    echo "[✓] swap 已关闭"
else
    echo "[=] swap 已经是关闭状态"
fi
sed -i -E '/swap/s/^([^#])/#\1/' /etc/fstab
echo "[✓] /etc/fstab swap 行已注释"

# --- 4. AppArmor ---
if command -v aa-status &>/dev/null; then
    echo "[✓] AppArmor 已启用（Ubuntu 默认，K8s 兼容，无需关闭）"
else
    echo "[=] 未检测到 AppArmor"
fi

# --- 5. 关闭防火墙（ufw）---
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw disable >/dev/null 2>&1
    echo "[✓] ufw 已关闭"
else
    echo "[=] ufw 未运行"
fi

# --- 6. 加载内核模块 ---
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

# --- 8. 安装基础工具 ---
export DEBIAN_FRONTEND=noninteractive
apt-get update > /dev/null 2>&1 || true
apt-get install -y conntrack socat ipset ipvsadm chrony \
    wget curl net-tools bash-completion ca-certificates gnupg > /dev/null 2>&1
echo "[✓] 基础工具已安装"

# --- 9. 时间同步 ---
systemctl enable chrony --now 2>/dev/null || true
echo "[✓] chrony 时间同步已启动"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "hostname: $(hostname)"
echo "swap: $(free -m | awk '/Swap/{print $2}')MB"
echo "AppArmor: $(command -v aa-status >/dev/null && echo enabled || echo disabled)"
echo "ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "br_netfilter: $(lsmod | grep br_netfilter | wc -l) (>0 表示已加载)"
echo ""
echo "[完成] 系统初始化完毕"
