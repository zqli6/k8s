#!/bin/bash
# ============================================================
# 01-system-init.sh
# 执行节点：全部节点（9台都要跑）
# 功能：系统初始化 - hostname、hosts、swap、SELinux、防火墙、内核模块、sysctl、时间同步
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 系统初始化: $(hostname)"
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
# 每次根据当前 MASTER_NODES/WORKER_NODES 重建受管区域，避免拓扑变更后
# 旧节点或旧 k8s-api 记录继续生效。其他非本方案记录保持不变。
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
sed -i '/swap/s/^/#/' /etc/fstab
echo "[✓] /etc/fstab swap 行已注释"

# --- 4. 关闭 SELinux ---
if [ "$(getenforce 2>/dev/null)" == "Enforcing" ]; then
    setenforce 0
    echo "[✓] SELinux 运行时已设为 Permissive"
fi
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    echo "[✓] SELinux 配置文件已设为 disabled"
fi

# --- 5. 关闭防火墙 ---
if systemctl is-active --quiet firewalld 2>/dev/null; then
    systemctl stop firewalld
    systemctl disable firewalld
    echo "[✓] firewalld 已停止并禁用"
else
    echo "[=] firewalld 未运行"
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
    modprobe $mod 2>/dev/null || modprobe nf_conntrack_ipv4 2>/dev/null
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
# 完全离线时优先使用本目录 packages/ 的本地 yum 源；没有离线包时
# 才回退到系统已配置的在线源，并明确提示该方案不是完全离线。
OFFLINE_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
[ -d "${OFFLINE_BASE}/packages" ] || OFFLINE_BASE="/opt/k8s-deploy"
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
    echo "[✓] 基础工具使用本地 RPM 源: file://${RPMS_DIR}"
else
    echo "[!] 未找到完整本地 RPM 源，基础工具将使用系统 yum 源（需要外网）"
fi

yum "${YUM_LOCAL_ARGS[@]}" install -y conntrack-tools socat ipset ipvsadm chrony yum-utils \
    wget curl net-tools bash-completion > /dev/null 2>&1
echo "[✓] 基础工具已安装"

# --- 9. 时间同步 ---
systemctl enable chronyd --now 2>/dev/null
echo "[✓] chrony 时间同步已启动"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "hostname: $(hostname)"
echo "swap: $(free -m | awk '/Swap/{print $2}')MB"
echo "SELinux: $(getenforce 2>/dev/null || echo Disabled)"
echo "ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "br_netfilter: $(lsmod | grep br_netfilter | wc -l) (>0 表示已加载)"
echo ""
echo "[完成] 系统初始化完毕"
