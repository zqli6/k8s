#!/bin/bash
# ============================================================
# 05-join-master.sh
# 执行节点：仅 master2、master3（串行，一次一个）
# 功能：加入控制平面 + 部署 kube-vip
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 加入控制平面: $(hostname)"
echo "=========================================="

# --- 前置检查 ---
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[!] 本节点已加入集群（/etc/kubernetes/kubelet.conf 存在）"
    echo "    如需重新加入: kubeadm reset -f && rm -rf /etc/kubernetes /var/lib/etcd"
    exit 1
fi

# 读取 join 信息（从 master1 scp 过来或手动拷贝）
JOIN_ENV="/etc/kubernetes/deploy/join.env"
if [ ! -f "$JOIN_ENV" ]; then
    echo "[✗] 未找到 $JOIN_ENV"
    echo "    请从 master1 拷贝: scp master1:/etc/kubernetes/deploy/join.env /etc/kubernetes/deploy/"
    exit 1
fi
source "$JOIN_ENV"

if [ -z "$JOIN_CMD" ] || [ -z "$CERT_KEY" ]; then
    echo "[✗] join.env 内容不完整"
    exit 1
fi
echo "[✓] join 信息已加载"

# --- 1. 加入控制平面 ---
echo ""
echo "--- 执行 kubeadm join (control-plane) ---"
${JOIN_CMD} --control-plane --certificate-key "${CERT_KEY}" \
    --cri-socket unix:///var/run/containerd/containerd.sock

# --- 2. 配置 kubectl ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
echo "[✓] kubectl 已配置"

# --- 3. 多 Master 才部署 kube-vip ---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    echo ""
    echo "--- 部署 kube-vip ---"

# 探测网卡
if [ -n "$KUBEVIP_INTERFACE" ]; then
    NIC="$KUBEVIP_INTERFACE"
else
    NIC=$(ip route show default | awk '/default/{print $5; exit}')
fi
echo "[✓] 网卡: $NIC"

# KUBEVIP_IMAGE 由 cluster.env 统一定义（受 PRIVATE_REGISTRY 开关控制）
KUBEVIP_IMAGE="${KUBEVIP_IMAGE:-ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}}"

# 拉取 kube-vip 镜像
ctr -n k8s.io images pull "$KUBEVIP_IMAGE" 2>/dev/null || {
    if [ -f "${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar" ]; then
        ctr -n k8s.io images import "${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar"
    else
        echo "[!] kube-vip 镜像拉取失败，VIP 故障转移可能不可用"
    fi
}

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
else
    echo "[=] 单 Master 不部署 kube-vip"
fi

# --- 验证 ---
echo ""
echo "--- 验证 ---"
sleep 5
kubectl get nodes
echo ""
echo "[完成] $(hostname) 已加入控制平面"
