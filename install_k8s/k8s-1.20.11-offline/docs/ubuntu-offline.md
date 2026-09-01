# Ubuntu 完全离线部署 Kubernetes 1.20.11 和 Helm 3.0.3

本文适用于无法访问公网和 SWR 的 Ubuntu x86_64 服务器。系统软件包使用 `packages/ubuntu/`，容器镜像使用 `images/k8s-images-offline.tar`。

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
```

在单控制面阶段，`API_ENDPOINT_IP` 暂时等于 `MASTER_IP`；后续迁移到 kube-vip 或负载均衡时，保持 `MASTER_IP` 和 `k8s-master` 不变，只把 `API_ENDPOINT_IP` 改为 VIP，再重新生成 `/etc/hosts` 中的 `k8s-api` 单独解析记录。

在**所有节点**配置相同的完整 `/etc/hosts`，包括 Master、三个 Worker 和集群统一 API 域名：

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

cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

## 三、离线安装 Docker 和 Kubernetes 组件

将 `packages/ubuntu/` 复制到每个节点的 `/tmp/packages/ubuntu/` 后执行。`os-packages/` 已包含 Kubernetes 1.20.11 在 Ubuntu 24.04 amd64 上所需的 `socat`、`ebtables`、`conntrack` 依赖，不需要访问 Ubuntu 软件源：

```bash
dpkg -i /tmp/packages/ubuntu/os-packages/containerd.io*.deb
dpkg -i /tmp/packages/ubuntu/os-packages/docker-ce-cli*.deb
dpkg -i /tmp/packages/ubuntu/os-packages/docker-ce*.deb
dpkg -i /tmp/packages/ubuntu/os-packages/socat_*.deb \
        /tmp/packages/ubuntu/os-packages/ebtables_*.deb \
        /tmp/packages/ubuntu/os-packages/conntrack_*.deb

dpkg -i /tmp/packages/ubuntu/kubernetes/kubeadm_1.20.11-00_amd64.deb \
        /tmp/packages/ubuntu/kubernetes/kubelet_1.20.11-00_amd64.deb \
        /tmp/packages/ubuntu/kubernetes/kubectl_1.20.11-00_amd64.deb \
        /tmp/packages/ubuntu/cni/kubernetes-cni_1.2.0-00_amd64.deb \
        /tmp/packages/ubuntu/cni/cri-tools_1.19.0-00_amd64.deb

dpkg --configure -a
apt-mark hold kubeadm kubelet kubectl kubernetes-cni cri-tools
```

上述命令必须在没有网络的情况下执行；不要使用 `apt-get install -f`，因为它会尝试从软件源下载缺失依赖。当前离线包中的依赖版本为：

```text
socat     1.8.0.0-4build3
ebtables   2.0.11-6build1
conntrack 1:1.4.8-1ubuntu1
```

这些依赖包基于 Ubuntu 24.04 Noble amd64。若目标系统不是 Ubuntu 24.04 amd64，应重新准备与目标系统版本匹配的依赖包。

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
systemctl enable kubelet
```

## 四、导入离线镜像并初始化

将 `images/k8s-images-offline.tar` 分发到每个节点：

```bash
docker load -i /tmp/k8s-images-offline.tar
```

控制面节点执行：

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

kubectl apply -f deploy/kube-flannel-offline.yaml
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
```

离线包 SHA-256：

```text
f87ec6d994d1a16a3ef07f0a7068d5453412f131cbb4f61e9f0e369a64c4967f3
```

## 五、Worker、Helm 和验证

在控制面生成 `kubeadm token create --print-join-command`，在已安装软件包并导入离线镜像的 Worker 上执行输出命令。

```bash
tar -xzf helm/helm-v3.0.3-linux-amd64.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
kubectl get nodes -o wide
kubectl get pods -A -o wide
helm version --short
```
