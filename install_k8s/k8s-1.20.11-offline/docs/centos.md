# CentOS 7 在线公网部署 Kubernetes 1.20.11 和 Helm 3.0.3

本文适用于能直接访问公网软件源、Kubernetes 历史官方公共镜像仓库及 Docker Hub 的 CentOS Linux 7 x86_64 服务器。

- Kubernetes 1.20.11 核心镜像使用阿里云镜像仓库 `registry.aliyuncs.com/google_containers`；
- Flannel 使用 Docker Hub 的 `docker.io/flannel/*`；
- 不需要 SWR 用户名、密码或 Docker 登录配置；
- 如服务器无法访问公共仓库或历史 Yum 源，请改用 [`centos-offline.md`](centos-offline.md) 或 [`swr-images.md`](swr-images.md)。

> CentOS 7 和 Kubernetes 1.20.11 均已停止维护。执行前先完成本文的版本和连通性检查；若历史仓库不再可用，应使用离线包或内部归档源。

## 一、部署参数与主控域名

```bash
MASTER_HOST=k8s-api
MASTER_IP=192.168.104.231
API_ENDPOINT_IP=${MASTER_IP}
NODE1_IP=192.168.104.232
NODE2_IP=192.168.104.233
NODE3_IP=192.168.104.234
POD_CIDR=10.244.0.0/16
SERVICE_CIDR=10.96.0.0/12
K8S_VERSION=1.20.11
```

在单控制面阶段，`API_ENDPOINT_IP` 暂时等于 `MASTER_IP`；后续迁移到 kube-vip 或负载均衡时，保持 `MASTER_IP` 和 `k8s-master` 不变，只把 `API_ENDPOINT_IP` 改为 VIP，再重新生成 `/etc/hosts` 中的 `k8s-api` 单独解析记录。

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

## 三、在线安装 Docker

CentOS 7 已 EOL；若默认 Yum 源不可用，先切换到可用 Vault 或企业内部镜像源。配置阿里云 Docker CE Yum 源：

```bash
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io
```

## 四、在线安装 kubeadm、kubelet、kubectl

阿里云和腾讯云保留的历史 Kubernetes Yum 元数据中已不再包含 `kubeadm/kubelet/kubectl 1.20.11`，因此不能使用 `yum install kubeadm-1.20.11`。本在线方案改为从 Kubernetes 官方发布站直接下载经校验的 v1.20.11 Linux amd64 二进制文件；系统依赖仍通过 CentOS Yum 在线安装。

```bash
yum install -y conntrack-tools ebtables ethtool socat iproute curl tar

install -d -m 0755 /usr/local/bin /opt/cni/bin
cd /tmp

for component in kubeadm kubelet kubectl; do
  curl -4 --fail --location \
    --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 \
    -o "${component}" \
    "https://storage.googleapis.com/kubernetes-release/release/v1.20.11/bin/linux/amd64/${component}"
  curl -4 --fail --location \
    --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 5 \
    -o "${component}.sha256" \
    "https://storage.googleapis.com/kubernetes-release/release/v1.20.11/bin/linux/amd64/${component}.sha256"
  echo "$(cat "${component}.sha256")  ${component}" | sha256sum -c -
  install -m 0755 "${component}" /usr/local/bin/"${component}"
done

# 在线版使用与离线包一致的 CNI v1.2.0；如果 GitHub Release 不可达，请改用离线文档。
curl -4 --fail --location \
  --connect-timeout 15 --max-time 600 --retry 2 --retry-delay 5 \
  -o cni-plugins-linux-amd64-v1.2.0.tar.gz \
  https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.2.0.tar.gz
```

为二进制版 kubelet 创建 systemd 服务和 kubeadm drop-in：

```bash
cat >/etc/systemd/system/kubelet.service <<'EOF'
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/systemd/system/kubelet.service.d
cat >/etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/var/lib/kubelet/kubeadm-env
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF

systemctl daemon-reload
systemctl enable kubelet

kubeadm version
kubelet --version
kubectl version --client
```

> Kubernetes 官方发布二进制文件通过 `storage.googleapis.com` 下载并进行 SHA-256 校验。CNI plugins v1.2.0 的 GitHub Release 在部分网络环境可能不可达；这种情况应使用 `centos-offline.md` 中的本地 CNI 包，不要使用未完整下载的文件。

## 五、配置 Docker 和 kubelet

本次 CentOS 7.9 实测使用 Docker 26.1.4；Kubernetes 1.20.11 会提示该 Docker 版本未列入其已验证版本列表，但 `kubeadm init`、Flannel 和 Worker 加入均已成功。

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

docker version
kubeadm version
kubelet --version
kubectl version --client
```

## 六、连通性验证

Docker Hub 镜像通过已配置的 `https://docker.1panel.live` 国内镜像加速服务拉取；Flannel YAML 仍保持官方镜像名 `docker.io/flannel/*`，无需修改。该公共加速服务的可用性可能变化，部署前必须执行以下实际拉取验证：

```bash
docker pull registry.aliyuncs.com/google_containers/pause:3.2
docker pull docker.io/flannel/flannel:v0.25.7
docker pull docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel2
```

任何一个镜像拉取失败时，不要继续本公网流程；应改用离线版或 SWR 版。

## 七、初始化控制面并部署公网 Flannel

- `--apiserver-advertise-address` 使用当前 Master 的实际 IP；
- `--control-plane-endpoint` 使用集群统一域名，未来可把域名解析切换到 kube-vip/负载均衡 VIP。

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
