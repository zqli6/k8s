#!/bin/bash
# ============================================================
# 09-verify.sh
# 执行节点：仅 master1
# 功能：全量验收检查
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0
check() {
    if eval "$2" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} $1"; PASS=$((PASS+1))
    else
        echo -e "${RED}[✗]${NC} $1"; FAIL=$((FAIL+1))
    fi
}

echo "=========================================="
echo " K8s 集群全量验收"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""
kubectl get nodes -o wide
echo ""

TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep " Ready" | wc -l)
check "节点总数 = ${TOTAL_COUNT}" "[ $TOTAL_NODES -eq ${TOTAL_COUNT} ]"
check "所有节点 Ready ($READY_NODES/$TOTAL_NODES)" "[ $READY_NODES -eq $TOTAL_NODES ]"
CP_COUNT=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l)
check "控制平面 = ${MASTER_COUNT}" "[ $CP_COUNT -eq ${MASTER_COUNT} ]"

echo ""
echo "--- 核心组件 ---"
check "API Server 健康" "kubectl get --raw='/healthz'"
check "etcd 健康" "kubectl get --raw='/healthz/etcd'"
check "kube-apiserver (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-apiserver --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-controller-manager (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-controller-manager --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "kube-scheduler (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "etcd (${MASTER_COUNT})" "[ $(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | grep Running | wc -l) -eq ${MASTER_COUNT} ]"
check "coredns" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep Running | wc -l) -ge 2 ]"
check "kube-proxy (${TOTAL_COUNT})" "[ $(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep Running | wc -l) -eq ${TOTAL_COUNT} ]"

echo ""
echo "--- kube-vip ---"
if [ "${MASTER_COUNT}" -gt 1 ]; then
    check "kube-vip Pod" "kubectl get pods -n kube-system --no-headers 2>/dev/null | grep kube-vip | grep -q Running"
    check "VIP $VIP 可达" "ping -c 1 -W 2 $VIP"
    check "VIP:6443 可连接" "curl -sk https://${VIP}:6443/healthz | grep -q ok"
else
    check "Master API 可连接" "curl -sk https://${MASTER1_IP}:6443/healthz | grep -q ok"
fi

echo ""
echo "--- Calico ---"
CALICO_READY=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
CALICO_DESIRED=$(kubectl get ds -n kube-system calico-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
check "calico-node ($CALICO_READY/$CALICO_DESIRED)" "[ '$CALICO_READY' == '$CALICO_DESIRED' ] && [ '$CALICO_READY' != '0' ]"

echo ""
echo "--- 证书 ---"
APISERVER_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
EXPIRE_EPOCH=$(date -d "$APISERVER_EXPIRE" +%s 2>/dev/null || echo "0")
YEARS_LEFT=$(( (EXPIRE_EPOCH - $(date +%s)) / 86400 / 365 ))
check "证书 >= 9 年 (实际 ${YEARS_LEFT}年)" "[ $YEARS_LEFT -ge 9 ]"

echo ""
echo "=========================================="
echo -e " 验收结果: ${GREEN}${PASS} 通过${NC}, ${RED}${FAIL} 失败${NC}"
echo "=========================================="
[ $FAIL -eq 0 ] && echo -e "${GREEN}集群部署验收通过！${NC}" || { echo -e "${RED}存在失败项${NC}"; exit 1; }
