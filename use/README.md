# 污点
## 1.节点污点查看
```
kubectl get nodes -o custom-columns=NODE:.metadata.name,TAINTS:.spec.taints
```
## 2.污点去除
```
kubectl taint nodes <节点名称> <key>-
```
示例
```
# 去除指定的污点（在 key 后面加 -）
kubectl taint nodes k8smaster1 node-role.kubernetes.io/control-plane-

# 去除带值的污点，需要指定完整 key
kubectl taint nodes k8smaster1 disktype-

# 去除带多个属性的污点
kubectl taint nodes k8smaster1 key1-
```
## 3.污点设置
```
kubectl taint nodes <节点名称> <key>=<value>:<效果>
```
示例
```
# 增加一个 NoSchedule 污点
kubectl taint nodes k8smaster1 node-role.kubernetes.io/control-plane=:NoSchedule

# 增加带值的污点
kubectl taint nodes k8smaster1 disktype=ssd:NoSchedule

# 增加 PreferNoSchedule 污点
kubectl taint nodes k8smaster1 key1=value1:PreferNoSchedule

# 增加 NoExecute 污点
kubectl taint nodes k8smaster1 key2=value2:NoExecute
```



