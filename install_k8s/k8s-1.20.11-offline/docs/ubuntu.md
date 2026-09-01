# Ubuntu 在线公网部署 Kubernetes 1.20.11 和 Helm 3.0.3

本文适用于能直接访问公网软件源、Kubernetes 官方公共镜像仓库及 Docker Hub 的 Ubuntu x86_64 服务器。

- Kubernetes 1.20.11 核心镜像使用阿里云镜像仓库 `registry.aliyuncs.com/google_containers`；
- Flannel 使用 Docker Hub 的 `docker.io/flannel/*`；
- 不需要 SWR 用户名、密码或 Docker 登录配置；
- 如服务器不能访问这些公网地址，请改用 [`ubuntu-offline.md`](ubuntu-offline.md) 或 [`swr-images.md`](swr-images.md)。

> Kubernetes 1.20.11 已停止维护，且历史官方仓库、旧版 APT 包可能不再对所有网络可用。开始前必须按本文“连通性验证”确认。

## 一、部署参数与主控域名

```bash
MASTER_HOST=k8s-api
MASTER_IP=<MASTER_NODE_IP>
API_ENDPOINT_IP=${MASTER_IP}
NODE1_IP=<NODE1_IP>
NODE2_IP=<NODE2_IP>
NODE3_IP=<NODE3_IP>
POD_CIDR=10.244.0.0/16
SERVICE_CIDR=10.96.0.0/12
K8S_VERSION=1.20.11
```

在单控制面阶段，`API_ENDPOINT_IP` 暂时等于 `MASTER_IP`；后续迁移到 kube-vip 或负载均衡时，保持 `MASTER_IP` 和 `k8s-master` 不变，只把 `API_ENDPOINT_IP` 改为 VIP，再重新生成 `/etc/hosts` 中的 `k8s-api` 单独解析记录。

在**所有节点**配置相同的完整 `/etc/hosts`，包括 Master、三个 Worker 和集群统一 API 域名。先根据当前节点设置对应主机名：

```bash
# Master 执行：hostnamectl set-hostname k8s-master
# Worker1 执行：hostnamectl set-hostname k8s-node1
# Worker2 执行：hostnamectl set-hostname k8s-node2
# Worker3 执行：hostnamectl set-hostname k8s-node3

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
hostnamectl set-hostname k8s-master

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

## 三、在线安装 Docker

```bash
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  >/etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
```

## 四、在线安装 kubeadm、kubelet、kubectl

Kubernetes 1.20.11 使用历史 APT 源。先查询指定版本，只有出现 `1.20.11-00` 才继续安装：

```bash
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-cache madison kubeadm | grep '1.20.11-00'
```

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  kubeadm=1.20.11-00 \
  kubelet=1.20.11-00 \
  kubectl=1.20.11-00 \
  kubernetes-cni=1.2.0-00 \
  cri-tools=1.19.0-00
apt-mark hold kubeadm kubelet kubectl kubernetes-cni cri-tools
```

## 五、配置 Docker 和 kubelet

```bash
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://docker.1panel.live"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"},
  "storage-driver": "overlay2"
}
EOF
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker
systemctl enable kubelet
```

## 六、连通性验证

Docker Hub 镜像通过已配置的 `https://docker.1panel.live` 国内镜像加速服务拉取；Flannel YAML 仍保持官方镜像名 `docker.io/flannel/*`，无需修改。该公共加速服务的可用性可能变化，部署前必须执行以下实际拉取验证：

```bash
docker pull registry.aliyuncs.com/google_containers/pause:3.2
docker pull docker.io/flannel/flannel:v0.25.7
docker pull docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel2
```

任何一个拉取失败时，不要继续本公网流程；应改用离线版或 SWR 版。

## 七、初始化控制面并部署公网 Flannel

- `--apiserver-advertise-address` 使用当前 Master 的实际 IP；
- `--control-plane-endpoint` 使用集群统一域名，方便未来改为 kube-vip/负载均衡 VIP。

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

kubectl apply -f deploy/kube-flannel-online.yaml
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
```

## 八、Worker 加入、Helm 和验证

```bash
# 控制面生成 join 命令
kubeadm token create --print-join-command

# 在每个 Worker 执行输出的 join 命令

# Helm 包为 Ubuntu/CentOS 共用 Linux amd64 包
tar -xzf helm/helm-v3.0.3-linux-amd64.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm

kubectl get nodes -o wide
kubectl get pods -A -o wide
helm version --short
```
