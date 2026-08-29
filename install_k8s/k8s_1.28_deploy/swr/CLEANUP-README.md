# SWR 版 Kubernetes 实验环境清理

本清理步骤适用于重新部署和 3 Master HA 实验。3 Master 实验必须清理全部参与节点；不能只清理 master1，也不能把已经加入集群的 worker 直接改成 master。尤其要删除旧的 `/etc/kubernetes/kubelet.conf`、`/var/lib/kubelet`、`/var/lib/etcd` 和旧 kubelet systemd unit。

> ⚠️ 这是破坏性操作：会删除 Kubernetes 配置、etcd 数据、CNI 状态、Pod 网络和 kubeconfig。仅在确认节点不承载需要保留的业务时执行。
>
> 本文不会删除 Docker 镜像和 Docker 数据；containerd 也默认保留。这样可以减少重新拉取镜像的时间。

## 1. 实验拓扑配置

在 `swr/config/cluster.env` 中只修改节点数组和 VIP，保留数组机制。单 master 实验示例：

```bash
MASTER_NODES=(
    "192.168.104.231 master1"
)

WORKER_NODES=(
    "192.168.104.232 node1"
    "192.168.104.233 node2"
    "192.168.104.234 node3"
)

VIP="192.168.104.200"
```

多 master 实验必须使用奇数个 master，例如：

```bash
MASTER_NODES=(
    "192.168.104.231 master1"
    "192.168.104.232 master2"
    "192.168.104.233 master3"
)
```

剩余节点放入 `WORKER_NODES`。不要把同一个 IP 同时放入两个列表，也不要把 VIP 配成节点 IP。

## 2. 清理前检查

在每台测试节点执行：

```bash
hostname
hostname -I
ip route
kubeadm version -o short 2>/dev/null || true
systemctl is-active kubelet 2>/dev/null || true
systemctl is-active containerd 2>/dev/null || true
kubectl get nodes 2>/dev/null || true
ip link show | egrep 'cni|flannel|cali|tunl|vxlan|kube-ipvs|docker' || true
```

确认没有需要保留的 Kubernetes 集群或业务数据后，再继续。

## 3. 完整清理 Kubernetes 和 CNI

按顺序在每台节点执行：

```bash
systemctl disable --now kubelet 2>/dev/null || true

# kubeadm reset 会清理 kubeadm 管理的节点状态、静态 Pod 和部分网络规则
kubeadm reset -f 2>/dev/null || true

# 停止可能残留的容器运行时任务；不删除 Docker/containerd 镜像
systemctl stop kubelet 2>/dev/null || true

# 清理 Kubernetes、kubelet、CNI 和 kubeconfig 状态
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /etc/cni/net.d
rm -rf /var/lib/cni
rm -rf /run/calico
rm -rf /var/run/calico
rm -rf /var/lib/calico
rm -rf /etc/cni
rm -rf /root/.kube

# 清理可能由 Flannel/Calico 创建的接口、路由和地址
for dev in cni0 flannel.1 flannel-v6 tunl0 vxlan.calico kube-ipvs0; do
    ip link delete "$dev" 2>/dev/null || true
done

# 删除残留的 cali* veth；只操作名称匹配 CNI 的接口
for dev in $(ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1 | grep -E '^(cali|veth)' || true); do
    ip link delete "$dev" 2>/dev/null || true
done

# 删除 CNI/Calico/Flannel 残留路由（失败可忽略）
ip route flush table 77 2>/dev/null || true
ip route flush table 80 2>/dev/null || true
```

### 清理 iptables 和 IPVS

`kubeadm reset` 通常不会删除所有 kube-proxy、Calico 或 Flannel 规则。以下命令会清理常见 Kubernetes 链：

```bash
# 删除 kube-proxy 常见链及引用
iptables-save | awk '/^-A (KUBE-|CALI-|FLANNEL-)/ {print}' > /tmp/k8s-iptables-rules.txt || true
iptables -t nat -S 2>/dev/null | awk '/^-A (KUBE-|CALI-|FLANNEL-)/ {print}' | sed 's/^-A /-D /' | while read -r rule; do iptables -t nat $rule 2>/dev/null || true; done
iptables -t filter -S 2>/dev/null | awk '/^-A (KUBE-|CALI-|FLANNEL-)/ {print}' | sed 's/^-A /-D /' | while read -r rule; do iptables -t filter $rule 2>/dev/null || true; done
iptables -t mangle -S 2>/dev/null | awk '/^-A (KUBE-|CALI-|FLANNEL-)/ {print}' | sed 's/^-A /-D /' | while read -r rule; do iptables -t mangle $rule 2>/dev/null || true; done

# 删除空的自定义链；内置链不删除
for table in filter nat mangle; do
    iptables -t "$table" -S 2>/dev/null | awk '/^-N (KUBE-|CALI-|FLANNEL-)/ {print $2}' | while read -r chain; do
        iptables -t "$table" -F "$chain" 2>/dev/null || true
        iptables -t "$table" -X "$chain" 2>/dev/null || true
    done
done

# 清除 IPVS 虚拟服务；不会删除普通路由
ipvsadm -C 2>/dev/null || true
```

> ⚠️ 不要直接执行 `iptables -F`、`iptables -t nat -F` 或 `ip route flush table main`。这些命令可能破坏宿主机 SSH、Docker 或其他业务网络。

## 4. 清理 Flannel/Calico 服务残留

```bash
systemctl disable --now flanneld 2>/dev/null || true
systemctl disable --now calico-node 2>/dev/null || true
systemctl disable --now docker 2>/dev/null || true

rm -f /etc/systemd/system/flanneld.service
rm -f /usr/lib/systemd/system/flanneld.service
rm -f /etc/systemd/system/calico-node.service
systemctl daemon-reload
```

如果 Flannel 或 Calico 是以容器方式运行，先查看再按容器名删除：

```bash
docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' | egrep 'calico|flannel|kube-' || true
ctr -n k8s.io containers list 2>/dev/null | egrep 'calico|flannel|kube-' || true
```

确认这些容器只属于待清理的 Kubernetes 实验后：

```bash
docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' | awk '/calico|flannel|kube-/{print $1}' | xargs -r docker rm -f
ctr -n k8s.io containers list -q 2>/dev/null | xargs -r -n1 ctr -n k8s.io containers delete
```

最后一条会删除 containerd `k8s.io` namespace 中的所有容器元数据，必须确认该 namespace 没有其他业务。

## 5. 清理旧 Kubernetes 软件和仓库（可选）

如果要彻底重新安装 Kubernetes 1.28，建议清理旧 kubeadm/kubelet/kubectl，尤其是手工放在 `/usr/local/bin` 的旧版本：

```bash
yum remove -y kubelet kubeadm kubectl kubernetes-cni 2>/dev/null || true
yum versionlock delete kubelet kubeadm kubectl 2>/dev/null || true
rm -f /usr/local/bin/kubeadm /usr/local/bin/kubelet /usr/local/bin/kubectl
rm -f /etc/yum.repos.d/kubernetes.repo
```

如果希望保留 containerd、Docker 和已有镜像，不要执行：

```bash
yum remove containerd.io docker-ce docker-ce-cli
rm -rf /var/lib/containerd /var/lib/docker
```

## 6. 重启并确认清理结果

```bash
systemctl daemon-reload
systemctl restart containerd

systemctl is-active containerd
systemctl is-active kubelet 2>/dev/null || true
test ! -e /etc/kubernetes && echo 'kubernetes config cleaned'
test ! -e /etc/cni/net.d && echo 'cni config cleaned'
ip link show | egrep 'cni|flannel|cali|tunl|vxlan|kube-ipvs' || true
ipvsadm -Ln 2>/dev/null || true
iptables-save | egrep 'KUBE-|CALI-|FLANNEL-' || true
```

预期：containerd 为 `active`；kubelet 未安装或为 `inactive`；`/etc/kubernetes`、`/etc/cni/net.d` 不存在；没有残留 Flannel/Calico/Kubernetes 专用接口和规则。

## 7. 重新部署前的顺序

1. 把当前实验拓扑写入 `swr/config/cluster.env`。
2. 在有权限的 SWR 客户端手动完成登录，或填写 `SWR_AK` 和 `SWR_LOGIN_KEY`；不要把凭据提交到版本库。
3. 先执行 `deploy-all.sh --dry-run` 检查节点计划。
4. 执行一键部署或按 `swr/README.md` 分步部署。
5. private SWR 下，确认每个节点的 containerd 都能拉取 `pause:3.9` 后再执行 kubeadm init。
6. 单 master 实验只能验证部署流程，不能宣称已验证多 master etcd HA；多 master 需要使用奇数 master 列表再次执行 join 和验收。
