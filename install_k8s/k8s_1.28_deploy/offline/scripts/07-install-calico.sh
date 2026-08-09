#!/bin/bash
# ============================================================
# 07-install-calico.sh
# 执行节点：仅 master1
# 功能：安装 Calico CNI 网络插件
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

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

# --- 1. 准备 Calico manifest ---
# 私有仓库版：优先用仓库内置本地 manifest（不联网），其次离线介质目录，最后才联网。
echo "--- 准备 Calico ${CALICO_VERSION} manifest ---"
CALICO_YAML="/tmp/calico.yaml"

if [ -f "${SCRIPT_DIR}/../manifests/calico.yaml" ]; then
    echo "[=] 使用仓库内置 manifest: private-registry/manifests/calico.yaml"
    cp "${SCRIPT_DIR}/../manifests/calico.yaml" "$CALICO_YAML"
elif [ -f "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" ]; then
    echo "[=] 使用离线介质 manifest"
    cp "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" "$CALICO_YAML"
elif [ -n "${CALICO_MANIFEST_URL}" ]; then
    echo "[=] 本地无 manifest，尝试下载: $CALICO_MANIFEST_URL"
    curl -sSL --connect-timeout 15 "$CALICO_MANIFEST_URL" -o "$CALICO_YAML"
else
    echo "[✗] 未找到 Calico manifest，请放到 private-registry/manifests/calico.yaml"
    exit 1
fi
if [ ! -s "$CALICO_YAML" ] || ! grep -q "calico" "$CALICO_YAML"; then
    echo "[✗] Calico manifest 无效"
    exit 1
fi
echo "[✓] Calico manifest 就绪（$(wc -l < $CALICO_YAML) 行）"

# --- 2. 修改 Pod CIDR ---
# 默认 192.168.0.0/16 与宿主网段冲突，必须改为 10.244.0.0/16
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' "$CALICO_YAML"
sed -i 's|#   value: "192.168.0.0/16"|  value: "'"${POD_CIDR}"'"|' "$CALICO_YAML"
echo "[✓] Pod CIDR 已设为 ${POD_CIDR}"

# --- 2.1 替换镜像源为私有仓库 ---
# 把 manifest 里 docker.io/calico/* 换成 ${PRIVATE_REGISTRY}/calico/*
# （镜像须已用 push-to-registry.sh 推到私有仓库）
if [ -n "${CALICO_IMAGE_REGISTRY}" ]; then
    sed -i "s|image: m.daocloud.io/docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    sed -i "s|image: docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    sed -i "s|image: calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    echo "[✓] Calico 镜像源已指向私有仓库: ${CALICO_IMAGE_REGISTRY}/calico/"
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
