# 相关资料
1. MetalLB GitHub  
https://github.com/metallb/metallb
2. metalLB官网安装教程  
<https://metallb.io/installation/>
3. lizhiquan的文档  
<https://www.yuque.com/jianglai-iayzx/sa1zul/lvzgvfv7kv1x2055#CvoOD>  


#  部署metalLB 
## 1. To deploy metalLB with yaml  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/metallb-native-v0.14.9-lzq.yaml
```

## 2. **metallb-IPAddressPool应用**  
MetalLB 的 Layer2 模式本质是让 K8s 节点“冒充”外部设备，    
所以 VIP（IPAddressPool） 必须在同一物理网段且未被网关或其他设备占用。  
本yaml的addresses为`10.0.0.10-10.0.0.50`，请根据实际修改。  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/IPAddressPool.yaml
```

## 3. 部署L2或BGP模式

**L2（ARP广播）** 是在局域网里喊“IP是我的”，让同网段的机器知道；  
**BGP（路由协议）** 是直接告诉上层路由器“IP在我这”，让路由器帮你把跨网段甚至外网的流量都转过来。

### 3.1. metallb-L2Advertisement应用  
配置注释了限制网卡，可以指定为你的网卡名
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/L2Advertisement.yaml
```

### 3.2. metalLB-BGP应用
GBPPeer中定义了：

```
#物理路由器配置：
# 路由器自己的 AS 号是 65001
bgp 65001

# 路由器设置对等体：对方 IP 是 K8s 节点 (比如 192.168.1.10)，对方的 AS 号是 65000
peer 192.168.1.10 as-number 65000
```

| 字段 | 谁决定 | 怎么获取 |
|------|--------|---------|
| `peerAddress` | 路由器 IP | 固定的，问管理员 |
| `peerASN` | 路由器的 AS 号 | 固定的，问管理员 |
| `myASN` | 管理员在路由器上**允许**的 AS 号 | 问管理员给你分配了什么号 |

```
# 需修改peerAddress、peerASN、myASN
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/BGPPeer.yaml
```
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/BGPAdvertisement.yaml
```


# **开启 kube-proxy 的 strictARP**【推荐】  
  在 strictARP: false 的情况下，MetalLB 的 L2 模式可能会出现 ARP 响应延迟或不响应（尤其是使用 IPVS 模式时）。  
  * 查看Kube-Proxy 的 StrictARP 模式
    ```
    kubectl get configmap -n kube-system kube-proxy -o yaml | grep strictARP
    ```
  * 如果结果是 strictARP: false，请立即执行：
    ```
    kubectl get configmap kube-proxy -n kube-system -o yaml | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
    ```
    然后重启 kube-proxy 确保生效
    ```
    kubectl rollout restart daemonset kube-proxy -n kube-system
    ```
# 问题排错
1.failed to call webhook  
```
# 环境描述：k8s集群宕机，集群恢复后，MetalLB 的 validating webhook 配置仍然存在于 etcd 中，但其 webhook 服务的 TLS 或 CA 信息与当前运行实例不一致，导致 kube-apiserver 调用 webhook 超时。通过删除 validatingwebhookconfiguration 临时绕过校验，恢复资源创建。

[root@GitLab ~ ]# kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-IPAddressPool.yaml
Error from server (InternalError): error when creating "https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-IPAddressPool.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": context deadline exceeded

[root@GitLab ~ ]# kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-L2Advertisement.yaml
Error from server (InternalError): error when creating "https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-L2Advertisement.yaml": Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": context deadline exceeded

# 排查服务是否启动
[root@GitLab ~ ]# kubectl get pod -n metallb-system
NAME                          READY   STATUS    RESTARTS   AGE
controller-7b4d87475f-qrxbc   1/1     Running   0          77s
controller-7b4d87475f-vw96q   1/1     Running   0          77s
speaker-jp8kh                 1/1     Running   0          77s
speaker-pfcsf                 1/1     Running   0          77s
speaker-q8nwm                 1/1     Running   0          77s
speaker-rh2gm                 1/1     Running   0          77s
speaker-tdqh9                 1/1     Running   0          77s
speaker-xqwnv                 1/1     Running   0          77s

[root@GitLab ~ ]# kubectl get secret -n metallb-system
NAME                   TYPE     DATA   AGE
memberlist             Opaque   1      77s
metallb-webhook-cert   Opaque   4      80s


[root@GitLab ~ ]# kubectl get svc -n metallb-system
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
metallb-webhook-service   ClusterIP   10.100.182.48   <none>        443/TCP   3m30s

[root@GitLab ~ ]# kubectl get endpoints -n metallb-system metallb-webhook-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                              AGE
metallb-webhook-service   192.168.188.5:9443,192.168.29.4:9443   3m37s

# 都没有问题，直接绕过
# webhook TLS/服务异常导致 apiserver 调不通
# webhook 服务“能连上 TCP”，但 HTTPS 校验/处理失败  
# 
[root@GitLab ~ ]# kubectl delete validatingwebhookconfiguration metallb-webhook-configuration
validatingwebhookconfiguration.admissionregistration.k8s.io "metallb-webhook-configuration" deleted

[root@GitLab ~ ]# kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-L2Advertisement.yaml
l2advertisement.metallb.io/localip-pool-l2a created

[root@GitLab ~ ]# kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/metalLB/service-metallb-IPAddressPool.yaml
ipaddresspool.metallb.io/localip-pool created
```

    
