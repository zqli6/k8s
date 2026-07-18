# 1. 相关网站
1. 官方GitHub：https://github.com/kube-vip/kube-vip  
2. lzq部署k8s文档：[lzq文档-部署k8s](https://www.yuque.com/jianglai-iayzx/sa1zul/lxkwah6m1zw0h7vb#coJvj)  
2. lzq部署学习文档：[lzq文档-部署kube-vip](https://www.yuque.com/jianglai-iayzx/sa1zul/yew3qp30rggryvb5#WrCUK)  

# 2. 部署步骤
*部署kube-vip的节点：创建完第一个控制节点master后*  
## 2.1 部署准备  
在部署k8s时，控制平面需要`--control-plane-endpoint kubeapi.lzq.org`。  
以下面举例：
```
kubeadm init --kubernetes-version=v${K8S_RELEASE_VERSION} --control-plane-endpoint kubeapi.wang.org --pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12 --token-ttl=0 --image-repository registry.aliyuncs.com/google_containers --upload-certs --cri-socket=unix:///run/cri-dockerd.sock
```
1. 做域名解析至kube-vip  
> 如果部署前做了单节点域名解析，需取消之前的解析
```
echo "10.0.0.199 kubeapi.lzq.org" >> /etc/hosts
```
2. 指定vip、网卡及版本  
```
export VIP=10.0.0.199
export INTERFACE=eth0   # 确认网卡名（使用 ip a 查看）
export KVVERSION=v1.1.2
export IMAGE="swr.cn-southwest-2.myhuaweicloud.com/zqli/ghcr.io/kube-vip/kube-vip:${KVVERSION}"
```
## 3.1 runtime：containerd  
### 3.1.1 manifest  
```

```
### 3.1.2 daemonset  
```

```