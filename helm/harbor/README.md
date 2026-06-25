# 1. 安装NFS配置共享目录/data/sc-nfs
# 2. 部署StorageClass
   详见：[k8s/StorageClass/nfs-subdir-external-provisioner](https://gitee.com/zqli6/k8s/tree/main/StorageClass/nfs-subdir-external-provisioner)
# 3. 部署ingress
   详见：[k8s/ingress](https://gitee.com/zqli6/k8s/blob/main/ingress/README.md)
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
wget https://gitee.com/zqli6/k8s/raw/main/helm/harbor/harbor-values_lzq.yml
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

  # 9. Harbor v2.14.3 ARM64 镜像构建指南

  在服务器上从官方源码构建 Harbor v2.14.3 镜像。覆盖三种场景:

  - **场景 A**:arm64 机器 + nerdctl(无 Docker,如 K3s 节点)
  - **场景 B**:arm64 机器 + Docker
  - **场景 C**:x86 机器交叉构建 arm64 镜像(QEMU 模拟)

  > 背景:官方 Docker Hub 只提供 `goharbor/*:v2.14.3` 的 **amd64** 镜像,没有
  arm64;社区也没有这个精确补丁版本。但官方源码自带 arm64 构建能力(`ARCH` 按宿主机架构自动识别),需自行构建。
  >
  > **优先级**:原生 arm64 构建(场景 A/B)最稳;x86 交叉构建(场景 C)依赖 QEMU 模拟,慢且偶有兼容问题,仅在没有 arm64
  机器时使用。

  ---

  ## 前置要求

  | 依赖 | 说明 |
  |---|---|
  | 构建机 | arm64 原生(场景 A/B)或 x86_64(场景 C) |
  | 运行时 | nerdctl + BuildKit(场景 A) 或 Docker ≥ 20.10(场景 B/C) |
  | git / make / python3 | clone、构建驱动、`prepare` 阶段生成配置 |
  | 磁盘空间 | 构建峰值约 15~25 GB,建议预留 30 GB 以上 |

  环境自检:

  ```bash
  uname -m                 # arm64 机器应为 aarch64;x86 机器为 x86_64
  git --version && make --version && python3 --version
  df -h /                  # 确认磁盘余量

  # 场景 A 额外确认 buildkitd 在跑
  ps aux | grep buildkitd

  # 场景 B/C 额外确认 docker
  docker version
  docker buildx ls         # 场景 C 需要 buildx,输出里应能看到 linux/arm64
  ```

  ---

  ## 第 1 步:拉取源码(指定 v2.14.3)

  ```bash
  git clone -b v2.14.3 --single-branch --depth 1 https://github.com/goharbor/harbor.git
  cd harbor

  # GitHub 慢时改用 gitee 同步镜像(稍慢于 GitHub,但国内更稳)
  # git clone -b v2.14.3 --single-branch --depth 1 https://gitee.com/mirrors/harbor.git
  ```

  参数含义:

  | 参数 | 作用 |
  |---|---|
  | `-b v2.14.3` | 直接检出 `v2.14.3` 这个 tag(无需再单独 `git checkout`) |
  | `--single-branch` | 只拉取该 tag 对应的单条分支历史,不下载其他分支 |
  | `--depth 1` | 浅克隆,只取最新一次提交,不要完整历史,体积更小、速度更快 |

  > 浅克隆下 `git describe --tags` 可能不显示 tag,确认版本可看 `cat VERSION`。

  ---

  ## 第 2 步:生成配置文件

  `prepare` 阶段会读取此文件,缺失会报错。构建镜像不依赖其中 hostname/密码,保持默认即可。

  ```bash
  cp make/harbor.yml.tmpl make/harbor.yml
  ```

  ---

  ## 场景 A:arm64 + nerdctl(无 Docker)

  ### A-1 关键前置:创建 docker → nerdctl 包装器

  Harbor 的环境检查脚本 `make/checkenv.sh` **硬编码检查 `docker` 命令**,且要求版本 ≥ 20.10.10。它不认 `-e
  DOCKERCMD=nerdctl`(那个变量只作用于后续构建命令,管不到这个前置检查),没有 `docker` 命令会直接报:

  ```
  ✖ Need to install docker(20.10.10+) first and run this script again.
  make: *** [Makefile:350：check_environment] 错误 1
  ```

  解法:做一个包装器,`--version` 伪造一个高版本骗过检查,其余命令全部透传给 nerdctl。注意不能简单 `ln -s`——nerdctl 的
  `--version` 输出格式不同,版本号会被误判为过低。

  ```bash
  cat > /usr/local/bin/docker <<'EOF'
  #!/bin/bash
  # checkenv.sh 只看 `docker --version` 的版本号,这里伪造一个高版本通过检查
  if [ "$1" = "--version" ]; then
    echo "Docker version 25.0.0, build nerdctl-shim"
    exit 0
  fi
  # 其余全部透传给 nerdctl
  exec nerdctl "$@"
  EOF
  chmod +x /usr/local/bin/docker

  # 验证
  docker --version          # 应显示 Docker version 25.0.0, build nerdctl-shim
  docker images | head      # 应等同 nerdctl images

  # 确认 /usr/local/bin 在 PATH 中(一般默认在)
  echo $PATH | tr ':' '\n' | grep '/usr/local/bin'
  ```

  > 构建全部完成后如需移除包装器:`rm /usr/local/bin/docker`

  ### A-2 编译(Go + 前端 portal)

  用容器编译模式,宿主机无需安装 Go / Node。`go：未找到命令` 只是警告,会自动 fallback 到容器编译。

  ```bash
  make compile \
    -e COMPILETAG=compile_golangimage \
    -e PULL_BASE_FROM_DOCKERHUB=true
  ```

  ### A-3 构建镜像

  ```bash
  make build \
    -e COMPILETAG=compile_golangimage \
    -e VERSIONTAG=v2.14.3 \
    -e PULL_BASE_FROM_DOCKERHUB=true \
    -e BUILD_BASE=true \
    -e TRIVYFLAG=true \
    -e NOTARYFLAG=false \
    -e CHARTFLAG=false \
    -e GEN_TLS=true
  ```

  | 参数 | 作用 |
  |---|---|
  | `COMPILETAG=compile_golangimage` | 在 golang/node 容器内编译,宿主机零工具链依赖 |
  | `VERSIONTAG=v2.14.3` | 镜像 tag 设为 v2.14.3 |
  | `BUILD_BASE=true` | 构建 photon base 层 |
  | `PULL_BASE_FROM_DOCKERHUB=true` | 拉官方 base 镜像省时间;不稳可改 `false` 自建(更慢) |
  | `TRIVYFLAG=true` | 构建 trivy-adapter 扫描组件 |
  | `NOTARYFLAG=false` / `CHARTFLAG=false` | 不构建 notary / chartmuseum(按需) |
  | `GEN_TLS=true` | 生成 TLS 证书 |

  > 包装器已把 `docker` 指向 nerdctl,所以这里不必再传 `DOCKERCMD=nerdctl`(传了也无害)。

  ---

  ## 场景 B:arm64 + Docker

  和场景 A 一致,但**不需要包装器**(本机有真 docker),也不必传 `DOCKERCMD`。

  ### B-1 编译

  ```bash
  make compile \
    -e COMPILETAG=compile_golangimage \
    -e PULL_BASE_FROM_DOCKERHUB=true
  ```

  ### B-2 构建镜像

  ```bash
  make build \
    -e COMPILETAG=compile_golangimage \
    -e VERSIONTAG=v2.14.3 \
    -e PULL_BASE_FROM_DOCKERHUB=true \
    -e BUILD_BASE=true \
    -e TRIVYFLAG=true \
    -e NOTARYFLAG=false \
    -e CHARTFLAG=false \
    -e GEN_TLS=true
  ```

  > 若宿主机已装好匹配版本的 Go/Node,可去掉 `COMPILETAG=compile_golangimage` 走默认的
  `compile_normal`(用本机工具链,编译更快)。版本要求以源码 `go.mod` 为准。

  ---

  ## 场景 C:x86 机器交叉构建 arm64 镜像(QEMU 模拟)

  在 x86_64 机器上构建 arm64 镜像,核心是让 x86 内核能运行 arm64 指令——通过 **QEMU binfmt** 模拟,再让构建流程全程以 arm64
  架构运行。**比原生慢数倍,仅在无 arm64 机器时使用。**

  ### C-1 注册 QEMU binfmt(让内核识别 arm64 二进制)

  ```bash
  # 一次性注册多架构模拟支持(重启后需重新执行,除非做了持久化)
  docker run --privileged --rm tonistiigi/binfmt --install arm64

  # 验证 arm64 已注册
  docker run --privileged --rm tonistiigi/binfmt
  ```

  ### C-2 创建支持多架构的 buildx builder

  ```bash
  docker buildx create --name armbuilder --use --bootstrap
  docker buildx ls          # 确认 armbuilder 支持 linux/arm64
  ```

  ### C-3 进入 arm64 模拟环境再构建(推荐做法)

  Harbor 的 Makefile 默认按宿主机 `uname -m` 决定架构,x86 机器直接跑会产出 amd64。最可靠的做法是**先进入一个 arm64
  容器**(经 QEMU 模拟,内部 `uname -m` 报告 `aarch64`),在其中执行第 1~2 步和编译/构建,整套流程自然按 arm64 走:

  ```bash
  # 启动一个 arm64 的构建环境容器(挂载源码与运行时)
  docker run --privileged --platform linux/arm64 -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD":/workspace -w /workspace \
    arm64v8/golang:1.25 bash

  # 容器内确认架构为 aarch64,再执行第 1~2 步、随后按场景 B 的 compile/build 流程
  uname -m   # 期望 aarch64
  ```

  > 替代方案(buildx 多平台):对单个 Dockerfile 可用 `docker buildx build --platform linux/arm64 --load ...`,但 Harbor
  多组件 Makefile 不直接支持 `--platform` 透传,需逐组件改造,工作量大,不推荐。
  >
  > **务必先给 Docker 配国内镜像 mirror**,否则 QEMU 环境下拉 base 镜像会非常慢。

  ---

  ## 第 3 步(通用):查看构建产物

  ```bash
  # 场景 A
  nerdctl images | grep goharbor
  # 场景 B/C
  docker images | grep goharbor
  ```

  典型产物(以实际输出为准):

  ```
  goharbor/harbor-core            v2.14.3
  goharbor/harbor-jobservice      v2.14.3
  goharbor/harbor-portal          v2.14.3
  goharbor/harbor-db              v2.14.3
  goharbor/harbor-registryctl     v2.14.3
  goharbor/harbor-exporter        v2.14.3
  goharbor/registry-photon        v2.14.3
  goharbor/nginx-photon           v2.14.3
  goharbor/redis-photon           v2.14.3
  goharbor/trivy-adapter-photon   v2.14.3
  ```

  > 单架构构建产物为 **单 manifest(arm64)**,非多架构 index。可用 `nerdctl manifest inspect <镜像>` 或 `docker manifest
  inspect <镜像>` 确认 `mediaType`。

  ---

  ## 第 4 步(通用):推送到镜像仓库(SWR)

  > 场景 A 把 `docker` 换成 `nerdctl`(或直接用包装器,`docker` 已指向 nerdctl),其余相同。

  ```bash
  docker login swr.cn-southwest-2.myhuaweicloud.com

  # harbor- 前缀组件
  for name in core jobservice portal db registryctl exporter; do
    docker tag goharbor/harbor-${name}:v2.14.3 \
      swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-${name}:v2.14.3-arm
    docker push swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-${name}:v2.14.3-arm
  done

  # 无 harbor- 前缀组件
  for name in registry-photon nginx-photon redis-photon trivy-adapter-photon; do
    docker tag goharbor/${name}:v2.14.3 \
      swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
    docker push swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
  done
  ```

  ---

  ## 第 5 步(通用):清理构建缓存

  ```bash
  # 场景 A
  nerdctl builder prune -a && nerdctl image prune

  # 场景 B/C
  docker builder prune -a && docker image prune
  docker buildx prune -a        # 场景 C 额外清 buildx 缓存

  df -h /                       # 确认空间回收
  ```

  ---

  ## 常见问题

  - **`Need to install docker(20.10.10+)`**(场景 A):见 A-1,checkenv.sh 硬检查 `docker` 命令,用包装器解决。
  - **`go：未找到命令`**:仅警告,容器编译模式会自动 fallback,无需在宿主机装 Go。
  - **拉基础镜像超时**:为 BuildKit / containerd / Docker 配置国内 mirror,或将 `PULL_BASE_FROM_DOCKERHUB` 改为 `false`
  从源码自建 base。
  - **nerdctl 报 `unknown flag`**(场景 A):Makefile 个别 `docker run` 可能带 nerdctl 不支持的参数,按提示微调对应 flag。
  - **K3s 节点上 nerdctl 镜像看不到**:nerdctl 默认 `default` namespace,K3s 用 `k8s.io`,二者隔离。用 `nerdctl images`
  查看,而非 `crictl images`。
  - **构建出来是 amd64 而非 arm64**(场景 C):说明没跑在 arm64 模拟环境里,参考 C-3 先进入 arm64 容器再构建。

