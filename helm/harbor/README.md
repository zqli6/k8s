# 1. 安装NFS配置共享目录/data/sc-nfs
# 2. 部署StorageClass
   详见：[k8s/StorageClass/nfs-subdir-external-provisioner](https://gitee.com/zqli6/k8s/tree/main/StorageClass/nfs-subdir-external-provisioner)
# 3. 部署ingress
   详见：[k8s/ingress](https://gitee.com/zqli6/k8s/blob/main/ingress/README.md)
# 4. 安装 helm
# 5. 安装harbor   
1. x86 SWR 镜像加速版
```
# 使用下载的chart包
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values-lzq.yml  \
&& wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz \
&& helm install myharbor -f harbor-values-lzq.yml harbor-1.18.3.tgz -n harbor --create-namespace
```
2. arm SWR 镜像加速版
```
# 使用下载的chart包
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values-arm-lzq.yml  \
&& wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz \
&& helm install myharbor -f harbor-values-arm-lzq.yml harbor-1.18.3.tgz -n harbor --create-namespace
```

3. 使用helm仓库
```
helm repo add harbor https://helm.goharbor.io
```
```
helm install myharbor -f harbor-values_lzq.yml harbor/harbor -n harbor --create-namespace
```

4. 官方
```
# 导出values.yaml定制参数
helm show values harbor/harbor > harbor-values.yaml
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
```

# 7. 在浏览器登录
## 证书导出  
```
# 列出所有 Secret，过滤出可能包含证书的项
kubectl get secrets -n harbor | grep -E "tls|cert"
myharbor-ingress                 kubernetes.io/tls    3      15m

[root@master1 ~ ]# kubectl get secret myharbor-ingress -n harbor -o jsonpath='{.data.ca\.crt}' | base64 --decode > ca.crt

[root@master1 ~ ]# ls
ca.crt

# 把证书传送到window电脑并信任
[root@master1 ~ ]# sz ca.crt
```  
## 浏览器登录
```
地址：ingress域名(lzq默认配置harbor.lzq.com)，注意配置域名解析
账号(admin)/密码(lzq12345)
```
# 8. docker/containerd/linux信任harbor  
## 1. 配置 Docker 使用 CA 证书
```
# 导出 Harbor 的 CA 根证书
kubectl get secrets -n harbor | grep -E "tls|cert"
myharbor-ingress                 kubernetes.io/tls    3      15m
# 从 Kubernetes Secret 导出（以 harbor-tls 为例，请根据实际 Secret 名称调整）
kubectl get secret myharbor-ingress -n harbor -o jsonpath='{.data.ca\.crt}' | base64 --decode > ca.crt

# 创建 Docker 证书目录并放入证书
#Docker 会为每个 registry 域名读取 /etc/docker/certs.d/<域名>/ca.crt 作为信任锚。
# 创建域名专属目录
mkdir -p /etc/docker/certs.d/harbor.lzq.com

# 将 CA 证书复制进去（必须命名为 ca.crt）
cp ca.crt /etc/docker/certs.d/harbor.lzq.com/ca.crt

# 重启 Docker 服务并登录
systemctl restart docker

# 再次尝试登录（建议使用 --password-stdin 避免警告）
echo "lzq12345" | docker login -u admin --password-stdin harbor.lzq.com
```

## 2. 备选方案：将证书添加到系统 CA 信任库（影响所有应用）  
此方法会让整个操作系统信任该 CA，适用于其他需要 TLS 验证的场景（如 curl、wget）。
```
# 导出 Harbor 的 CA 根证书
kubectl get secrets -n harbor | grep -E "tls|cert"
myharbor-ingress                 kubernetes.io/tls    3      15m
# 从 Kubernetes Secret 导出（以 harbor-tls 为例，请根据实际 Secret 名称调整）
kubectl get secret myharbor-ingress -n harbor -o jsonpath='{.data.ca\.crt}' | base64 --decode > ca.crt

# 将私有CA的证书加入到每个docker主机的上信任证书CA列表中，在所有Harbor客户端执行

# Ubuntu系统
# 方法1
$ cat /data/harbor/certs/ca.crt >> /etc/ssl/certs/ca-certificates.crt
$ systemctl restart docker.service

# 方法2
$ cp /data/harbor/certs/ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
$ update-ca-certificates
$ systemctl restart docker.service


# 红帽系统
# 方法1
cat /data/harbor/certs/ca.crt >> /etc/pki/tls/certs/ca-bundle.crt

# 方法2
cp /data/harbor/certs/ca.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust

# 将上面的文件复制到所有docker主机覆盖原文件
# 并将所有docker主机的docker服务重启生效
systemctl restart docker.service
```

## 3. 不推荐的临时方案：配置 insecure-registries
```
# 修改 /etc/docker/daemon.json，添加：
json
{
  "insecure-registries": ["harbor.lzq.com"]
}
```
然后 systemctl restart docker。此方式会完全跳过 TLS 验证，存在中间人攻击风险，仅建议在测试环境临时使用。  