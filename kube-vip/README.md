# 1. 相关网站
1. 官方GitHub：https://github.com/kube-vip/kube-vip  
2. lzq部署k8s文档[课件版-haproxy高可用]：[lzq文档-部署k8s-课件版-haproxy高可用](https://www.yuque.com/jianglai-iayzx/sa1zul/lxkwah6m1zw0h7vb#coJvj)  
3. lzq部署k8s文档[精简版-kube-vip高可用]：[lzq文档-部署k8s-精简版-kube-vip高可用](https://www.yuque.com/jianglai-iayzx/sa1zul/yew3qp30rggryvb5#t6X5K)  
4. lzq部署学习文档：[lzq文档-部署kube-vip](https://www.yuque.com/jianglai-iayzx/sa1zul/yew3qp30rggryvb5#WrCUK)  


# 2. 部署准备  
*部署kube-vip的节点：创建完第一个控制节点master后*  
在部署k8s时，控制平面需要`--control-plane-endpoint kubeapi.lzq.org`。  
以下面举例：
```
kubeadm init --kubernetes-version=v${K8S_RELEASE_VERSION} --control-plane-endpoint kubeapi.wang.org \
--pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12 --token-ttl=0 \   # 指定pod网段和svc网段
--image-repository registry.aliyuncs.com/google_containers \                   # 指定加速仓库
--upload-certs --cri-socket=unix:///run/cri-dockerd.sock                       # Docker作为运行时指定cri-docker
```
## 2.1 所有k8s节点做域名解析至kube-vip  
> 如果部署前做了单节点域名解析，需取更改为kube-vip解析
```
echo "10.0.0.199 kubeapi.lzq.org" >> /etc/hosts
```
## 2.2 指定vip、网卡及版本  
```
export VIP=10.0.0.199
export INTERFACE=eth0   # 确认网卡名（使用 ip a 查看）
export KVVERSION=v1.1.2
export IMAGE="swr.cn-southwest-2.myhuaweicloud.com/zqli/ghcr.io/kube-vip/kube-vip:${KVVERSION}"
```
# 3 部署kube-vip  
## 3.1 两种部署方式解析  
| 方式 | 原理 | 优势 | 劣势 | 适用场景 |
|------|------|------|------|----------|
| 静态 Pod（manifest） | kubelet 直接管理，/etc/kubernetes/manifests/ | 不依赖集群 API，Node 被删也不影响 | 每台 master 都要放，更新要手动改文件 | kube-vip 这种基础设施组件，特别是控制平面的 VIP、API server 本身 |
| DaemonSet | 走 Kubernetes 调度器，依赖 API 和 Node 对象 | 方便管理，kubectl 就能升级、回滚 | Node 没了就不调度，鸡生蛋蛋生鸡 | 业务组件、不涉及集群本身可用性的组件 |
 
## 3.2 containerd运行时  
### 3.2.1 manifest
3.2.1.1 生成静态 Pod 清单
```
ctr -n k8s.io run --rm --net-host $IMAGE vip \
  /kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --services \
  --arp \
  --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml
```
重启kubelet立即生效
```
systemctl restart kubelet
```
3.2.1.2 部署失败可选操作  
```
# 【可选】修正：手动补全 args 参数（确保选举触发）
sed -i '/- manager/!b;n;c\    - --controlplane\n    - --leaderElection' /etc/kubernetes/manifests/kube-vip.yaml

# 【可选】修正：修改监控端口防止冲突
sed -i 's/:2112/:2113/g' /etc/kubernetes/manifests/kube-vip.yaml
```
### 3.2.2 daemonset
3.2.2.1 部署权限 (RBAC)二选一
```
# lzq SWR仓库加速版
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/network/kube-vip/rbac.yaml
```
```
# 官方版
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml
```
3.2.2.2 生成 DaemonSet 配置  
```
ctr -n k8s.io run --rm --net-host "$IMAGE" vip /kube-vip manifest daemonset \
    --interface "$INTERFACE" \
    --address "$VIP" \
    --inCluster \
    --controlplane \
    --services \
    --arp \
    --leaderElection \
    --taint > kube-vip-ds.yaml
```
3.2.2.3 替换为SWR镜像加速,若不替换及使用官方镜像
```
sed -i "s|image: ghcr.io/kube-vip/kube-vip:.*|image: $IMAGE|g" kube-vip-ds.yaml
```

3.2.2.4 应用部署  
```
kubectl apply -f kube-vip-ds.yaml
```

3.2.2.5 部署失败可选操作  
```
# 【可选】修正 2：手动补全 Args（v1.1.2 必备，否则 Lease 不会生成）
sed -i '/- manager/a \        - --controlplane\n        - --leaderElection' kube-vip-ds.yaml

# 【可选】修正 3：修改监控端口防止 2112 冲突
sed -i 's/value: :2112/value: :2113/g' kube-vip-ds.yaml
```


## 3.3 Docker运行时  
### 3.3.1 manifest
```
docker run --network host --rm $IMAGE manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --services \
  --arp \
  --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml
```
### 3.3.2 daemonset
3.3.2.1 部署权限 (RBAC)二选一
```
# lzq SWR仓库加速版
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/network/kube-vip/rbac.yaml
```
```
# 官方版
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml
```

3.2.2.2 生成 DaemonSet 配置 
```
docker run --network host --rm $IMAGE manifest daemonset \
    --interface $INTERFACE \
    --address $VIP \
    --inCluster \
    --controlplane \
    --services \
    --arp \
    --leaderElection \
    --taint > kube-vip-ds.yaml
```

3.2.2.3 替换为SWR镜像加速,若不替换及使用官方镜像
```
sed -i "s|image: ghcr.io/kube-vip/kube-vip:.*|image: $IMAGE|g" kube-vip-ds.yaml
```

3.2.2.4 应用部署  
```
kubectl apply -f kube-vip-ds.yaml
```

3.2.2.5 部署失败可选操作  
```
# 【可选】修正 2：手动补全 Args（v1.1.2 必备，否则 Lease 不会生成）
sed -i '/- manager/a \        - --controlplane\n        - --leaderElection' kube-vip-ds.yaml

# 【可选】修正 3：修改监控端口防止 2112 冲突
sed -i 's/value: :2112/value: :2113/g' kube-vip-ds.yaml
```
