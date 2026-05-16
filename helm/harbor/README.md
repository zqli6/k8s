# 1. 安装NFS配置共享目录/data/sc-nfs
# 2. 部署StorageClass
   详见：k8s/StorageClass/nfs-subdir-external-provisioner
# 3. 部署ingress
   详见：k8s/ingress
# 4. 安装 helm
# 5. 安装harbor
1. 添加harbor helm仓库 或者 直接使用文件harbor-1.18.3.tgz
```
helm repo add harbor https://helm.goharbor.io
```
```
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz
```
2. wget 下载yaml文件  
   1. SWR 镜像加速版
```
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor-values_lzq.yml
```  
```
helm install myharbor -f harbor-values_lzq.yml harbor/harbor -n harbor --create-namespace
或
helm install myharbor -f harbor-values_lzq.yml harbor-1.18.3.tgz -n harbor --create-namespace
```
   2. 官方  
```
helm install myharbor -f harbor-values.yml harbor/harbor -n harbor --create-namespace
```
# 6. 文档中的配置  
```
expose:
  type: ingress
  tls:
    enabled: true  
    certSource: auto
  ingress:
    hosts:
      core: harbor.lzq.com     # 指定 harbor 访问的域名
      notary: notary.wang.org   # 公证人，用于 Docker image 签名和认证，开发者在发布镜像后使用 Notary 进行签名，并发布签名信息。运维团队在拉取镜像时使用 Notary 来验证镜像的签名，确保其没有被篡改
    controller: default
    className: "nginx"                      # 新版用法，添加此行，指定 ingress
    annotations: 
      kubernetes.io/ingress.class: "nginx"  # 添加此行，指定 ingress，旧版使用

ipFamily:
  ipv4:
    enabled: true
  ipv6:
    enabled: false

externalURL: https://harbor.lzq.com   # 指定 harbor 访问的域名，和前面域名要一致

# 持久化存储配置部分，如果设置 storageclass 是默认值，下面可不修改
persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:                # 定义 Harbor 各个组件的 PVC 持久卷
    registry:                           # registry 组件（持久卷）
      storageClass: "sc-nfs"            # 前面创建的 StorageClass，其它组件同样配置，如果设置默认 storageClass，可以不用配置
      accessMode: ReadWriteMany         # 卷的访问模式，需要修改为 ReadWriteMany
      size: 5Gi
    chartmuseum:                        # chartmuseum 组件（持久卷）
      storageClass: "sc-nfs"
      accessMode: ReadWriteMany
      size: 5Gi
    jobservice:
      jobLog:
        storageClass: "sc-nfs"          # 如果设置默认 storageClass，可以不用配置
        accessMode: ReadWriteOnce
        size: 1Gi
      scanDataExports:
        storageClass: "sc-nfs"
        accessMode: ReadWriteOnce
        size: 1Gi
    database:                           # PostgreSQl 数据库组件
      storageClass: "sc-nfs"            # 如果设置默认 storageClass，可以不用配置
      accessMode: ReadWriteMany
      size: 2Gi
    redis:                              # Redis 缓存组件
      storageClass: "sc-nfs"            # 如果设置默认 storageClass，可以不用配置
      accessMode: ReadWriteMany
      size: 2Gi
    trivy:                              # Trity 漏洞扫描
      storageClass: "sc-nfs"            # 如果设置默认 storageClass，可以不用配置
      accessMode: ReadWriteMany
      size: 1Gi

harborAdminPassword: "lzq12345"
``` 
# 6. 查看相关信息  
```
# 查看ingress
[root@master1 ~ ]# kubectl get ingress -n harbor 
NAME               CLASS   HOSTS            ADDRESS               PORTS     AGE
myharbor-ingress   nginx   harbor.lzq.com   10.0.0.10,10.0.0.99   80, 443   87m

# 查看pod运行状态
[root@master1 ~ ]# kubectl get pod -n harbor 
NAME                                   READY   STATUS    RESTARTS   AGE
myharbor-core-6dfd7d749d-h2b85         1/1     Running   0          67m
myharbor-database-0                    1/1     Running   0          92m
myharbor-jobservice-78d9977bf8-8ndmr   1/1     Running   0          67m
myharbor-portal-84b4f54dfd-rtb6c       1/1     Running   0          92m
myharbor-redis-0                       1/1     Running   0          92m
myharbor-registry-94988f7f7-d68l2      2/2     Running   0          92m
myharbor-trivy-0                       1/1     Running   0          92m


# 查看svc信息
[root@master1 ~ ]# kubectl get svc -n harbor 
NAME                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
myharbor-core         ClusterIP   10.101.249.223   <none>        80/TCP              92m
myharbor-database     ClusterIP   10.107.241.208   <none>        5432/TCP            92m
myharbor-jobservice   ClusterIP   10.111.58.244    <none>        80/TCP              92m
myharbor-portal       ClusterIP   10.104.21.35     <none>        80/TCP              92m
myharbor-redis        ClusterIP   10.108.153.137   <none>        6379/TCP            92m
myharbor-registry     ClusterIP   10.96.110.5      <none>        5000/TCP,8080/TCP   92m
myharbor-trivy        ClusterIP   10.111.2.244     <none>        8080/TCP            92m

# 在浏览器登录  
地址：ingress域名，注意配置域名解析
账号(admin)/密码(lzq12345)

```
