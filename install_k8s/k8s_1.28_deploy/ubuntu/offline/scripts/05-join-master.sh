#!/bin/bash
# ============================================================
# 05-join-master.sh
# 执行节点：仅 master2、master3（串行）
# 功能：加入控制平面 + 部署 kube-vip（Ubuntu 离线版）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 加入控制平面: $(hostname)"
echo "=========================================="

if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[!] 本节点已加入集群"
    exit 1
fi

JOIN_ENV="/etc/kubernetes/deploy/join.env"
if [ ! -f "$JOIN_ENV" ]; then
    echo "[✗] 未找到 $JOIN_ENV"
    exit 1
fi
source "$JOIN_ENV"
[ -z "$JOIN_CMD" ] || [ -z "$CERT_KEY" ] && { echo "[✗] join.env 不完整"; exit 1; }

# --- 1. 加入控制平面 ---
${JOIN_CMD} --control-plane --certificate-key "${CERT_KEY}" \
    --cri-socket unix:///var/run/containerd/containerd.sock

# --- 2. 配置 kubectl ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# --- 3. 多 Master 才部署 kube-vip ---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    if [ -n "$KUBEVIP_INTERFACE" ]; then
        NIC="$KUBEVIP_INTERFACE"
    else
        NIC=$(ip route show default | awk '/default/{print $5; exit}')
    fi
    KUBEVIP_IMAGE="${KUBEVIP_IMAGE:-ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}}"

    # 离线：先查本地，无则 import 本地 tar
    if ! ctr -n k8s.io images ls -q 2>/dev/null | grep -q "kube-vip"; then
        KUBEVIP_TAR="${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar"
        [ -f "$KUBEVIP_TAR" ] || KUBEVIP_TAR="${SCRIPT_DIR}/../images/kube-vip.tar"
        [ -f "$KUBEVIP_TAR" ] && ctr -n k8s.io images import "$KUBEVIP_TAR" 2>/dev/null || true
    fi

    cat > /etc/kubernetes/manifests/kube-vip.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "${API_SERVER_PORT}"
    - name: vip_interface
      value: "${NIC}"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "${VIP}"
    image: ${KUBEVIP_IMAGE}
    imagePullPolicy: IfNotPresent
    name: kube-vip
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        - SYS_TIME
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
EOF
    echo "[✓] kube-vip manifest 已部署"
fi

echo ""
sleep 5
kubectl get nodes
echo ""
echo "[完成] $(hostname) 已加入控制平面"
