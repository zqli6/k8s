# k8s官网关于 StatefulSet 的说明  
<https://kubernetes.io/zh-cn/docs/tasks/run-application/run-replicated-stateful-application/>  
# 本文档使用说明  
1. 准备NFS服务共享目录  
2. 使用前先创建 StorageClass 或 手动创建PV、PVC  
StorageClass的创建方法见：/k8s/StorageClass/nfs-subdir-external-provisioner/{01-04}  
3. 创建ConfigMap
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StatefulSet/01-mysql-configmap.yaml
```
4. 创建Service  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StatefulSet/02-mysql-services.yaml
```
5. 创建StatefulSet  
   1. SWR 加速镜像  
   ```
   kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StatefulSet/03-mysql-statefulset_lzq.yaml
   ```
   2. 
   ```
   kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StatefulSet/03-mysql-statefulset.yaml
   ```
# 测试
```
kubectl run -it test-$RANDOM --rm --image swr.cn-southwest-2.myhuaweicloud.com/zqli/ubuntu:22.04-apt --command -- bash

root@test-23524:/# host mysql-0.mysql.default.svc.cluster.local
mysql-0.mysql.default.svc.cluster.local has address 10.244.1.68

# 无头服务
root@test-23524:/# host mysql.default.svc.cluster.local
mysql.default.svc.cluster.local has address 10.244.6.37
mysql.default.svc.cluster.local has address 10.244.1.68
mysql.default.svc.cluster.local has address 10.244.2.82

mysql -h mysql-read -e "show variables" | grep -i hostname
root@test-23524:/# mysql -h mysql-read -e "show variables" | grep -i hostname
hostname	mysql-2
root@test-23524:/# mysql -h mysql-read -e "show variables" | grep -i hostname
hostname	mysql-0
root@test-23524:/# mysql -h mysql-read -e "show variables" | grep -i hostname
hostname	mysql-1
```
