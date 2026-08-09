#!/bin/bash
# ============================================================
# 09-verify.sh
# 执行节点：仅 master1
# 功能：全量验收检查
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS=0
FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} $desc"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✗]${NC} $desc"
        FAIL=$((FAIL+1))
    fi
}

echo "=========================================="
echo " K8s 集群全量验收"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# --- 1. 节点状态 ---
echo ""
echo "--- 节点状态 ---"
kubectl get nodes -o wide
echo ""

TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep " Ready" | wc -l)
check "节点总数 = ${TOTAL_COUNT}" "[ $TOTAL_NODES -eq ${TOTAL_COUNT} ]"
check "所有节点 Ready ($READY_NODES/$TOTAL_NODES)" "[ $READY_NODES -eq $TOTAL_NODES ]"

CP_COUNT=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l)
check "控制平面节点 = ${MASTER_COUNT}" "[ $CP_COUNT -eq ${MASTER_COUNT} ]"

# --- 2. 核心组件 ---
echo ""
echo "--- 核心组件 ---"
check "API Server 健康" "kubectl get --raw='/healthz'"
check "etcd 健康" "kubectl get --raw='/healthz/etcd'"

# kube-system pods
echo ""
kubectl get pods -n kube-system --no-headers | awk '{printf "  %-50s %s\n", $1, $3}'
echo ""

check "kube-apiserver 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-apiserver --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-controller-manager 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-controller-manager --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-scheduler 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "etcd 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "coredns 运行" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep Running | wc -l) -ge 2 ]"
check "kube-proxy 运行 (${TOTAL_COUNT})" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep Running | wc -l) -eq ${TOTAL_COUNT} ]"

# --- 3. kube-vip ---
echo ""
echo "--- kube-vip ---"
check "kube-vip Pod 运行" "kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip --no-headers 2>/dev/null | grep -q Running || kubectl get pods -n kube-system --no-headers 2>/dev/null | grep kube-vip | grep -q Running"
check "VIP $VIP 可达" "ping -c 1 -W 2 $VIP"
check "VIP:6443 可连接" "curl -sk https://${VIP}:6443/healthz | grep -q ok"

# --- 4. Calico ---
echo ""
echo "--- Calico CNI ---"
CALICO_READY=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
CALICO_DESIRED=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
check "calico-node DaemonSet ($CALICO_READY/$CALICO_DESIRED)" "[ '$CALICO_READY' == '$CALICO_DESIRED' ] && [ '$CALICO_READY' != '0' ]"

# 检查 Pod CIDR 是否正确（不是 192.168.0.0/16）
POD_CIDR_ACTUAL=$(kubectl get ippool -o jsonpath='{.items[0].spec.cidr}' 2>/dev/null || kubectl cluster-info dump 2>/dev/null | grep -m1 "cluster-cidr" | grep -oP '[\d./]+' || echo "unknown")
check "Pod CIDR 不与宿主网段冲突" "echo '$POD_CIDR_ACTUAL' | grep -v '192.168.0.0'"

# --- 5. DNS 测试 ---
echo ""
echo "--- DNS 功能测试 ---"
kubectl run dns-test --image=${IMAGE_REPOSITORY}/busybox:latest --restart=Never --rm -i --wait --timeout=30s -- nslookup kubernetes.default 2>/dev/null && {
    check "集群 DNS 解析正常" "true"
} || {
    check "集群 DNS 解析正常" "false"
}

# --- 6. 证书 ---
echo ""
echo "--- 证书有效期 ---"
CERTS_OUTPUT=$(kubeadm certs check-expiration 2>/dev/null || echo "")
if [ -n "$CERTS_OUTPUT" ]; then
    echo "$CERTS_OUTPUT" | head -20
fi

APISERVER_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
EXPIRE_EPOCH=$(date -d "$APISERVER_EXPIRE" +%s 2>/dev/null || echo "0")
NOW_EPOCH=$(date +%s)
YEARS_LEFT=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 / 365 ))
check "apiserver 证书 >= 9 年 (实际: ${YEARS_LEFT}年)" "[ $YEARS_LEFT -ge 9 ]"

# --- 7. etcd 集群 ---
# 注意：kubeadm 部署的 etcd 是容器化的，宿主机通常没有 etcdctl 命令，
# 故通过 crictl exec 进 etcd 容器执行 etcdctl（用容器内的证书路径）。
echo ""
echo "--- etcd 集群 ---"
ETCD_CID=$(crictl ps --name '^etcd$' -q 2>/dev/null | head -1)
if [ -z "$ETCD_CID" ]; then
    ETCD_CID=$(crictl ps --name etcd -q 2>/dev/null | head -1)
fi

if [ -n "$ETCD_CID" ]; then
    ETCDCTL="crictl exec ${ETCD_CID} etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key"
    ETCD_HEALTH=$($ETCDCTL endpoint health 2>&1 || echo "")
    echo "$ETCD_HEALTH"
    check "etcd 端点健康" "echo '$ETCD_HEALTH' | grep -q 'is healthy'"

    ETCD_MEMBERS=$($ETCDCTL member list 2>/dev/null | grep -c "started")
    check "etcd 成员数 = ${MASTER_COUNT}" "[ $ETCD_MEMBERS -eq ${MASTER_COUNT} ]"
else
    # 回退：用 apiserver 的 /healthz/etcd（不依赖 etcdctl）
    echo "[!] 未找到 etcd 容器，改用 apiserver /healthz/etcd 检查"
    check "etcd 健康（经 apiserver）" "kubectl get --raw='/healthz/etcd'"
fi

# --- 汇总 ---
echo ""
echo "=========================================="
echo -e " 验收结果: ${GREEN}${PASS} 通过${NC}, ${RED}${FAIL} 失败${NC}"
echo "=========================================="

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║   集群部署验收通过！                    ║"
    echo "  ║   K8s v${KUBE_VERSION} | 3M + 6W | HA  ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
else
    echo -e "${RED}存在失败项，请排查后重新验收${NC}"
    exit 1
fi
