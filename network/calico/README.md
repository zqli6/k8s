# 相关网页
1. 官网  
<https://www.tigera.io/project-calico/>  
2. 安装要求  
<https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements>  
3. 安装文档  
<https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart#step-1-create-a-cluster> 
4. 安装calicoctl  
**注意：calicoctl的版本需与插件版本一致**
<https://docs.tigera.io/calico/latest/operations/calicoctl/install>

# 部署  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/network/calico/calico_lzq.yaml
```

# 五种模式
1. BGP
```
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 修改：
#   ipipMode: Never
#   vxlanMode: Never
```
2. IPIP
```
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 修改：
#   ipipMode: Always
#   vxlanMode: Never
```
3. IPIP with BGP
```
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 例如：同网段用BGP，跨网段用IPIP
#   ipipMode: CrossSubnet
#   vxlanMode: Never
```
4. vxlan
```
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 修改：
#   ipipMode: Never
#   vxlanMode: Always
```
5. vxlan with BGP
```
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 例如：同网段用BGP，跨网段用IPIP
#   ipipMode: Never
#   vxlanMode: CrossSubnet
```
6. 修改方法
```
# 修改方法
# 方法1：直接编辑IPPool
[root@master1 ~]# kubectl edit ippools.crd.projectcalico.org default-ipv4-ippool
# 修改：
#   ipipMode: Never
#   vxlanMode: Never

# 方法2：通过配置文件
[root@master1 ~]# kubectl get ippools default-ipv4-ippool -o yaml > default-ipv4-ippool.yaml
# 编辑后 apply

# 重启calico-node Pod
[root@master1 ~]# kubectl delete pod -n kube-system -l k8s-app=calico-node
# 
[root@master1 ~]# kubectl rollout history -n kube-system ds calico-node
```  
# calicoctl 工具管理 BGP 网络
1. 使用文档  
[LZQ学习文档](https://www.yuque.com/jianglai-iayzx/sa1zul/aiua0xf8umfv717v)

