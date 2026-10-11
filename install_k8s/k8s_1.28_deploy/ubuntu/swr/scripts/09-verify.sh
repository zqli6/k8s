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

echo ""
echo "--- 核心组件 ---"
check "API Server 健康" "kubectl get --raw='/healthz'"
check "etcd 健康" "kubectl get --raw='/healthz/etcd'"

echo ""
kubectl get pods -n kube-system --no-headers | awk '{printf "  %-50s %s\n", $1, $3}'
echo ""

check "kube-apiserver 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-apiserver --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-controller-manager 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-controller-manager --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-scheduler 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "etcd 运行 (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "coredns 运行" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep Running | wc -l) -ge 2 ]"
check "kube-proxy 运行 (${TOTAL_COUNT})" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep Running | wc -l) -eq ${TOTAL_COUNT} ]"

echo ""
echo "--- kube-vip ---"
if [ "${MASTER_COUNT}" -gt 1 ]; then
    check "kube-vip Pod 运行" "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep kube-vip | grep -q Running"
    check "VIP $VIP 可达" "ping -c 1 -W 2 $VIP"
    check "VIP:6443 可连接" "curl -sk https://${VIP}:6443/healthz | grep -q ok"
else
    echo "[=] 单 Master 模式，跳过 kube-vip/VIP 检查"
    check "Master API Server 可连接" "curl -sk https://${MASTER1_IP}:6443/healthz | grep -q ok"
fi

echo ""
echo "--- Calico CNI ---"
CALICO_READY=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
CALICO_DESIRED=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
check "calico-node DaemonSet ($CALICO_READY/$CALICO_DESIRED)" "[ '$CALICO_READY' == '$CALICO_DESIRED' ] && [ '$CALICO_READY' != '0' ]"

POD_CIDR_ACTUAL=$(kubectl get ippool -o jsonpath='{.items[0].spec.cidr}' 2>/dev/null || echo "unknown")
check "Pod CIDR 不与宿主网段冲突" "echo '$POD_CIDR_ACTUAL' | grep -v '192.168.0.0'"

echo ""
echo "--- 证书有效期 ---"
kubeadm certs check-expiration 2>/dev/null | head -20 || true
APISERVER_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
EXPIRE_EPOCH=$(date -d "$APISERVER_EXPIRE" +%s 2>/dev/null || echo "0")
NOW_EPOCH=$(date +%s)
YEARS_LEFT=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 / 365 ))
check "apiserver 证书 >= 9 年 (实际: ${YEARS_LEFT}年)" "[ $YEARS_LEFT -ge 9 ]"

echo ""
echo "--- etcd 集群 ---"
ETCD_CID=$(crictl ps --name '^etcd$' -q 2>/dev/null | head -1)
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
    check "etcd 健康（经 apiserver）" "kubectl get --raw='/healthz/etcd'"
fi

echo ""
echo "=========================================="
echo -e " 验收结果: ${GREEN}${PASS} 通过${NC}, ${RED}${FAIL} 失败${NC}"
echo "=========================================="

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║   集群部署验收通过！                    ║"
    echo "  ║   K8s v${KUBE_VERSION} | ${MASTER_COUNT}M + ${WORKER_COUNT}W  ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
else
    echo -e "${RED}存在失败项，请排查后重新验收${NC}"
    exit 1
fi
