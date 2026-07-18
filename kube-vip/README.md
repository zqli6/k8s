# 1. 相关网站
1. 官方GitHub：https://github.com/kube-vip/kube-vip  
2. lzq部署k8s文档：[lzq文档-部署k8s](https://www.yuque.com/jianglai-iayzx/sa1zul/lxkwah6m1zw0h7vb#coJvj)  
2. lzq部署学习文档：[lzq文档-部署kube-vip](https://www.yuque.com/jianglai-iayzx/sa1zul/yew3qp30rggryvb5#WrCUK)  


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
## 2.1 做域名解析至kube-vip  
> 如果部署前做了单节点域名解析，需取消之前的解析
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
```

```
### 3.2.1 daemonset
```
```
## 3.3 Docker运行时  
### 3.3.1 manifest
```

```
### 3.3.1 daemonset
```
```
