# 1. 安装NFS配置共享目录/data/sc-nfs
# 2. 部署StorageClass
   详见：[k8s/StorageClass/nfs-subdir-external-provisioner](https://gitee.com/zqli6/k8s/tree/main/StorageClass/nfs-subdir-external-provisioner)
# 3. 部署ingress
   详见：[k8s/ingress](https://gitee.com/zqli6/k8s/blob/main/ingress/README.md)
# 4. 安装 helm  
  详见  [lzq相关文档](https://www.yuque.com/jianglai-iayzx/sa1zul/vpmelt03h9qzq32c#wD49m)
# 5. 安装harbor   
## 5.1. lzq SWR 镜像加速版
### 1. x86 nfs
- 配置pvc容量：registry 200Gi；database 5Gi；jobservice 2Gi;redis 2Gi;trivy 10Gi
```
# 使用下载的chart包
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz \
&& helm install myharbor -f https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values-lzq.yml \
harbor-1.18.3.tgz -n harbor --create-namespace
```
### 2. arm nfs
- 配置pvc容量：registry 200Gi；database 5Gi；jobservice 2Gi;redis 2Gi;trivy 10Gi
```
# 使用下载的chart包
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz \
&& helm install myharbor -f https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values-arm-lzq.yml \
harbor-1.18.3.tgz -n harbor --create-namespace
```
### 3. arm topoLVM  
- 需先安装`topoLVM`，[详见zqli6/k8s/StorageClass/topolvm](https://gitee.com/zqli6/k8s/tree/main/StorageClass/topolvm)  
- 配置pvc容量：registry 200Gi；database 5Gi；jobservice 2Gi;redis 2Gi;trivy 10Gi
- 对于topoLVM，申请即占用，vg，lv大小不足会报错
```
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-1.18.3.tgz \
&& helm install myharbor -f https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values-topolvm-arm-lzq.yml \
harbor-1.18.3.tgz -n harbor --create-namespace
```

### 4. 使用helm仓库
```
helm repo add harbor https://helm.goharbor.io
```
```
helm install myharbor -f harbor-values_lzq.yml harbor/harbor -n harbor --create-namespace
```

## 5.2 官方仓库安装
```
# 导出values.yaml定制参数
helm show values harbor/harbor > harbor-values.yaml
```
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

# 9. 备份和还原
- 以Harbor NFS → TopoLVM 迁移为例  

## 9.1、背景说明

Harbor DB 使用 NFS 存储，PostgreSQL 在 NFS 上高并发写入时 fsync 超时，
导致 PG 子进程 SIGPIPE 崩溃，Harbor 认证失败，镜像推送报 401。
迁移至 TopoLVM（基于 LVM，数据存于本地 NVMe）彻底解决该问题。

### 需要备份的组件

| 组件 | 是否备份 | 原因 |
|------|---------|------|
| database | ✅ 必须 | 用户/项目/镜像元数据/系统配置 |
| registry | ✅ 必须 | 镜像实际 layer 数据 |
| jobservice | ❌ 不需要 | 任务日志，丢了无影响 |
| redis | ❌ 不需要 | 缓存，重启自动重建 |
| trivy | ❌ 不需要 | 漏洞库，自动更新 |

---

## 9.2、备份
### 9.2.1 设置备份目录

```bash
BACKUP_DIR=/home/lzq/harbor/backup
DATE=$(date +%Y%m%d%H%M)
mkdir -p ${BACKUP_DIR}
```

### 9.2.2 备份 DB

```bash
kubectl exec -n harbor myharbor-database-0 -- pg_dumpall -U postgres \
  > ${BACKUP_DIR}/harbor-db-backup-${DATE}.sql
echo "DB备份完成: $(wc -l < ${BACKUP_DIR}/harbor-db-backup-${DATE}.sql) 行"
```

校验关键表是否有数据（`pg_dumpall` 默认输出是 `COPY ... FROM stdin;` 格式而非 `INSERT INTO`，需同时匹配两种格式；`role_permission`/`permission_policy` 是现代 Harbor 版本的遗留空表，权限判断已改为读取代码内硬编码的 `PoliciesMap`，不依赖这两张表，所以不纳入校验）：

```bash
for TABLE in harbor_user project role; do
    COUNT=$(grep -E -c "INSERT INTO public.${TABLE} |COPY public.${TABLE} " ${BACKUP_DIR}/harbor-db-backup-${DATE}.sql)
    echo "  表 ${TABLE}: ${COUNT} 处匹配（INSERT 或 COPY 起始行）"
    if [ "$COUNT" -eq 0 ]; then
        echo "  警告: ${TABLE} 没有数据，备份可能不完整，请先排查源库再继续！"
    fi
done

echo "=== 校验数据行数（更准确） ==="
for TABLE in harbor_user project role; do
    LINES=$(sed -n "/^COPY public.${TABLE} /,/^\\\\.\$/p" ${BACKUP_DIR}/harbor-db-backup-${DATE}.sql | wc -l)
    echo "  表 ${TABLE}: 约 $((LINES - 2)) 行数据"
done
```

### 9.2.3 备份 registry layer

registry layer数据目录结构：

```bash
kubectl exec -n harbor harbor-registry-7b96dd8cf8-25xnq -c registry -- tree /storage/
/storage
└── docker
    └── registry
        └── v2
            ├── blobs
            │   └── sha256
            │       ├── 00
            │       ├── ...
            │       └── fb                 # 此处省略了大量中间哈希前缀目录
            └── repositories
                └── ict                    # 项目/命名空间
```

从 registry 容器拷贝出来（注意：拷贝耗时较久，必须等命令彻底返回到命令提示符后才能做下面的校验，否则数字是中途的过渡值）：

```bash
REGISTRY_POD=$(kubectl get pod -n harbor | grep registry | awk '{print $1}')

kubectl cp -n harbor ${REGISTRY_POD}:/storage/docker \
  ${BACKUP_DIR}/harbor-registry-backup/docker -c registry
```

校验备份内容：

```bash
echo "=== 校验 registry 备份内容 ==="
echo "Repository 数量: $(find ${BACKUP_DIR}/harbor-registry-backup/docker/registry/v2/repositories -maxdepth 2 -mindepth 2 -type d 2>/dev/null | wc -l)"
echo "Blob 数量: $(find ${BACKUP_DIR}/harbor-registry-backup/docker/registry/v2/blobs -name "data" 2>/dev/null | wc -l)"
```

### 9.3 旧应用停机

```bash
kubectl scale deployment -n harbor --all --replicas=0
kubectl scale statefulset -n harbor --all --replicas=0
kubectl get pod -n harbor
# 预期输出: No resources found in harbor namespace.

kubectl delete pvc -n harbor --all
kubectl get pvc -n harbor
# 预期输出: No resources found in harbor namespace.

helm uninstall myharbor -n harbor
```

> 这一步会卸载整个 release，9.4 重新 helm install 时所有组件（包括 portal）会一并拉起，不存在漏启动风险。

### 9.4 新应用开机

```bash
sed -i 's/storageClass: "nfs-client"/storageClass: "topolvm-provisioner"/g' \
  /home/lzq/harbor/harbor-values-topolvm-arm-lzq.yml

grep "storageClass" /home/lzq/harbor/harbor-values-topolvm-arm-lzq.yml | grep -v "#"

helm install myharbor /home/lzq/harbor/harbor-1.18.3.tgz \
  -n harbor \
  -f /home/lzq/harbor/harbor-values-topolvm-arm-lzq.yml \
  --wait --timeout 10m

kubectl get pod -n harbor
```

### 9.5 还原

#### 9.5.1 还原 DB

```bash
kubectl scale deployment -n harbor --all --replicas=0
kubectl scale statefulset -n harbor myharbor-trivy --replicas=0
kubectl get pod -n harbor
```

> 注意：上面这条 `--all --replicas=0` 会把 **myharbor-core / myharbor-jobservice / myharbor-portal / myharbor-registry** 全部停掉。
> 后面恢复时必须把这四个全部重新拉起来，少一个都会导致访问异常（例如漏了 portal 会导致 UI 报 "no available server"）。

```bash
kubectl exec -n harbor myharbor-database-0 -- psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'registry' AND pid <> pg_backend_pid();
"

kubectl exec -n harbor myharbor-database-0 -- psql -U postgres -c "DROP DATABASE registry;"
kubectl exec -n harbor myharbor-database-0 -- psql -U postgres -c "CREATE DATABASE registry OWNER postgres;"

kubectl exec -i -n harbor myharbor-database-0 -- psql -U postgres \
  < ${BACKUP_DIR}/harbor-db-backup-${DATE}.sql
```

> 还原过程中可能会看到 `ERROR: role "postgres" already exists` 和 `ERROR: database "registry" already exists`，
> 这是因为备份文件本身包含了重建角色/数据库的语句，而这两个对象已经存在（前两条命令刚建过）。
> 这类报错不会中断导入，后续的 `CREATE TABLE`/`COPY`/`CREATE INDEX` 等仍会继续执行，属于预期噪音，不代表失败。

启动 core / jobservice / registry / **portal**（四个一起，缺一个都会出问题）/ trivy：

```bash
kubectl scale deployment -n harbor myharbor-core myharbor-jobservice myharbor-registry myharbor-portal --replicas=1
kubectl scale statefulset -n harbor myharbor-trivy --replicas=1
kubectl get pod -n harbor -w
```

等所有 pod 变为 Running 且无持续重启后 Ctrl+C 退出，再执行还原后校验（不再校验 `permission_policy`/`role_permission`，这两张表为遗留空表，权限判断不依赖它们）：

```bash
echo "=== 还原后校验 ==="
kubectl exec -it -n harbor myharbor-database-0 -- psql -U postgres -d registry -c "SELECT count(*) FROM project;"
kubectl exec -it -n harbor myharbor-database-0 -- psql -U postgres -d registry -c "SELECT count(*) FROM harbor_user;"
# 上面两个数字都不应该是 0，且应与备份时记录的预期数量一致，确认无误后才继续 9.5.2
```

#### 9.5.2 还原 registry layer

```bash
REGISTRY_POD=$(kubectl get pod -n harbor -l component=registry \
  -o jsonpath='{.items[0].metadata.name}')
echo $REGISTRY_POD
```

> 如果输出为空，说明 myharbor-registry 还没起来，先执行
> `kubectl scale deployment -n harbor myharbor-registry --replicas=1`
> 等它 Running 后再重新执行上面这条获取 pod 名的命令。

```bash
kubectl cp ${BACKUP_DIR}/harbor-registry-backup/docker \
  harbor/${REGISTRY_POD}:/storage/docker -c registry

kubectl exec -n harbor ${REGISTRY_POD} -c registry -- ls /storage/
# 预期输出: docker
```

如果数据落在了错误路径，先确认实际路径再移动（按 `ls /storage/` 实际看到的路径调整，不要直接套用固定命令）：

```bash
kubectl exec -n harbor ${REGISTRY_POD} -c registry -- mv /storage/<错误路径>/docker /storage/
kubectl exec -n harbor ${REGISTRY_POD} -c registry -- rm -rf /storage/<错误路径>
```

还原后校验 repository 数量是否与备份时记录的一致：

```bash
echo "=== registry layer 还原后校验 ==="
kubectl exec -n harbor ${REGISTRY_POD} -c registry -- \
  find /storage/docker/registry/v2/repositories -maxdepth 2 -mindepth 2 -type d | wc -l
# 与 9.2.3 备份时记录的 repository 数量对比，确认一致
```

#### 9.5.3 收尾确认

```bash
kubectl get pod -n harbor
```

> 此时应能看到 myharbor-core / myharbor-database-0 / myharbor-jobservice /
> myharbor-portal / myharbor-redis-0 / myharbor-registry / myharbor-trivy-0
> 共 7 个组件全部 Running，缺任何一个都需要单独 `scale --replicas=1` 补上。

```bash
kubectl get ingress -n harbor
kubectl get svc -n harbor
kubectl get endpoints -n harbor
```

---

## 9.6、验证

## 9.6.1 登录 Harbor UI 确认项目和镜像存在  
> 登录域名查看ingress  
这个域名是在[6. 文档中的配置](https://gitee.com/zqli6/k8s/tree/main/helm/harbor?svcp_stk=1_Qy3IgpgHpCe5KsHgIcVbYyQv7YPBIXxgCYfhXYcibGOo3IdlnnphuV5jnPQriJHtc0BK4L01tOz0M6A2lIt1k6akDc1UAxmGDu9L8O3LSJyqUeDzYD_psMRjqVyl7LShPCoHWIPr6VtU786i9JUaYblUE74I9pIWdxlCoNihlozrnqDTSqipGxLVlN7JPk6r5lFSs-AzixaohzoJa231Dw%3D%3D#6-%E6%96%87%E6%A1%A3%E4%B8%AD%E7%9A%84%E9%85%8D%E7%BD%AE)中讲解了  
注意配置`tls`需使用`https://ingress域名`访问，否则可能会提示用户名或密码错误  
```
kubectl get ingress -n harbor
```
> 账号：`admin`  
密码在values.yaml中配置`harborAdminPassword: "你的密码"`  
也可以使用下方命令查看
```
kubectl get secret -n harbor myharbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d; echo
```
```bash
# 最终验证，挑 1-2 个镜像实际 push/pull 一次，确认整条链路（DB + registry + 权限）都正常：
nerdctl pull <harbor域名>/ict/<某个repo>:<tag>

# 确认 DB 不再崩溃
kubectl logs -n harbor myharbor-database-0 --tail=20 | grep -i "error\|fatal\|crash"
```

## 9.7 常见问题  
### 9.7.1 用 http 访问，登录报 403 Forbidden / "CSRF token invalid"  

  现象：密码确认无误（API 直连返回 200），但浏览器登录返回 403，或提示 CSRF token invalid。  

  原因：Harbor 的 CSRF cookie（_gorilla_csrf）带 Secure 属性，在纯 http 下浏览器不会回传该 cookie，导致请求头里的 CSRF token 与 cookie 永远配不上，稳定 403。  

  解决：必须用 https + ingress 里配置的域名访问，不能用 http、也不能用 IP 直接访问。  

  确认 ingress 域名：  
```
kubectl get ingress -n harbor
```
> 用 HOSTS 列里的域名，以 https 访问，例如：  
https://ict-harbor-pro-registry-huabei2.crs.ctyun.cn  
若本机无 DNS 解析，在本机 hosts 文件加一行：<ingress的ADDRESS> <HOSTS域名>  
首次访问提示证书不安全（自签证书），点"高级 → 继续访问"即可。  

### 9.7.2 已用 https，仍偶发 "CSRF token invalid"  

  现象：已经换成 https，之前能登录，再次登录时报 CSRF token invalid。  

  原因：CSRF token 有时效，且与会话 cookie 绑定。登录页停留过久导致 token 过期，或之前用 http 访问时残留的旧 cookie（_gorilla_csrf / sid）与当前 https 的新 cookie 混在一起，提交时带了失效 token。  

  解决（按顺序，通常第1步即可）：  

 > 1. 在登录页按 Ctrl+Shift+R 强制刷新，刷新后立即输入账号密码登录，不要停留太久。  
 >  2. 若仍报错，清掉该站点残留 cookie：F12 → Application → Cookies → 选中该域名 → 全部删除，然后 Ctrl+Shift+R 重新加载再登录。  
 >  3. 最彻底：关闭该站点所有标签页，开一个全新无痕窗口，直接访问 https 域名，首次加载即登录。  


