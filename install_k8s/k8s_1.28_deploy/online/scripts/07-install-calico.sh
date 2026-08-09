#!/bin/bash
# ============================================================
# 07-install-calico.sh
# 执行节点：仅 master1
# 功能：安装 Calico CNI 网络插件
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 安装 Calico CNI: $(hostname)"
echo "=========================================="

# --- 前置检查 ---
if ! kubectl get nodes &>/dev/null; then
    echo "[✗] kubectl 无法连接集群"
    exit 1
fi

if kubectl get ds -n kube-system calico-node &>/dev/null; then
    echo "[=] Calico 已安装"
    kubectl get pods -n kube-system -l k8s-app=calico-node
    exit 0
fi

# --- 1. 下载 Calico manifest ---
echo "--- 下载 Calico ${CALICO_VERSION} manifest ---"
# raw.githubusercontent.com 国内被墙，默认用 gitee 镜像（cluster.env 中 CALICO_MANIFEST_URL）
CALICO_URL="${CALICO_MANIFEST_URL:-https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml}"
CALICO_YAML="/tmp/calico.yaml"

if [ -f "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" ]; then
    echo "[=] 使用本地 Calico manifest"
    cp "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" "$CALICO_YAML"
else
    echo "下载地址: $CALICO_URL"
    curl -sSL --connect-timeout 15 "$CALICO_URL" -o "$CALICO_YAML" || {
        echo "[✗] manifest 下载失败，尝试备用 ghproxy 加速源..."
        curl -sSL --connect-timeout 15 "https://ghfast.top/https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" -o "$CALICO_YAML"
    }
    # 校验下载内容有效（至少几百行且含 calico）
    if [ ! -s "$CALICO_YAML" ] || ! grep -q "calico" "$CALICO_YAML"; then
        echo "[✗] Calico manifest 下载失败或内容无效"
        exit 1
    fi
    echo "[✓] Calico manifest 已下载（$(wc -l < $CALICO_YAML) 行）"
fi

# --- 2. 修改 Pod CIDR ---
# 取消 CALICO_IPV4POOL_CIDR 注释并设置为我们的 Pod CIDR
# 默认 192.168.0.0/16 与宿主网段冲突，必须改为 10.244.0.0/16
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' "$CALICO_YAML"
sed -i 's|#   value: "192.168.0.0/16"|  value: "'"${POD_CIDR}"'"|' "$CALICO_YAML"
echo "[✓] Pod CIDR 已设为 ${POD_CIDR}"

# --- 2.1 替换镜像源（国内 docker.io 不可达）---
# Calico manifest 默认镜像为 docker.io/calico/*，国内拉不到
# 替换为可配置的加速前缀（默认 DaoCloud），离线时 cluster.env 改为内网 registry
if [ -n "${CALICO_IMAGE_REGISTRY}" ]; then
    sed -i "s|image: m.daocloud.io/docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    sed -i "s|image: docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    # 部分 manifest 镜像不带 docker.io 前缀，直接写 calico/
    sed -i "s|image: calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    echo "[✓] Calico 镜像源已替换为 ${CALICO_IMAGE_REGISTRY}/calico/"
    echo "    实际镜像: $(grep -m1 'image:' $CALICO_YAML | awk '{print $2}')"
fi

# --- 3. 应用 Calico manifest ---
# 注意：不用 sed 硬插 env（易破坏 CLUSTER_TYPE 等键值对），
# 改为先 apply、再用 kubectl set env 精确设置——稳健且幂等。
echo ""
echo "--- 应用 Calico ---"
kubectl apply -f "$CALICO_YAML"
echo "[✓] Calico manifest 已应用"

# --- 4. 精确设置 calico-node 环境变量 ---
echo ""
echo "--- 配置 calico-node 数据面 ---"

# 4.0 探测网卡名（优先 CALICO_INTERFACE，留空则取默认路由网卡）
if [ -n "${CALICO_INTERFACE}" ]; then
    CALICO_NIC="${CALICO_INTERFACE}"
else
    CALICO_NIC=$(ip route show default | awk '/default/{print $5; exit}')
fi
echo "[=] Calico 网卡: ${CALICO_NIC}"

# 4.1 网卡探测用 interface=（★不要用 cidr=）
# 真机踩坑：kube-proxy IPVS 模式会在 kube-ipvs0 虚拟网卡上挂 Service IP，
# 若某 Service IP 落在节点网段内，cidr= 会误选 kube-ipvs0 → 多节点探测到同一 IP
# → calico-node 报 "already using the IPv4 address" 崩溃。用 interface= 精确指定真实网卡。
kubectl set env daemonset/calico-node -n kube-system \
    IP_AUTODETECTION_METHOD="interface=${CALICO_NIC}"
echo "[✓] IP_AUTODETECTION_METHOD = interface=${CALICO_NIC}"

# 4.2 纯 VXLAN 数据面（★backend 必须设 vxlan，否则默认 bird 会启 BGP 与 VXLAN 冲突）
# 真机踩坑：只设 CALICO_IPV4POOL_VXLAN=Always 不够，backend 默认仍是 bird，
# calico-node 会同时尝试建 BGP → BIRD 配置语法错误、节点 NotReady。
# 必须同时：backend=vxlan（禁 BIRD）+ CLUSTER_TYPE=k8s（去掉 bgp）+ 关 IPIP。
kubectl set env daemonset/calico-node -n kube-system \
    CALICO_NETWORKING_BACKEND="vxlan" \
    CLUSTER_TYPE="k8s" \
    CALICO_IPV4POOL_IPIP="Never" \
    CALICO_IPV4POOL_VXLAN="Always"
echo "[✓] 数据面: 纯 VXLAN (backend=vxlan, 禁用 BGP), IPIP 已关闭"

# 4.3 VXLAN 模式 BIRD 不运行，去掉探针里的 -bird-ready / -bird-live
# 真机踩坑：默认探针含 -bird-ready，VXLAN 模式 BIRD 不跑 → 探针永远失败 → Pod 0/1。
kubectl patch daemonset calico-node -n kube-system --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/exec/command","value":["/bin/calico-node","-felix-ready"]},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/exec/command","value":["/bin/calico-node","-felix-live"]}
]' 2>/dev/null && echo "[✓] 探针已去掉 bird 检查（VXLAN 模式 BIRD 不跑）"

echo "[✓] calico-node 配置完成，等待滚动重启..."
sleep 5

# --- 等待就绪 ---
echo ""
echo "--- 等待 Calico 就绪 ---"
echo "等待 calico-node DaemonSet 滚动完成..."
for i in $(seq 1 60); do
    READY=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    if [ "$READY" == "$DESIRED" ] && [ "$READY" != "0" ]; then
        echo "[✓] calico-node: $READY/$DESIRED Ready"
        break
    fi
    echo "    等待中... ($READY/$DESIRED) [${i}/60]"
    sleep 10
done

# --- 验证 ---
echo ""
echo "--- 验证 ---"
kubectl get pods -n kube-system -l k8s-app=calico-node
echo ""
kubectl get nodes
echo ""

# 检查节点是否全部 Ready
NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
if [ "$NOT_READY" -eq 0 ]; then
    echo "[完成] Calico 安装成功，所有节点 Ready"
else
    echo "[!] 仍有 $NOT_READY 个节点 NotReady，等待 Calico Pod 启动..."
    echo "    kubectl get pods -n kube-system -l k8s-app=calico-node -o wide"
fi
