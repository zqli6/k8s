# 相关网址  
1. nfs-subdir-external-provisioner GitHub 主页  
<https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner>  
# 创建 NFS 共享存储的 storageclass步骤如下：
01 至 04 为 nfs-subdir-external-provisioner 的部署及StorageClass的创建  
其他为pvc和pod的创建（05、06）
- 创建 NFS 共享  
  - 服务端：
  ```
  [root@master1 ~]# apt update && apt -y install nfs-server
  [root@master1 ~]# systemctl status nfs-server.service
  [root@master1 ~]# mkdir -pv /data/sc-nfs/
  [root@master1 ~]# vim /etc/exports
  # 授权 worker 节点的网段可以挂载
  # /data/sc-nfs *(rw,no_root_squash,all_squash,anonuid=0,anongid=0)
  /data/sc-nfs *(rw,no_root_squash)
  
  # 配置生效
  exportfs -rv
  ```
  - 客户端：安装nfs客户端挂载工具即可，不需要挂载nfs目录
  ```
  apt update && apt -y install nfs-common 或者 nfs-client
  ```
  - 共享文件名为：`sc-nfs` 
  - 若不一致需修改`03-nfs-client-provisioner_lzq.yaml`
  - `spec.template.spec.containers.env: /data/sc-nfs`  # NFS 共享目录
  - `spec.template.spec.volumes.path: /data/sc-nfs`  # NFS 共享目录
- 创建 Service Account 并授予管控NFS provisioner在k8s集群中运行的权限（rbac.yaml）  
  ```
  kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/01-namespace.yaml
  kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/02-rbac.yaml
  ```
- 部署 NFS-Subdir-External-Provisioner 对应的 Deployment（nfs-client-provisioner.yaml）  
  - 官方镜像：nfs-client-provisioner.yaml
  - SWR仓库镜像：nfs-client-provisioner_lzq.yaml
  ```
  kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/03-nfs-client-provisioner_lzq.yaml
  ```
- 创建 StorageClass 负责建立PVC并调用NFS provisioner进行预定的工作,并让PV与PVC建立联系（nfs-StorageClass.yaml） 
  ```
  kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/04-nfs-StorageClass.yaml
  ``` 
- 创建 PVC 时自动调用SC创建PV（pvc.yaml）  
- 创建Pod 使用 PVC（pod-test.yaml） 
# 实践：基于sc-nfs 实现MySQL的动态置备  
- 创建pvc、svc、pod
  -  storage-mysql-storage-class-pvc.yaml