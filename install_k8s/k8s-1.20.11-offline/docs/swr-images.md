# 华为云 SWR 私有仓库部署 Kubernetes 1.20.11（Ubuntu / CentOS 通用）

本文仅说明**镜像从华为云 SWR 私有仓库拉取**的流程，适用于 Ubuntu 和 CentOS x86_64。

- 先按照系统对应的公网在线文档完成 Docker、kubeadm、kubelet、kubectl 安装：[`ubuntu.md`](ubuntu.md) 或 [`centos.md`](centos.md)；
- Kubernetes 核心镜像和 Flannel 镜像均从 SWR 拉取；
- 不使用、不保存本地 SWR 镜像 tar；
- SWR 私有仓库认证配置必须在每个节点完成。

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

## 二、SWR Docker 凭据（每个节点）

SWR 是私有仓库。将下列文件写入每个节点；不要将真实密码、生成的 `config.json` 或 Base64 凭据提交到 Git。

```bash
mkdir -p /root/.docker
cat >/root/.docker/config.json <<'EOF'
{
  "auths": {
    "swr.cn-southwest-2.myhuaweicloud.com": {
      "auth": "<BASE64_USERNAME_COLON_PASSWORD>"
    }
  }
}
EOF
chmod 600 /root/.docker/config.json
```

在安全环境生成 `auth` 值：

```bash
printf '%s' '<SWR_USERNAME>:<SWR_PASSWORD>' | base64 -w 0
```

将输出替换文件中的 `<BASE64_USERNAME_COLON_PASSWORD>`。可使用以下命令验证凭据：

```bash
printf '%s' '<SWR_PASSWORD>' | docker login \
  swr.cn-southwest-2.myhuaweicloud.com \
  --username '<SWR_USERNAME>' \
  --password-stdin
```

## 三、SWR 镜像地址

Kubernetes 核心镜像仓库：

```text
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers
```

```text
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-apiserver:v1.20.11
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-controller-manager:v1.20.11
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-scheduler:v1.20.11
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-proxy:v1.20.11
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/etcd:3.4.13-0
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/coredns:1.7.0
swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/pause:3.2
```

Flannel 的真实 SWR 镜像地址：

```text
swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
```

不要使用错误的 `zqli/google_containers/flannel*` 地址。

## 四、验证镜像拉取、初始化和 Flannel

控制面节点先验证核心镜像和 Flannel 拉取：

```bash
kubeadm config images pull \
  --kubernetes-version=v1.20.11 \
  --image-repository=swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers

docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
```

初始化控制面：

```bash
kubeadm init \
  --kubernetes-version=v1.20.11 \
  --control-plane-endpoint="${MASTER_HOST}:6443" \
  --apiserver-advertise-address="${MASTER_IP}" \
  --image-repository=swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers \
  --service-cidr="${SERVICE_CIDR}" \
  --pod-network-cidr="${POD_CIDR}"

mkdir -p "$HOME/.kube"
cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

创建 Flannel 从私有 SWR 拉取镜像需要的 Secret，并部署 Flannel：

```bash
kubectl create namespace kube-flannel --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic swr-registry-credentials \
  --namespace kube-flannel \
  --from-file=.dockerconfigjson=/root/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f deploy/kube-flannel-swr.yaml
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
```

`deploy/kube-flannel-swr.yaml` 已引用 `swr-registry-credentials`，不需要执行 `docker tag`。

## 五、Worker、Helm 和验证

Worker 也要先完成本文件的 `/root/.docker/config.json` 配置，然后在控制面执行：

```bash
kubeadm token create --print-join-command
```

在 Worker 执行输出命令。Helm 包对 Ubuntu 和 CentOS 通用：

```bash
tar -xzf helm/helm-v3.0.3-linux-amd64.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
kubectl get nodes -o wide
kubectl get pods -A -o wide
helm version --short
```
