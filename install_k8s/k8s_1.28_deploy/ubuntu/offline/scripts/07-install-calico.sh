#!/bin/bash
# ============================================================
# 07-install-calico.sh
# 执行节点：仅 master1
# 功能：安装 Calico CNI（Ubuntu 离线版，优先本地 manifest）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 安装 Calico CNI: $(hostname)"
echo "=========================================="

if ! kubectl get nodes &>/dev/null; then
    echo "[✗] kubectl 无法连接集群"
    exit 1
fi

if kubectl get ds -n kube-system calico-node &>/dev/null; then
    echo "[=] Calico 已安装"
    exit 0
fi

# --- 1. 准备 Calico manifest（本地优先，离线不能联网）---
echo "--- 准备 Calico manifest ---"
CALICO_YAML="/tmp/calico.yaml"

if [ -f "${SCRIPT_DIR}/../manifests/calico.yaml" ]; then
    cp "${SCRIPT_DIR}/../manifests/calico.yaml" "$CALICO_YAML"
    echo "[=] 使用仓库内置 manifest"
elif [ -f "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" ]; then
    cp "${LOCAL_MANIFESTS_DIR:-/opt/k8s-offline/manifests}/calico.yaml" "$CALICO_YAML"
    echo "[=] 使用离线介质 manifest"
elif [ -n "${CALICO_MANIFEST_URL}" ]; then
    curl -sSL --connect-timeout 15 "$CALICO_MANIFEST_URL" -o "$CALICO_YAML"
    echo "[=] 下载 manifest"
else
    echo "[✗] 未找到 Calico manifest（请先执行 fetch-resources.sh 或放置 manifests/calico.yaml）"
    exit 1
fi
[ -s "$CALICO_YAML" ] && grep -q "calico" "$CALICO_YAML" || { echo "[✗] manifest 无效"; exit 1; }
echo "[✓] manifest 就绪（$(wc -l < "$CALICO_YAML") 行）"

# --- 2. 修改 Pod CIDR ---
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' "$CALICO_YAML"
sed -i 's|#   value: "192.168.0.0/16"|  value: "'"${POD_CIDR}"'"|' "$CALICO_YAML"

# --- 2.1 替换镜像源 ---
if [ -n "${CALICO_IMAGE_REGISTRY}" ]; then
    sed -i "s|image: m.daocloud.io/docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    sed -i "s|image: docker.io/calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    sed -i "s|image: calico/|image: ${CALICO_IMAGE_REGISTRY}/calico/|g" "$CALICO_YAML"
    echo "[✓] 镜像源: ${CALICO_IMAGE_REGISTRY}/calico/"
fi

# --- 3. 应用 ---
kubectl apply -f "$CALICO_YAML"
echo "[✓] Calico 已应用"

# --- 4. 配置 calico-node 数据面 ---
if [ -n "${CALICO_INTERFACE}" ]; then
    CALICO_NIC="${CALICO_INTERFACE}"
else
    CALICO_NIC=$(ip route show default | awk '/default/{print $5; exit}')
fi

kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD="interface=${CALICO_NIC}"
kubectl set env daemonset/calico-node -n kube-system \
    CALICO_NETWORKING_BACKEND="vxlan" CLUSTER_TYPE="k8s" \
    CALICO_IPV4POOL_IPIP="Never" CALICO_IPV4POOL_VXLAN="Always"
kubectl patch daemonset calico-node -n kube-system --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/exec/command","value":["/bin/calico-node","-felix-ready"]},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/exec/command","value":["/bin/calico-node","-felix-live"]}
]' 2>/dev/null && echo "[✓] 探针已去 bird 检查"
echo "[✓] 数据面: 纯 VXLAN"

# --- 等待就绪 ---
for i in $(seq 1 60); do
    READY=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    [ "$READY" == "$DESIRED" ] && [ "$READY" != "0" ] && { echo "[✓] calico-node: $READY/$DESIRED Ready"; break; }
    echo "    等待中... ($READY/$DESIRED) [${i}/60]"
    sleep 10
done

echo ""
kubectl get pods -n kube-system -l k8s-app=calico-node
echo ""
kubectl get nodes
NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
[ "$NOT_READY" -eq 0 ] && echo "[完成] Calico 安装成功" || echo "[!] 仍有节点 NotReady"
