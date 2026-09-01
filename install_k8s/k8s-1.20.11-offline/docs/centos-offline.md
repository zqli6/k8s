# CentOS 7 完全离线部署 Kubernetes 1.20.11 和 Helm 3.0.3

本文适用于无法访问公网和 SWR 的 CentOS Linux 7 x86_64 服务器。

部署时只需将下列内容打包并传到目标服务器：

```text
packages/centos/
images/k8s-images-offline.tar
helm/helm-v3.0.3-linux-amd64.tar.gz
deploy/kube-flannel-offline.yaml
docs/centos-offline.md
```

在目标服务器准备统一目录，并将上述内容解压到该目录：

```bash
ROOT=/opt/k8s-1.20.11-offline
mkdir -p "${ROOT}"
tar -xzf k8s-1.20.11-centos-offline.tar.gz -C "${ROOT}"
```

> 制作安装包时，从项目根目录打包上述路径；不要把 Ubuntu 包或 SWR 镜像包混入 CentOS 安装包。

## 一、部署参数和主控域名

```bash
MASTER_HOST=k8s-api
MASTER_IP=<MASTER_NODE_IP>
API_ENDPOINT_IP=${MASTER_IP}
NODE1_IP=<NODE1_IP>
NODE2_IP=<NODE2_IP>
NODE3_IP=<NODE3_IP>
POD_CIDR=10.244.0.0/16
SERVICE_CIDR=10.96.0.0/12

OS_PACKAGES=${ROOT}/packages/centos/os-packages
K8S_PACKAGES=${ROOT}/packages/centos/kubernetes
CNI_PACKAGES=${ROOT}/packages/centos/cni
SYSTEMD_PACKAGES=${ROOT}/packages/centos/systemd
IMAGE_BUNDLE=${ROOT}/images/k8s-images-offline.tar
DEPLOY_DIR=${ROOT}/deploy
```

在单控制面阶段，`API_ENDPOINT_IP` 等于 `MASTER_IP`；后续迁移到 kube-vip 或负载均衡时，只将 `API_ENDPOINT_IP` 改为 VIP，保持 `MASTER_IP`、`k8s-master` 和各 Worker 主机名不变。

在**所有节点**配置相同的 `/etc/hosts`，包括 Master、三个 Worker 和独立的 API 域名：

```bash
# 根据当前节点执行对应的 hostnamectl 命令
# Master：hostnamectl set-hostname k8s-master
# Worker1：hostnamectl set-hostname k8s-node1
# Worker2：hostnamectl set-hostname k8s-node2
# Worker3：hostnamectl set-hostname k8s-node3

sed -i '/# BEGIN K8S HOSTS/,/# END K8S HOSTS/d' /etc/hosts
cat >>/etc/hosts <<EOF
# BEGIN K8S HOSTS
${MASTER_IP} k8s-master
${API_ENDPOINT_IP} ${MASTER_HOST}
${NODE1_IP} k8s-node1
${NODE2_IP} k8s-node2
${NODE3_IP} k8s-node3
# END K8S HOSTS
EOF

getent hosts "${MASTER_HOST}" k8s-master k8s-node1 k8s-node2 k8s-node3
```

## 二、所有节点基础配置

```bash
swapoff -a
sed -ri '/\sswap\s/s/^/#/' /etc/fstab

setenforce 0 || true
sed -ri 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
systemctl disable --now firewalld || true

cat >/etc/modules-load.d/k8s.conf <<'EOF'
br_netfilter
EOF
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

## 三、使用本地 RPM 离线安装 Docker 和依赖

`packages/centos/os-packages/` 只保留 CentOS 7 x86_64 RPM。不要启用公网 Yum 源：

```bash
yum localinstall -y --disablerepo='*' \
  "${OS_PACKAGES}"/*.x86_64.rpm \
  "${OS_PACKAGES}"/*.noarch.rpm
```

配置并启动 Docker：

```bash
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"},
  "storage-driver": "overlay2"
}
EOF
systemctl daemon-reload
systemctl enable --now docker
```

## 四、安装 Kubernetes 二进制、CNI 和 kubelet

```bash
install -m 0755 "${K8S_PACKAGES}/kubeadm" /usr/local/bin/kubeadm
install -m 0755 "${K8S_PACKAGES}/kubelet" /usr/local/bin/kubelet
install -m 0755 "${K8S_PACKAGES}/kubectl" /usr/local/bin/kubectl

mkdir -p /opt/cni/bin
tar -C /opt/cni/bin \
  -xzf "${CNI_PACKAGES}/cni-plugins-linux-amd64-v1.2.0.tar.gz"

install -m 0644 "${SYSTEMD_PACKAGES}/kubelet.service" \
  /etc/systemd/system/kubelet.service
mkdir -p /etc/systemd/system/kubelet.service.d
install -m 0644 "${SYSTEMD_PACKAGES}/10-kubeadm.conf" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload
systemctl enable kubelet

kubeadm version
kubelet --version
kubectl version --client
command -v conntrack
command -v socat
test -x /opt/cni/bin/bridge
```

## 五、导入离线镜像并初始化控制面

在每个节点执行：

```bash
docker load -i "${IMAGE_BUNDLE}"
```

在控制面节点执行：

```bash
kubeadm init \
  --kubernetes-version=v1.20.11 \
  --control-plane-endpoint="${MASTER_HOST}:6443" \
  --apiserver-advertise-address="${MASTER_IP}" \
  --image-repository=registry.aliyuncs.com/google_containers \
  --service-cidr="${SERVICE_CIDR}" \
  --pod-network-cidr="${POD_CIDR}"

mkdir -p "$HOME/.kube"
cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

kubectl apply -f "${DEPLOY_DIR}/kube-flannel-offline.yaml"
kubectl rollout status daemonset/kube-flannel-ds \
  -n kube-flannel --timeout=180s
```

## 六、Worker 加入集群

在控制面生成加入命令：

```bash
kubeadm token create --print-join-command
```

在每个 Worker 执行输出的命令。Worker 必须已经完成本文第三、四、五节中的离线 RPM、二进制、CNI 和镜像安装。

## 七、安装 Helm 3.0.3

Helm Linux amd64 二进制包可在 Ubuntu 和 CentOS 共用：

```bash
tar -xzf "${ROOT}/helm/helm-v3.0.3-linux-amd64.tar.gz" -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
helm version --short
```

## 八、验证

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get daemonset -n kube-flannel
helm version --short
```

期望结果：

- `k8s-master`、`k8s-node1`、`k8s-node2`、`k8s-node3` 均为 `Ready`；
- 每个节点各有一个 Flannel Pod 和一个 kube-proxy Pod，状态为 `Running`；
- CoreDNS、etcd、API Server、Controller Manager、Scheduler 均为 `Running`。

## 九、当前已验证环境和校验值

本流程已经在以下环境完成四节点离线部署验证：

```text
OS: CentOS Linux 7.9.2009 x86_64
Kubernetes: v1.20.11
Docker: 26.1.4
Flannel: v0.25.7
CNI: v1.2.0
```

公共离线镜像包 SHA-256：

```text
f87ec6d994d1a16a3ef07f0a7068d5453412f131cbb4f61e9f0e369a64c4967f
```

> 本文验证的是 CentOS 离线部署。Ubuntu 离线材料目前不纳入本次验证范围。
