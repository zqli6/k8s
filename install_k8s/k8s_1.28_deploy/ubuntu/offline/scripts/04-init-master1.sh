#!/bin/bash
# ============================================================
# 04-init-master1.sh
# 执行节点：仅 master1
# 功能：生成 kube-vip manifest + kubeadm init + 输出 join 信息（Ubuntu 离线版）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 初始化 master1: $(hostname)"
echo "=========================================="

if [ -f /etc/kubernetes/admin.conf ]; then
    echo "[!] /etc/kubernetes/admin.conf 已存在，集群可能已初始化"
    echo "    如需重新初始化: kubeadm reset -f && rm -rf /etc/kubernetes /var/lib/etcd"
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    echo "[✗] containerd 未运行，请先执行 02-install-containerd.sh"
    exit 1
fi

if ! command -v kubeadm &>/dev/null; then
    echo "[✗] kubeadm 未安装，请先执行 03-install-k8s.sh"
    exit 1
fi

# --- 1. 探测网卡名（多 Master 的 kube-vip 模式需要）---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    if [ -n "$KUBEVIP_INTERFACE" ]; then
        NIC="$KUBEVIP_INTERFACE"
    else
        NIC=$(ip route show default | awk '/default/{print $5; exit}')
    fi
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if ! ip addr show "$NIC" | grep -q "$LOCAL_IP"; then
        echo "[✗] 网卡 $NIC 未持有本机 IP $LOCAL_IP"
        exit 1
    fi
    echo "[✓] 网卡: $NIC (持有 $LOCAL_IP)"
else
    echo "[=] 单 Master，不部署 kube-vip"
fi

# --- 2. 多 Master 才准备 kube-vip 镜像并生成 manifest ---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    echo ""
    echo "--- 配置 kube-vip ---"
    KUBEVIP_IMAGE="${KUBEVIP_IMAGE:-ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}}"

    # 离线版：先查本地是否已由 import-resources.sh 导入
    if ctr -n k8s.io images ls -q 2>/dev/null | grep -q "kube-vip"; then
        echo "[=] kube-vip 镜像已在本地，跳过拉取"
    else
        echo "本地无 kube-vip，尝试离线导入..."
        KUBEVIP_TAR="${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar"
        [ -f "$KUBEVIP_TAR" ] || KUBEVIP_TAR="${SCRIPT_DIR}/../images/kube-vip.tar"
        if [ -f "$KUBEVIP_TAR" ]; then
            ctr -n k8s.io images import "$KUBEVIP_TAR"
        else
            ctr -n k8s.io images pull "$KUBEVIP_IMAGE" || { echo "[✗] 无法获取 kube-vip"; exit 1; }
        fi
    fi

    mkdir -p /etc/kubernetes/manifests
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
    echo "[✓] kube-vip manifest 已生成（VIP: ${VIP}）"
fi

# --- 3. 生成 kubeadm 配置 ---
echo ""
echo "--- 生成 kubeadm 配置 ---"
mkdir -p /etc/kubernetes/manifests

CERT_SANS="    - \"k8s-api\""
if [ "${MASTER_COUNT}" -gt 1 ]; then
    CERT_SANS="${CERT_SANS}
    - \"${VIP}\""
fi
for ip in "${MASTER_IPS[@]}"; do CERT_SANS="${CERT_SANS}
    - \"${ip}\""; done
for name in "${MASTER_NAMES[@]}"; do CERT_SANS="${CERT_SANS}
    - \"${name}\""; done
CERT_SANS="${CERT_SANS}
    - \"localhost\"
    - \"127.0.0.1\""

CONTROL_PLANE_ENDPOINT="k8s-api:${API_SERVER_PORT}"

cat > /etc/kubernetes/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "${MASTER1_IP}"
  bindPort: ${API_SERVER_PORT}
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v${KUBE_VERSION}"
controlPlaneEndpoint: "${CONTROL_PLANE_ENDPOINT}"
imageRepository: "${IMAGE_REPOSITORY}"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
  dnsDomain: "cluster.local"
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  certSANs:
${CERT_SANS}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ${KUBE_PROXY_MODE}
EOF
echo "[✓] kubeadm 配置已生成"

# --- 4. 预拉取镜像（离线版：先查本地，有则跳过联网拉取）---
echo ""
echo "--- 检查 K8s 镜像 ---"
MISSING_IMG=0
for img in $(kubeadm config images list --config /etc/kubernetes/kubeadm-config.yaml 2>/dev/null); do
    if ! ctr -n k8s.io images ls -q 2>/dev/null | grep -q "$img"; then
        MISSING_IMG=1; break
    fi
done
if [ "$MISSING_IMG" -eq 0 ]; then
    echo "[=] K8s 镜像已在本地，跳过预拉取"
else
    echo "本地缺镜像，尝试拉取（离线会失败，属正常）..."
    kubeadm config images pull --config /etc/kubernetes/kubeadm-config.yaml || \
        echo "[!] 预拉取失败，请确认 import-resources.sh 已执行"
fi

# --- 5. kubeadm init ---
echo ""
echo "--- 执行 kubeadm init ---"
kubeadm init --config /etc/kubernetes/kubeadm-config.yaml --upload-certs | tee /tmp/kubeadm-init.log

# --- 6. 配置 kubectl ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# --- 7. 提取 join 信息 ---
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
mkdir -p /etc/kubernetes/deploy
cat > /etc/kubernetes/deploy/join.env <<EOF
JOIN_CMD="${JOIN_CMD}"
CERT_KEY="${CERT_KEY}"
VIP="${VIP}"
API_SERVER_PORT="${API_SERVER_PORT}"
EOF
chmod 600 /etc/kubernetes/deploy/join.env
echo "[✓] join 信息已保存"

# --- 验证 ---
echo ""
sleep 10
kubectl get nodes
echo ""
kubectl get pods -n kube-system
echo ""
kubectl get nodes | grep -q "Ready" && echo "[完成] master1 初始化成功" || echo "[!] master1 状态异常，检查: journalctl -u kubelet -f"
