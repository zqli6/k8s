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

  # 9. Harbor v2.14.3 ARM64 镜像构建指南(国内 / 纯 nerdctl 实战版)

  在 arm64 服务器上从官方源码构建 Harbor v2.14.3 镜像。本文以**只有 nerdctl + containerd + BuildKit、无
  Docker、且在国内网络**(如 K3s 节点)的环境为主线(场景 A),并附 arm64+Docker(场景 B)、x86 交叉构建(场景 C)。

  > 背景:官方 Docker Hub 只提供 `goharbor/*:v2.14.3` 的 **amd64** 镜像,无 arm64;社区也无此精确补丁版本。官方源码自带
  arm64 构建能力(`ARCH` 按宿主机自动识别),需自行构建。
  >
  > **本文所有补丁/加速命令均经实测跑通**(arm64 + nerdctl v2.3.3 + containerd v2.2.3-k3s1 + buildkitd v0.31.0)。

  ---

  ## 前置要求

  | 依赖 | 说明 |
  |---|---|
  | arm64 机器 | `uname -m` = `aarch64`,原生构建 |
  | nerdctl + buildkitd | `nerdctl build` 依赖 buildkitd 运行 |
  | git / make / python3 | clone、构建驱动、prepare 阶段 |
  | 磁盘 | 构建峰值 15~25 GB,建议预留 30 GB+ |

  自检:

  ```bash
  uname -m                 # aarch64
  ps aux | grep buildkitd  # buildkitd 在跑
  git --version && make --version && python3 --version
  df -h /
  ```

  ---

  ## 第 1 步:拉取源码(指定 v2.14.3)

  ```bash
  git clone -b v2.14.3 --single-branch --depth 1 https://github.com/goharbor/harbor.git
  cd harbor
  # GitHub 慢时用 gitee 镜像:
  # git clone -b v2.14.3 --single-branch --depth 1 https://gitee.com/mirrors/harbor.git
  ```

  | 参数 | 作用 |
  |---|---|
  | `-b v2.14.3` | 直接检出 v2.14.3 tag |
  | `--single-branch` | 只拉该分支历史 |
  | `--depth 1` | 浅克隆,只取最新提交,更快更小 |

  > 浅克隆下 `git describe` 可能不显示 tag,确认版本看 `cat VERSION`。

  ---

  ## 第 2 步:生成配置文件

  ```bash
  cp make/harbor.yml.tmpl make/harbor.yml
  ```

  prepare 阶段会读它,缺失会报错;构建镜像不依赖其内容,保持默认即可。

  ---

  ## 第 3 步:创建 docker → nerdctl 包装器(场景 A 核心)

  纯 nerdctl 环境有三个连环坑,用一个包装器一次性解决:

  1. `make/checkenv.sh` **硬检查 `docker` 命令**(版本 ≥ 20.10.10),无 docker 直接报 `Need to install
  docker(20.10.10+)`;
  2. 构建中多处 `docker run` 临时工具容器(lint、证书生成、Go 编译),纯 nerdctl 默认 bridge 网络缺 CNI 插件,报 `needs
  CNI plugin "bridge" ... /opt/cni/bin/bridge: no such file`;
  3. 核心组件用 `docker run golang go build` 编译,容器内 `go` 走默认代理拉 module 会超时(`proxy.golang.org ... i/o
  timeout`)。

  包装器:`--version` 伪造高版本过检查;`run` 注入 `--network host` 绕 CNI、注入 `GOPROXY/GOSUMDB`
  走国内代理;其余透传。(不能用 `ln -s`,nerdctl 的 `--version` 格式会被误判版本过低。)

  ```bash
  cat > /usr/local/bin/docker <<'EOF'
  #!/bin/bash
  # checkenv.sh 只看 `docker --version` 的版本号,伪造高版本通过检查
  if [ "$1" = "--version" ]; then
    echo "Docker version 25.0.0, build nerdctl-shim"
    exit 0
  fi
  # docker run 注入:
  #   --network host        绕开 nerdctl 默认 bridge(缺 CNI 插件)
  #   GOPROXY/GOSUMDB        容器内 go build/install 走国内代理,避免超时
  if [ "$1" = "run" ]; then
    shift
    exec nerdctl run --network host \
      -e GOPROXY=https://goproxy.cn,direct \
      -e GOSUMDB=off \
      "$@"
  fi
  exec nerdctl "$@"
  EOF
  chmod +x /usr/local/bin/docker

  # 验证
  docker --version          # Docker version 25.0.0, build nerdctl-shim
  docker images | head      # 等同 nerdctl images
  echo $PATH | tr ':' '\n' | grep '/usr/local/bin'   # 确认在 PATH
  ```

  > 这些 `docker run` 都是用完即删的临时容器,共享主机网络无副作用。
  > 全部构建完成后如需移除:`rm /usr/local/bin/docker`

  ---

  ## 第 4 步:国内网络加速(三类下载,必做)

  国内直连 github / proxy.golang.org / DockerHub / google 基本都超时。分三类处理。

  ### 4.1 github 下载加速(Dockerfile 内的下载)

  构建中 spectral 等组件的 Dockerfile 会从 `github.com` 下二进制,直连报 `curl: (52) Empty reply` 或 `(28) timed
  out`。

  先测最快镜像(可用性随时变,实测为准):

  ```bash
  URL="https://github.com/stoplightio/spectral/releases/download/v6.14.2/spectral-linux-arm64"
  for m in "https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/" \
           "https://gh.llkk.cc/" "https://github.moeyy.xyz/" "https://gitproxy.click/" ; do
    echo "==== $m ===="
    curl -fsSL --connect-timeout 8 --max-time 60 -o /tmp/sp_test \
      -w "  状态:%{http_code} 大小:%{size_download} 耗时:%{time_total}s 速度:%{speed_download}B/s\n" \
      "${m}${URL}" 2>&1 || echo "  ✗ 失败"
    rm -f /tmp/sp_test
  done
  ```

  选 `状态:200`、`大小` 约 7400 万字节、`速度` 最高的。(实测 `gh.llkk.cc` ≈5MB/s、`gh-proxy.com` ≈4.9MB/s
  较稳;直连超时。)

  把所有 Dockerfile 里的 `https://github.com` 统一加前缀(幂等):

  ```bash
  FAST="https://gh.llkk.cc/"        # 换成你测最快的
  grep -rln "https://github.com" --include="Dockerfile*" make tools   # 预览
  grep -rl "https://github.com" --include="Dockerfile*" make tools | while read f; do
    sed -i "s#https://github.com#${FAST}https://github.com#g" "$f"
    sed -i "s#${FAST}${FAST}#${FAST}#g" "$f"
  done
  grep -rn "github.com" --include="Dockerfile*" make tools            # 复核
  ```

  > 只匹配带 `https://` 的下载 URL;Go import 路径(`github.com/...` 无协议头)不会被误伤。

  ### 4.2 GOPROXY 注入(Dockerfile 内的 go 命令)

  部分组件 Dockerfile 直接跑 `go install` / `go build`(swagger、mockery、trivy-adapter、exporter),需各自加 GOPROXY。

  ```bash
  # swagger / mockery:在 RUN go install 前插入 ENV GOPROXY
  for f in tools/swagger/Dockerfile tools/mockery/Dockerfile; do
    grep -q 'GOPROXY' "$f" || sed -i '/^RUN go install/i ENV GOPROXY=https://goproxy.cn,direct' "$f"
  done

  # trivy-adapter:在 export 行追加 GOPROXY + GOSUMDB
  sed -i 's|GO111MODULE=on CGO_ENABLED=0|GO111MODULE=on CGO_ENABLED=0 GOPROXY=https://goproxy.cn,direct
  GOSUMDB=off|' \
    make/photon/trivy-adapter/Dockerfile.binary
  ```

  ### 4.3 修复 exporter 写死的架构 + 加 GOPROXY(arm64 关键)

  `make/photon/exporter/Dockerfile` **写死了 `ENV GOARCH=amd64`**,在 arm64 上会交叉编译出 amd64 二进制,导致 exporter
  容器 `exec format error` 起不来。必须改成 arm64。

  ```bash
  sed -i 's#ENV GOARCH=amd64#ENV GOARCH=arm64#' make/photon/exporter/Dockerfile
  sed -i '/^ENV GOOS=linux/a ENV GOPROXY=https://goproxy.cn,direct\nENV GOSUMDB=off' \
    make/photon/exporter/Dockerfile
  ```

  复核三处补丁:

  ```bash
  grep -n "GOPROXY\|go install" tools/swagger/Dockerfile tools/mockery/Dockerfile
  grep -n "GOPROXY\|GOOS" make/photon/trivy-adapter/Dockerfile.binary
  grep -n "GOARCH\|GOPROXY\|GOSUMDB\|GOOS" make/photon/exporter/Dockerfile   # GOARCH 应为 arm64
  ```

  ### 4.4 预拉 golang 镜像到 containerd(compile_core 必做)

  核心组件用 `docker run golang go build` 编译 → 经包装器走 `nerdctl run`,它用 **containerd 镜像存储,与 buildkit
  构建缓存相互独立**,会去 DockerHub 直连拉 golang 并超时(`registry-1.docker.io ... i/o timeout`)。

  用国内 DockerHub mirror 预拉,再重命名为 Makefile 期望的裸名(版本见 Makefile `GOBUILDIMAGE=`,v2.14.3 为
  `golang:1.24.13`):

  ```bash
  # 测可用 mirror
  for m in docker.m.daocloud.io dockerproxy.net docker.1ms.run hub.rat.dev docker.1panel.live ; do
    echo "==== $m ===="
    timeout 25 nerdctl pull ${m}/library/golang:1.24.13 && echo "✅ $m" && break || echo "✗ $m"
  done

  # 用成功的 mirror 重命名(实测 docker.m.daocloud.io 可用)
  MIRROR=docker.m.daocloud.io
  nerdctl tag ${MIRROR}/library/golang:1.24.13 golang:1.24.13
  nerdctl tag ${MIRROR}/library/golang:1.24.13 docker.io/library/golang:1.24.13
  nerdctl images | grep golang
  ```

  ---

  ## 第 5 步:编译(Go + 前端 portal)

  容器编译模式,宿主机无需 Go/Node(`go：未找到命令` 仅警告,会自动 fallback 到容器编译)。

  ```bash
  make compile \
    -e COMPILETAG=compile_golangimage \
    -e PULL_BASE_FROM_DOCKERHUB=true
  ```

  过程会:lint_apis(spectral)→ gen_apis(swagger 生成 API 代码)→ compile_core/jobservice/registryctl(容器内 Go 编译)。

  > `make compile` 输出大量 swagger lint warning(如 `295 problems (0 errors, 295 warnings)`)是**正常**的——Harbor
  官方 API 定义自带的风格提示,只要 **`0 errors`** 即通过。

  **验证编译成功**:

  ```bash
  echo "退出码: $?"                          # 0 = 成功
  ls -lh make/photon/core/harbor_core        # 二进制已生成(约 70M)
  file make/photon/core/harbor_core          # 应含 ARM aarch64(确认非 amd64)
  ```

  ---

  ## 第 6 步:构建镜像

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
  | `VERSIONTAG=v2.14.3` | 镜像 tag |
  | `BUILD_BASE=true` | 构建 photon base 层 |
  | `TRIVYFLAG=true` | 构建 trivy-adapter 扫描组件 |
  | `NOTARYFLAG=false` / `CHARTFLAG=false` | 不构建 notary / chartmuseum |
  | `GEN_TLS=true` | 生成 TLS 证书 |

  ### ⚠️ 已知后续坑:build 阶段从 github/google 下载的 make 变量

  build 会用 `-e` 传入若干**外部下载地址**(不在 Dockerfile 里,4.1 的 sed 覆盖不到),国内大概率超时:

  ```
  TRIVY_DOWNLOAD_URL          = https://github.com/aquasecurity/trivy/.../trivy_0.69.3_Linux-64bit.tar.gz
  TRIVY_ADAPTER_DOWNLOAD_URL  = https://github.com/goharbor/harbor-scanner-trivy/.../v0.35.1.tar.gz
  DISTRIBUTION_SRC            = https://github.com/goharbor/distribution.git
  REGISTRYURL                 = https://storage.googleapis.com/harbor-builds/.../registry   (google,基本不通)
  ```

  若卡在这些,用 `-e` 覆盖成加速地址重跑 build(github 加前缀,google 的 registry 需另找镜像或自建)。例如:

  ```bash
  make build \
    -e COMPILETAG=compile_golangimage -e VERSIONTAG=v2.14.3 \
    -e PULL_BASE_FROM_DOCKERHUB=true -e BUILD_BASE=true \
    -e TRIVYFLAG=true -e NOTARYFLAG=false -e CHARTFLAG=false -e GEN_TLS=true \
    -e TRIVY_DOWNLOAD_URL=https://gh.llkk.cc/https://github.com/aquasecurity/trivy/releases/download/v0.69.3/trivy_0
  .69.3_Linux-ARM64.tar.gz \
    -e TRIVY_ADAPTER_DOWNLOAD_URL=https://gh.llkk.cc/https://github.com/goharbor/harbor-scanner-trivy/archive/refs/t
  ags/v0.35.1.tar.gz \
    -e DISTRIBUTION_SRC=https://gh.llkk.cc/https://github.com/goharbor/distribution.git
  ```

  > **注意 trivy 架构**:默认 `TRIVY_DOWNLOAD_URL` 是 `Linux-64bit`(amd64)。arm64 须改用 `Linux-ARM64`
  包(如上),否则装进去的是 x86 trivy,扫描时 `exec format error`。具体文件名以 [trivy
  releases](https://github.com/aquasecurity/trivy/releases) 为准。
  > base 镜像(photon、各 `harbor-*-base`)超时时,同 4.4 用 `docker.m.daocloud.io` 预拉再 tag 成裸名。

  ---

  ## 第 7 步:查看产物

  ```bash
  nerdctl images | grep goharbor
  ```

  典型产物(以实际为准):

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

  > 单架构构建产物为 **单 manifest(arm64)**,非多架构 index。可用 `nerdctl manifest inspect <镜像>` 看 `mediaType`
  确认。

  ---

  ## 第 8 步:推送到镜像仓库(SWR)

  ```bash
  nerdctl login swr.cn-southwest-2.myhuaweicloud.com

  # harbor- 前缀组件
  for name in core jobservice portal db registryctl exporter; do
    nerdctl tag goharbor/harbor-${name}:v2.14.3 \
      swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-${name}:v2.14.3-arm
    nerdctl push swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-${name}:v2.14.3-arm
  done

  # 无 harbor- 前缀组件
  for name in registry-photon nginx-photon redis-photon trivy-adapter-photon; do
    nerdctl tag goharbor/${name}:v2.14.3 \
      swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
    nerdctl push swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
  done
  ```

  ---

  ## 第 9 步:清理构建缓存

  ```bash
  nerdctl builder prune -a && nerdctl image prune
  df -h /
  ```

  ---

  ## 场景 B:arm64 + Docker

  与场景 A 一致,但**无需第 3 步包装器**、无需第 4 步的包装器注入(本机有真 docker);github / GOPROXY / mirror
  加速在国内仍建议做(4.1~4.4 的 Dockerfile 补丁、exporter 架构修复同样适用)。命令去掉 `DOCKERCMD`
  相关即可。若宿主机已装好匹配版本 Go/Node,可去掉 `COMPILETAG=compile_golangimage` 走更快的本机 `compile_normal`。

  ## 场景 C:x86 交叉构建 arm64(QEMU,慢,仅无 arm64 机器时用)

  ```bash
  docker run --privileged --rm tonistiigi/binfmt --install arm64   # 注册 QEMU(重启失效)
  docker run --privileged --rm tonistiigi/binfmt                   # 验证 arm64 已注册
  ```

  Harbor Makefile 按宿主机 `uname -m` 定架构,x86 直接跑会产出 amd64。最可靠做法:**先进入 arm64 容器**(QEMU 模拟,内部
  `uname -m`=aarch64),在其中执行第 1~6 步:

  ```bash
  docker run --privileged --platform linux/arm64 -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD":/workspace -w /workspace arm64v8/golang:1.24 bash
  uname -m   # 期望 aarch64
  ```

  > 务必先给 Docker 配国内 mirror,否则 QEMU 下拉镜像极慢。

  ---

  ## 常见问题速查

  | 报错 | 原因 / 解决 |
  |---|---|
  | `Need to install docker(20.10.10+)` | checkenv.sh 硬查 docker;见第 3 步包装器 |
  | `go：未找到命令` | 仅警告,容器编译模式自动 fallback,无需装 Go |
  | `needs CNI plugin "bridge" ... /opt/cni/bin/bridge` | nerdctl 默认 bridge 缺 CNI;包装器对 run 注入 `--network
  host` 解决 |
  | `curl: (52) Empty reply` / `(28) timed out`(spectral 等) | github 直连超时;见 4.1 加速 |
  | `proxy.golang.org ... i/o timeout`(go install) | GOPROXY 未注入;见 4.2 / 包装器 GOPROXY |
  | `registry-1.docker.io ... i/o timeout`(compile_core) | nerdctl run 的 containerd 存储无 golang;见 4.4 预拉重命名
  |
  | swagger lint `0 errors, NNN warnings` | 正常,官方 API 定义风格提示,无需处理 |
  | exporter 容器 `exec format error` | Dockerfile 写死 `GOARCH=amd64`;见 4.3 改 arm64 |
  | build 阶段 trivy/distribution/registry 下载超时 | 这些是 make `-e` 变量;见第 6 步用 `-e` 覆盖为加速地址 |
  | trivy `exec format error` | `TRIVY_DOWNLOAD_URL` 默认 amd64;改用 `Linux-ARM64` 包 |
  | K3s 节点 `nerdctl images` 看不到集群镜像 | nerdctl 默认 `default` namespace,K3s 用 `k8s.io`,二者隔离,正常 |

  ---

  ## 关键认知小结

  - **buildkit 构建缓存 ≠ containerd 镜像存储**:`docker build` 走 buildkit,`docker run` 走 containerd,两套独立。所以
  `nerdctl run` 用的 golang 镜像要单独预拉(4.4)。
  - **三类下载源**:Dockerfile 内 `github.com`(4.1)、Dockerfile 内 `go install`(4.2)、make `-e` 传入的外部 URL(第 6
  步)——加速手段各不同,别漏。
  - **arm64 架构陷阱**:exporter 的 `GOARCH=amd64`(4.3)和 trivy 的 `Linux-64bit`(第 6 步)是两处写死 amd64
  的地方,arm64 必须改,否则镜像能构建但运行时 `exec format error`。