# K8s 1.20.11 + Docker + Flannel + Helm 3.0.3 部署文档

下载离线包
```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s-1.20.11-offline:26.8.9
```
复制出文件可参考[Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/mlda3n2mcphvzo2o#wpXxl)
```
docker run --rm \
  -v /data/softs:/host \
  swr.cn-southwest-2.myhuaweicloud.com/zqli/jenkens-plugins:lzq1 \
  cp /data/jenkins-plugins.tar.gz /host/
```
```
ctr image mount ccr.ccs.tencentyun.com/zqli/nerdctl-full:2.3.4-arm /mnt/nerdctl
cp /mnt/nerdctl/usr/local/bin/nerdctl ./nerdctl
ctr image unmount /mnt/nerdctl
```

## 一、环境信息

| 节点 | 内网 IP | 公网 IP | 角色 | OS | CPU |
|------|---------|---------|------|-----|-----|
| k8s-master | 172.30.0.100 | 8.130.8.173 | Control Plane | Ubuntu 24.04.4 LTS | 4C |
| k8s-node1 | 172.30.0.101 | — | Worker | Ubuntu 24.04.4 LTS | 4C |
| k8s-node2 | 172.30.0.102 | — | Worker | Ubuntu 24.04.4 LTS | 4C |
| k8s-node3 | 172.30.0.103 | — | Worker | Ubuntu 24.04.4 LTS | 4C |

| 组件 | 版本 |
|------|------|
| Kubernetes | 1.20.11 |
| Docker | 29.6.2 |
| Flannel | 0.25.7 |
| Helm | 3.0.3 |
| CoreDNS | 1.7.0 |
| Etcd | 3.4.13-0 |
| Pause | 3.2 |

**集群网络规划：**

| 网络 | CIDR |
|------|------|
| Service CIDR | 10.96.0.0/12 |
| Pod CIDR | 10.244.0.0/16 |
| API Server | https://172.30.0.100:6443 |

## 二、SWR 镜像清单

所有镜像已推送到华为云 SWR，部署时使用 `--image-repository` 指定。

| 镜像 | SWR 地址 |
|------|----------|
| kube-apiserver | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-apiserver:v1.20.11` |
| kube-controller-manager | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-controller-manager:v1.20.11` |
| kube-scheduler | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-scheduler:v1.20.11` |
| kube-proxy | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/kube-proxy:v1.20.11` |
| etcd | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/etcd:3.4.13-0` |
| coredns | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/coredns:1.7.0` |
| pause | `swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/pause:3.2` |
| flannel | `swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7` |
| flannel-cni-plugin | `swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2` |
> flannel本地镜像似乎是  
`swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/flannel:v0.25.7`  
`swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers/flannel-cni-plugin:v1.5.1-flannel2`

## 三、所有节点基础环境

```bash
# 1. 主机名
hostnamectl set-hostname k8s-master   # Master
hostnamectl set-hostname k8s-node1    # Worker，依次类推

# 2. /etc/hosts
cat >> /etc/hosts << EOF
172.30.0.100 k8s-master
172.30.0.101 k8s-node1
172.30.0.102 k8s-node2
172.30.0.103 k8s-node3
EOF

cat >> /etc/hosts << EOF
10.0.0.100 k8s-master
10.0.0.101 k8s-node1
10.0.0.102 k8s-node2
10.0.0.103 k8s-node3
EOF

for i in {100..103}; do ssh-copy-id root@10.0.0.$i; done

# 3. 关闭 swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 4. 内核模块
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 5. 内核参数
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
```

## 四、安装 Docker

### 4.1 在线安装（有外网）

```bash
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 阿里云 Docker CE 源
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli
```

### 4.2 离线安装（无外网 — 使用 deb 包）

离线包位于 `ubuntu-deb/` 目录，包含 Docker 三件套：`docker-ce`、`docker-ce-cli`、`containerd.io`。

```bash
# 1. 将 ubuntu-deb/ 目录拷贝到目标节点
scp -r ubuntu-deb/ root@目标节点:/tmp/
for i in {100..103}; do scp -r ubuntu-deb/ root@10.0.0.$i:/tmp/; done

# 2. 在目标节点上安装
dpkg -i /tmp/ubuntu-deb/containerd.io*.deb
dpkg -i /tmp/ubuntu-deb/docker-ce-cli*.deb
dpkg -i /tmp/ubuntu-deb/docker-ce*.deb

# 3. 如果缺依赖，一次性补全
apt-get install -f -y
```

### 4.3 配置 Docker（所有节点）

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload
systemctl enable docker --now
docker --version
```

## 五、安装 kubeadm/kubelet/kubectl

### 5.1 在线安装（有外网 — 阿里云 APT 源）

```bash
curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  kubeadm=1.20.11-00 \
  kubelet=1.20.11-00 \
  kubectl=1.20.11-00 \
  kubernetes-cni=1.2.0-00 \
  -o Dpkg::Options::="--force-confold"

apt-mark hold kubeadm kubelet kubectl kubernetes-cni
```

### 5.2 离线安装（无外网 — 使用 deb 包）

离线包位于 `ubuntu-deb/` 目录，仅需 4 个 deb：

| deb 包 | 说明 |
|--------|------|
| `kubeadm_1.20.11-00_amd64.deb` | 集群初始化工具 |
| `kubelet_1.20.11-00_amd64.deb` | 节点代理（每个节点运行） |
| `kubectl_1.20.11-00_amd64.deb` | 命令行管理工具 |
| `kubernetes-cni_1.2.0-00_amd64.deb` | CNI 网络插件基础文件 |

```bash
# 1. 将 ubuntu-deb/ 中的 K8s deb 拷贝到目标节点
scp ubuntu-deb/kube*.deb ubuntu-deb/kubernetes-cni*.deb root@目标节点:/tmp/

for i in {100..103}; do scp -r ubuntu-deb/kube*.deb root@10.0.0.$i:/tmp/; done

# 2. 在目标节点上安装
dpkg -i /tmp/kubeadm_1.20.11-00_amd64.deb \
        /tmp/kubelet_1.20.11-00_amd64.deb \
        /tmp/kubectl_1.20.11-00_amd64.deb \
        /tmp/kubernetes-cni_1.2.0-00_amd64.deb

apt-mark hold kubeadm kubelet kubectl kubernetes-cni
```



有的需安装依赖

```
sudo tar zxvf ubuntu-deb/crictl-v1.20.0-linux-amd64.tar.gz -C /usr/local/bin
crictl --version

# 创建工作目录
mkdir -p /tmp/cri-tools-dummy/DEBIAN

# 写入 control 文件
cat > /tmp/cri-tools-dummy/DEBIAN/control <<EOF
Package: cri-tools
Version: 1.20.0
Section: misc
Priority: optional
Architecture: amd64
Description: Dummy package to satisfy cri-tools dependency for kubeadm
EOF

# 构建 .deb 包
dpkg-deb --build /tmp/cri-tools-dummy /tmp/cri-tools_1.20.0_amd64.deb
```

```
dpkg -i /tmp/cri-tools_1.20.0_amd64.deb

apt update
apt install -y socat ebtables conntrack
```

```
重新配置 kubeadm 和 kubelet（使它们识别已满足的依赖）

dpkg --configure -a
这一步会重新配置所有未配置的包，现在依赖都已满足，配置会顺利完成。

5. 验证所有组件

kubeadm version
kubelet --version
kubectl version --client
crictl --version
```









### 5.3 配置 kubelet（所有节点）

```bash
# 确认 kubelet dropin 中 ExecStart 路径为 /usr/bin/kubelet
sed -i 's|/usr/local/bin/kubelet|/usr/bin/kubelet|g' \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl enable kubelet
```

## 六、初始化 Master（172.30.0.100）

### 6.1 登录 SWR

```bash
docker login swr.cn-southwest-2.myhuaweicloud.com
```

### 6.2 拉取 SWR 镜像（可选，加速初始化）

```bash
REG="swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers"
for img in \
  kube-apiserver:v1.20.11 \
  kube-controller-manager:v1.20.11 \
  kube-scheduler:v1.20.11 \
  kube-proxy:v1.20.11 \
  etcd:3.4.13-0 \
  coredns:1.7.0 \
  pause:3.2; do
  docker pull ${REG}/${img}
done

# Flannel 镜像
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
```



离线镜像

```
for i in {100..103}; do scp -r images/k8s-images-swr.tar root@10.0.0.$i:/tmp/; done

docker load -i /tmp/k8s-images-swr.tar
```





### 6.3 kubeadm init

```bash
kubeadm init \
  --kubernetes-version=v1.20.11 \
  --apiserver-advertise-address=172.30.0.100 \
  --image-repository=swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers \
  --service-cidr=10.96.0.0/12 \
  --pod-network-cidr=10.244.0.0/16 \
  --ignore-preflight-errors=all
  
  
kubeadm init \
  --kubernetes-version=v1.20.11 \
  --apiserver-advertise-address=10.0.0.100 \
  --image-repository=swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers \
  --service-cidr=10.96.0.0/12 \
  --pod-network-cidr=10.244.0.0/16 \
  --ignore-preflight-errors=all  
```

### 6.4 配置 kubectl

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

## 七、部署 Flannel CNI（使用 SWR 镜像）

完整 YAML 文件：`deploy/kube-flannel-swr.yaml`

关键修改点 — DaemonSet 中所有 `image:` 字段替换为 SWR 地址：

```yaml
# 原始 -> SWR
# docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel2
#   -> swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
# docker.io/flannel/flannel:v0.25.7
#   -> swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
```

```bash
kubectl apply -f deploy/kube-flannel-swr.yaml
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=120s
```

完整 Flannel YAML（kube-flannel-swr.yaml）：

```yaml
cat >kube-flannel-swr.yaml<<-'EOF'
---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: psp.flannel.unprivileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default
    seccomp.security.alpha.kubernetes.io/defaultProfileName: docker/default
    apparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default
    apparmor.security.beta.kubernetes.io/defaultProfileName: runtime/default
spec:
  privileged: false
  volumes:
  - configMap
  - secret
  - emptyDir
  - hostPath
  allowedHostPaths:
  - pathPrefix: "/etc/cni/net.d"
  - pathPrefix: "/etc/kube-flannel"
  - pathPrefix: "/run/flannel"
  readOnlyRootFilesystem: false
  allowPrivilegeEscalation: false
  runAsUser:
    rule: RunAsAny
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flannel
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes/status"]
  verbs: ["patch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["clustercidrs"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "EnableNFTables": false,
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      hostNetwork: true
      priorityClassName: system-node-critical
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni-plugin
        image: swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
        image: swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: 100m
            memory: 50Mi
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
EOF
```

## 八、Worker 节点加入集群

### 8.1 预拉取 SWR 镜像（Worker 有外网时）

```bash
docker login swr.cn-southwest-2.myhuaweicloud.com

REG="swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers"
docker pull ${REG}/pause:3.2
docker pull ${REG}/kube-proxy:v1.20.11
docker pull ${REG}/coredns:1.7.0

docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel:v0.25.7
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli/flannel/flannel-cni-plugin:v1.5.1-flannel2
```

### 8.2 Worker 无外网时 — 从 Master 分发镜像

```bash
# Master 上操作
REG="swr.cn-southwest-2.myhuaweicloud.com/zqli"
docker save \
  ${REG}/google_containers/pause:3.2 \
  ${REG}/google_containers/kube-proxy:v1.20.11 \
  ${REG}/google_containers/coredns:1.7.0 \
  ${REG}/flannel/flannel:v0.25.7 \
  ${REG}/flannel/flannel-cni-plugin:v1.5.1-flannel2 \
  -o /tmp/worker-images.tar

for ip in 172.30.0.101 172.30.0.102 172.30.0.103; do
  scp /tmp/worker-images.tar root@$ip:/tmp/
  ssh root@$ip "docker load -i /tmp/worker-images.tar && rm /tmp/worker-images.tar"
done
```

### 8.3 执行 join

```bash
# Master 上获取 join 命令
kubeadm token create --print-join-command

# 输出示例：
# kubeadm join 172.30.0.100:6443 --token <TOKEN> \
#     --discovery-token-ca-cert-hash sha256:<HASH>

# 在每个 Worker 上执行（尾部追加 --ignore-preflight-errors=all）
kubeadm join 172.30.0.100:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --ignore-preflight-errors=all
```

## 九、安装 Helm 3.0.3

```bash
curl -fsSL -o /tmp/helm.tar.gz \
  https://get.helm.sh/helm-v3.0.3-linux-amd64.tar.gz
tar -xzf /tmp/helm.tar.gz -C /tmp
install -m 755 /tmp/linux-amd64/helm /usr/local/bin/helm
helm version --short
# v3.0.3+gac925eb
```

离线

```
scp helm/helm-v3.0.3-linux-amd64.tar.gz root@10.0.0.100:/tmp/
tar -xzf /tmp/helm-v3.0.3-linux-amd64.tar.gz -C /tmp
install -m 755 /tmp/linux-amd64/helm /usr/local/bin/helm
helm version --short
```





## 十、验证

```bash
# 节点状态
kubectl get nodes -o wide

# 预期输出：
# NAME         STATUS   ROLES                  AGE   VERSION    INTERNAL-IP
# k8s-master   Ready    control-plane,master   xx    v1.20.11   172.30.0.100
# k8s-node1    Ready    <none>                 xx    v1.20.11   172.30.0.101
# k8s-node2    Ready    <none>                 xx    v1.20.11   172.30.0.102
# k8s-node3    Ready    <none>                 xx    v1.20.11   172.30.0.103

# 所有 Pod
kubectl get pods -A

# 预期每个节点一个 flannel Pod、一个 kube-proxy Pod，全部 Running

# 功能测试
kubectl create deployment nginx-test --image=nginx:alpine
kubectl get pods -l app=nginx-test -o wide
# Running 后清理
kubectl delete deploy nginx-test
```

## 十一、离线安装包清单

```
k8s-1.20.11-offline/
├── ubuntu-deb/           # K8s + Docker deb 包 (131M)
│   ├── docker-ce_5:29.6.2-1~ubuntu.24.04~noble_amd64.deb
│   ├── docker-ce-cli_5:29.6.2-1~ubuntu.24.04~noble_amd64.deb
│   ├── containerd.io_2.2.6-1~ubuntu.24.04~noble_amd64.deb
│   ├── kubeadm_1.20.11-00_amd64.deb
│   ├── kubelet_1.20.11-00_amd64.deb
│   ├── kubectl_1.20.11-00_amd64.deb
│   ├── kubernetes-cni_1.2.0-00_amd64.deb
│   └── cri-tools_1.19.0-00_amd64.deb
├── images/               # Docker 镜像 tar
│   ├── all-k8s-images.tar        (224M, 原始 aliyun 镜像)
│   └── k8s-images-swr-final.tar  (733M, SWR 已 tag 镜像)
├── helm/
│   └── helm-v3.0.3-linux-amd64.tar.gz  (12M)
└── deploy/
    └── kube-flannel-swr.yaml     # Flannel DaemonSet (SWR 镜像)
```

## 十二、关键注意事项

| 问题 | 说明 |
|------|------|
| **Worker 无外网** | 镜像从 Master `docker save/load` 分发，或使用 SWR 自定义 Flannel YAML |
| **kubelet ExecStart 路径** | APT 包安装到 `/usr/bin/kubelet`，检查 dropin 文件中的路径 |
| **cgroup v2** | Ubuntu 24.04 默认 cgroup v2，Docker daemon.json 必须配置 `native.cgroupdriver=systemd` |
| **Join Token 过期** | 24h 过期，Master 执行 `kubeadm token create --print-join-command` 重新生成 |
| **flannel 镜像名** | 默认 YAML 拉取 `docker.io/flannel/*`，无外网节点需 tag 为本地镜像或使用 SWR 版 YAML |
