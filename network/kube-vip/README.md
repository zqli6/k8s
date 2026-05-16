## kube-vip部署说明  
[可查看LZQ文档](https://www.yuque.com/jianglai-iayzx/sa1zul/podq5g7kxggtzots#WrCUK)  

### Kube-vip v1.1.2 高可用部署手册

#### 基础环境变量定义
在执行任何操作前，请在所有控制节点（Master）统一设置以下变量。

```bash
# 确认网卡名（使用 ip a 查看）
export VIP=10.0.0.199
export INTERFACE=eth0
export KVVERSION=v1.1.2
export IMAGE="swr.cn-southwest-2.myhuaweicloud.com/zqli/ghcr.io/kube-vip/kube-vip:${KVVERSION}"
```

#### 部署方式：使用 containerd

##### DaemonSet 方式
适用于集群已建立后的部署，通过 Kubernetes 统一管理。只需在 **Master1** 执行。

```bash
# 部署权限 (RBAC)
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/network/kube-vip/rbac.yaml  

kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

# 生成 DaemonSet 配置
ctr -n k8s.io run --rm --net-host "$IMAGE" vip /kube-vip manifest daemonset \
    --interface "$INTERFACE" \
    --address "$VIP" \
    --inCluster \
    --controlplane \
    --services \
    --arp \
    --leaderElection \
    --taint > kube-vip-ds.yaml

# 修正 1：替换为私有镜像地址
sed -i "s|image: ghcr.io/kube-vip/kube-vip:.*|image: $IMAGE|g" kube-vip-ds.yaml

# 修正 2：手动补全 Args（v1.1.2 必备，否则 Lease 不会生成）
sed -i '/- manager/a \        - --controlplane\n        - --leaderElection' kube-vip-ds.yaml

# 修正 3：修改监控端口防止 2112 冲突
sed -i 's/value: :2112/value: :2113/g' kube-vip-ds.yaml

# 应用部署
kubectl apply -f kube-vip-ds.yaml
```

#### 部署方式：使用 Docker

##### DaemonSet 方式
只需在 **Master1** 执行。

```bash
docker run --network host --rm $IMAGE manifest daemonset \
    --interface $INTERFACE \
    --address $VIP \
    --inCluster \
    --controlplane \
    --services \
    --arp \
    --leaderElection \
    --taint > kube-vip-ds.yaml

# 修正 1：替换为私有镜像地址
sed -i "s|image: ghcr.io/kube-vip/kube-vip:.*|image: $IMAGE|g" kube-vip-ds.yaml

# 修正 2：手动补全 Args（v1.1.2 必备，否则 Lease 不会生成）
sed -i '/- manager/a \        - --controlplane\n        - --leaderElection' kube-vip-ds.yaml

# 修正 3：修改监控端口防止 2112 冲突
sed -i 's/value: :2112/value: :2113/g' kube-vip-ds.yaml

# 应用部署
kubectl apply -f kube-vip-ds.yaml
```

#### 核心验证步骤
部署完成后，请依次执行以下检查以确保高可用功能正常。



##### 检查选举锁状态
Kube-vip 依靠 Kubernetes 的 Lease 对象进行选主，只有抢到锁的节点才会挂载 VIP。
```bash
kubectl get lease -n kube-system plndr-cp-lock
```
**预期输出：** 能够看到 `HOLDER` 列显示了某一台 Master 的主机名，且 `AGE` 在正常跳动。

##### 检查 VIP 绑定情况
在 **HOLDER** 对应的节点上检查网卡。
```bash
ip a show $INTERFACE | grep $VIP
```
**预期输出：** 该网卡下会出现 `inet 10.0.0.199/32 ...` 的记录。注意：非 Holder 节点不应看到此 IP。

##### 验证二层 ARP 广播
从集群外或其他节点测试 VIP 的连通性及 MAC 地址响应。
```bash
# 检查是否能 Ping 通
ping -c 4 $VIP

# 检查 ARP 响应（推荐）
arping -I $INTERFACE -c 3 $VIP
```
**预期输出：** `arping` 应该能收到来自 Holder 节点物理网卡 MAC 地址的回复。

##### 检查实时日志逻辑
查看 Pod 是否进入了正确的选举与广播流程。
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip-ds --tail 20
```
**预期输出：** 日志中应包含 `Attempting to acquire leader lease` 和 `Node xxx is assuming leadership` 等关键信息。

#### 参数详解与排错指导

##### 核心参数说明
* `--interface`：指定绑定 VIP 的物理网卡。
* `--address`：指定的虚拟 IP (VIP)。
* `--controlplane`：启用控制平面高可用。
* `--leaderElection`：启动领导者选举，确保 VIP 唯一性。
* `--inCluster`：使 kube-vip 使用 ServiceAccount Token 访问集群 API。

##### 常见排错
* **Pod 状态为 Error**：使用 `kubectl describe` 查看，通常是因为 `args` 参数不被识别（检查拼写）或 2112 端口冲突。
* **VIP 无法 Ping 通**：检查物理网络是否允许 ARP 广播，或者 `INTERFACE` 变量是否与宿主机实际网卡名一致。