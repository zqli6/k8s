#!/bin/bash
# ============================================================
# 04-init-master1.sh
# 执行节点：仅 master1
# 功能：生成 kube-vip manifest + kubeadm init + 输出 join 信息
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 初始化 master1: $(hostname)"
echo "=========================================="

# --- 前置检查 ---
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "[!] /etc/kubernetes/admin.conf 已存在，集群可能已初始化"
    echo "    如需重新初始化请先: kubeadm reset -f && rm -rf /etc/kubernetes /var/lib/etcd"
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

# --- 1. 探测网卡名（仅多 Master 的 kube-vip 模式需要）---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    if [ -n "$KUBEVIP_INTERFACE" ]; then
        NIC="$KUBEVIP_INTERFACE"
        echo "[=] 使用指定网卡: $NIC"
    else
        NIC=$(ip route show default | awk '/default/{print $5; exit}')
        echo "[✓] 自动探测网卡: $NIC"
    fi

    # 校验网卡持有本机 IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if ! ip addr show "$NIC" | grep -q "$LOCAL_IP"; then
        echo "[✗] 网卡 $NIC 未持有本机 IP $LOCAL_IP"
        exit 1
    fi
    echo "[✓] 网卡 $NIC 持有 IP $LOCAL_IP"
else
    echo "[=] 单 Master 模式，不部署 kube-vip，控制面直接使用 ${MASTER1_IP}:${API_SERVER_PORT}"
fi

# --- 2. 多 Master 才拉取 kube-vip 镜像并生成 static pod manifest ---
if [ "${MASTER_COUNT}" -gt 1 ]; then
    echo ""
    echo "--- 配置 kube-vip ---"
    # KUBEVIP_IMAGE 由 cluster.env 定义
    KUBEVIP_IMAGE="${KUBEVIP_IMAGE:-ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}}"

    # 拉取镜像（ctr 不自动拉取，必须先 pull）
    echo "拉取 kube-vip 镜像: $KUBEVIP_IMAGE"
    ctr -n k8s.io images pull "$KUBEVIP_IMAGE" || {
        echo "[!] 从 ghcr.io 拉取失败，尝试离线导入..."
        if [ -f "${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar" ]; then
            ctr -n k8s.io images import "${OFFLINE_DIR:-/opt/k8s-offline}/images/kube-vip.tar"
        else
            echo "[✗] 无法获取 kube-vip 镜像"
            exit 1
        fi
    }

    # 生成 manifest（必须在 kubeadm init 之前放入）
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
    echo "[✓] kube-vip manifest 已生成: /etc/kubernetes/manifests/kube-vip.yaml"
    echo "    VIP: ${VIP}, 网卡: ${NIC}, 模式: ARP + LeaderElection"
fi

# --- 3. 生成 kubeadm 配置 ---
echo ""
echo "--- 生成 kubeadm 配置 ---"
mkdir -p /etc/kubernetes/manifests
# 动态生成 certSANs（多 Master 包含 VIP；单 Master 仅使用 master1 地址）
if [ "${MASTER_COUNT}" -gt 1 ]; then
    CERT_SANS="    - \"${VIP}\""
else
    CERT_SANS=""
fi
for ip in "${MASTER_IPS[@]}"; do
    CERT_SANS="${CERT_SANS}
    - \"${ip}\""
done
for name in "${MASTER_NAMES[@]}"; do
    CERT_SANS="${CERT_SANS}
    - \"${name}\""
done
CERT_SANS="${CERT_SANS}
    - \"localhost\"
    - \"127.0.0.1\""

if [ "${MASTER_COUNT}" -gt 1 ]; then
    CONTROL_PLANE_ENDPOINT="${VIP}:${API_SERVER_PORT}"
else
    CONTROL_PLANE_ENDPOINT="${MASTER1_IP}:${API_SERVER_PORT}"
fi

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
echo "[✓] kubeadm 配置已生成: /etc/kubernetes/kubeadm-config.yaml"

# --- 4. 预拉取镜像 ---
echo ""
echo "--- 预拉取 K8s 镜像（阿里云）---"
kubeadm config images pull --config /etc/kubernetes/kubeadm-config.yaml
echo "[✓] 镜像预拉取完成"

# --- 5. kubeadm init ---
echo ""
echo "--- 执行 kubeadm init ---"
kubeadm init --config /etc/kubernetes/kubeadm-config.yaml --upload-certs | tee /tmp/kubeadm-init.log

# --- 6. 配置 kubectl ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
echo "[✓] kubectl 已配置"

# --- 7. 提取 join 信息 ---
echo ""
echo "--- 提取 join 信息 ---"
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)

mkdir -p /etc/kubernetes/deploy
cat > /etc/kubernetes/deploy/join.env <<EOF
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# certificate-key 有效期 2 小时，token 有效期 24 小时
JOIN_CMD="${JOIN_CMD}"
CERT_KEY="${CERT_KEY}"
VIP="${VIP}"
API_SERVER_PORT="${API_SERVER_PORT}"
EOF
chmod 600 /etc/kubernetes/deploy/join.env
echo "[✓] join 信息已保存: /etc/kubernetes/deploy/join.env"

# --- 验证 ---
echo ""
echo "--- 验证 ---"
echo "等待 API Server 就绪..."
sleep 10

kubectl get nodes
echo ""
kubectl get pods -n kube-system
echo ""

if kubectl get nodes | grep -q "Ready"; then
    echo "[完成] master1 初始化成功"
    echo ""
    echo "=========================================="
    echo " 下一步："
    echo "   1. 在 master2/3 执行 05-join-master.sh"
    echo "   2. 在 node1-6 执行 06-join-worker.sh"
    echo "=========================================="
else
    echo "[!] master1 状态异常，请检查日志"
    echo "    kubectl get pods -n kube-system"
    echo "    journalctl -u kubelet -f"
fi
