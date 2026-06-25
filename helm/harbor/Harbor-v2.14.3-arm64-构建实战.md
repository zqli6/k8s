# Harbor v2.14.3 ARM64 镜像构建实战（nerdctl / 国内网络）

> 在 **arm64 服务器 + 纯 nerdctl（无 Docker）+ K3s 内置 containerd + 国内网络** 环境下，从官方源码构建 Harbor **v2.14.3** 全部 arm64 镜像并推送到华为云 SWR。
>
> 本文所有命令、补丁均为**真实跑通**记录（环境：arm64 / nerdctl v2.3.3 / containerd v2.2.3-k3s1 / buildkitd v0.31.0 / 磁盘余量 150G+）。

---

## 0. 背景与结论

- 官方 Docker Hub 只提供 `goharbor/*:v2.14.3` 的 **amd64** 镜像，**没有 arm64**；社区也没有这个精确补丁版本。
- Harbor 官方源码（v2.14.3 tag）已自带 arm64 构建能力（`ARCH` 按宿主机自动识别），所以"原材料具备、成品没人做"——只能自己构建。
- 最终产出 **12 个 arm64 镜像**（Helm 部署实际用 10 个，`prepare`/`harbor-log` 为副产物）。

### 关键认知（贯穿全文）

| 认知 | 说明 |
|---|---|
| **buildkit 缓存 ≠ containerd 镜像存储** | `docker build` 走 buildkit，`docker run/create` 走 containerd，两套**独立**。所以 `nerdctl run` 用的镜像要单独预拉。 |
| **三类下载源，加速手段不同** | ① Dockerfile 内 `github.com` 下载；② Dockerfile 内 `go install/go build`；③ Makefile 用 `-e` 传入的外部 URL。 |
| **两处写死 amd64** | `exporter` 的 `GOARCH=amd64`、`trivy` 的 `Linux-64bit` 包——arm64 必须改，否则镜像能构建但运行时 `exec format error`。 |
| **buildkit 走了 DockerHub mirror** | buildkitd 配了 `docker.m.daocloud.io` 作 mirror，解析 base tag 时会拉 mirror 上的 amd64，导致 redis 反复失败——这是最隐蔽的坑。 |

---

## 1. 前置要求

| 依赖 | 要求 |
|---|---|
| 架构 | arm64（`uname -m` = `aarch64`），原生构建 |
| 运行时 | nerdctl + buildkitd（buildkitd 必须在运行） |
| 工具 | git、make、python3 |
| 磁盘 | 构建峰值 15~25 GB，建议预留 30 GB+ |

环境自检：

```bash
uname -m                      # aarch64
ps aux | grep buildkitd       # buildkitd 在跑
git --version && make --version && python3 --version
df -h /                       # 确认余量
```

---

## 2. 拉取源码（指定 v2.14.3）

```bash
git clone -b v2.14.3 --single-branch --depth 1 https://github.com/goharbor/harbor.git
cd harbor
# GitHub 慢时用 gitee 镜像：
# git clone -b v2.14.3 --single-branch --depth 1 https://gitee.com/mirrors/harbor.git
```

| 参数 | 作用 |
|---|---|
| `-b v2.14.3` | 直接检出 v2.14.3 tag |
| `--single-branch` | 只拉该分支历史 |
| `--depth 1` | 浅克隆，只取最新提交，更快更小 |

> 浅克隆下 `git describe` 可能不显示 tag，确认版本用 `cat VERSION`。

生成配置文件（`prepare` 阶段会读，缺失会报错；构建不依赖其内容，保持默认）：

```bash
cp make/harbor.yml.tmpl make/harbor.yml
```

---

## 3. 创建 docker → nerdctl 包装器（核心）

纯 nerdctl 环境有**三个连环坑**，用一个包装器一次性解决：

1. `make/checkenv.sh` **硬编码检查 `docker` 命令**（版本 ≥ 20.10.10），不认 `-e DOCKERCMD=nerdctl`，无 docker 直接报 `Need to install docker(20.10.10+)`。
2. 构建中多处 `docker run` / `docker create` 临时容器（lint、证书、Go 编译、拷贝二进制），纯 nerdctl 默认 bridge 网络缺 CNI 插件，报 `needs CNI plugin "bridge"`。
3. 核心组件 `docker run golang go build`，容器内 go 走默认代理拉 module 超时（`proxy.golang.org ... i/o timeout`）。

包装器：`--version` 伪造高版本过检查；`run`/`create` 注入 `--network host` 绕 CNI + 注入 GOPROXY；其余透传。**不能用 `ln -s`**（nerdctl 的 `--version` 格式不同会被误判版本过低）。

```bash
cat > /usr/local/bin/docker <<'EOF'
#!/bin/bash
# checkenv.sh 只看 `docker --version` 的版本号，伪造高版本通过检查
if [ "$1" = "--version" ]; then
  echo "Docker version 25.0.0, build nerdctl-shim"
  exit 0
fi
# run 和 create 都注入 --network host（绕 CNI）+ GOPROXY（go 编译走国内）
if [ "$1" = "run" ] || [ "$1" = "create" ]; then
  sub="$1"; shift
  exec nerdctl "$sub" --network host \
    -e GOPROXY=https://goproxy.cn,direct \
    -e GOSUMDB=off \
    "$@"
fi
exec nerdctl "$@"
EOF
chmod +x /usr/local/bin/docker

docker --version          # 应显示 Docker version 25.0.0, build nerdctl-shim
docker images | head      # 应等同 nerdctl images
```

> 全部构建完成后如需移除：`rm /usr/local/bin/docker`

---

## 4. 安装 CNI bridge 插件（arm64）

`docker run/create` 默认 bridge 网络需要 CNI `bridge` 插件。纯 nerdctl/精简环境缺它，报：

```
needs CNI plugin "bridge" to be installed in CNI_PATH ("/opt/cni/bin") ... no such file
```

装 arm64 版 CNI 插件（K3s 节点的 `/opt/cni/bin` 是共享目录，装这里正合适）：

```bash
mkdir -p /opt/cni/bin
cd /tmp
curl -fsSL -o cni.tgz "https://gh.llkk.cc/https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-arm64-v1.5.1.tgz"
tar -xzf cni.tgz -C /opt/cni/bin
ls /opt/cni/bin/          # 应有 bridge、host-local、loopback、portmap 等
cd /home/lzq/harbor/harbor
```

> 包装器的 `--network host` 已能绕过大部分场景，但 registry 的 `builder` 脚本里用了 `docker create`（拷贝二进制），那一步靠 CNI 插件兜底，所以两者都要做。

---

## 5. 国内网络加速（三类下载，必做）

### 5.1 github 下载加速（Dockerfile 内的下载 URL）

spectral 等组件 Dockerfile 从 github 下二进制，直连报 `curl: (52) Empty reply` / `(28) timed out`。

**测速选最快镜像**（可用性随时间变化，实测为准）：

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

判读：选 `状态:200`、`大小`≈7400 万字节、`速度`最高者。
> 实测：`gh.llkk.cc`≈5MB/s、`gh-proxy.com`≈4.9MB/s 较稳；直连超时。本文用 `gh.llkk.cc`。

**批量给所有 Dockerfile 的 `https://github.com` 加前缀**（幂等，重复跑不叠加）：

```bash
FAST="https://gh.llkk.cc/"
grep -rln "https://github.com" --include="Dockerfile*" make tools          # 预览
grep -rl "https://github.com" --include="Dockerfile*" make tools | while read f; do
  sed -i "s#https://github.com#${FAST}https://github.com#g" "$f"
  sed -i "s#${FAST}${FAST}#${FAST}#g" "$f"
done
grep -rn "github.com" --include="Dockerfile*" make tools                   # 复核
```

> 只匹配带 `https://` 的下载 URL；Go import 路径（`github.com/...` 无协议头）不会被误伤。

### 5.2 GOPROXY 注入（Dockerfile 内的 go 命令）

部分组件 Dockerfile 直接 `go install` / `go build`（swagger、mockery、trivy-adapter），各自加 GOPROXY：

```bash
# swagger / mockery：RUN go install 前插入 ENV GOPROXY
for f in tools/swagger/Dockerfile tools/mockery/Dockerfile; do
  grep -q 'GOPROXY' "$f" || sed -i '/^RUN go install/i ENV GOPROXY=https://goproxy.cn,direct' "$f"
done

# trivy-adapter：export 行追加 GOPROXY + GOSUMDB
sed -i 's|GO111MODULE=on CGO_ENABLED=0|GO111MODULE=on CGO_ENABLED=0 GOPROXY=https://goproxy.cn,direct GOSUMDB=off|' \
  make/photon/trivy-adapter/Dockerfile.binary
```

### 5.3 修复 exporter 写死的架构 + 加 GOPROXY（arm64 关键）

`make/photon/exporter/Dockerfile` **写死 `ENV GOARCH=amd64`**，arm64 上会交叉编译出 amd64 二进制，导致 exporter 容器 `exec format error`。必须改：

```bash
sed -i 's#ENV GOARCH=amd64#ENV GOARCH=arm64#' make/photon/exporter/Dockerfile
sed -i '/^ENV GOOS=linux/a ENV GOPROXY=https://goproxy.cn,direct\nENV GOSUMDB=off' \
  make/photon/exporter/Dockerfile
```

复核三处补丁：

```bash
grep -n "GOPROXY\|go install" tools/swagger/Dockerfile tools/mockery/Dockerfile
grep -n "GOPROXY\|GOOS" make/photon/trivy-adapter/Dockerfile.binary
grep -n "GOARCH\|GOPROXY\|GOSUMDB" make/photon/exporter/Dockerfile   # GOARCH 须为 arm64
```

### 5.4 修复 registry 源码编译（Go 版本 + 工具链校验）

registry 走源码编译（goharbor/distribution），其 `go.mod` 要求 **Go ≥ 1.25**，但 Harbor 编译镜像是 `golang:1.24.13`，报：

```
go: go.mod requires go >= 1.25.0 (running go 1.24.13; GOTOOLCHAIN=local)
```

修法：让容器内 go 自动下载 1.25 工具链，并用国内可达的校验源（`GOSUMDB=off` 反而会挡住工具链下载，必须用 `sum.golang.google.cn`）：

```bash
sed -i '/^ENV GO111MODULE auto/a ENV GOTOOLCHAIN=auto\nENV GOPROXY=https://goproxy.cn,direct\nENV GOSUMDB=sum.golang.google.cn' \
  make/photon/registry/Dockerfile.binary

cat make/photon/registry/Dockerfile.binary   # 复核
```

预期含：
```dockerfile
ENV GOTOOLCHAIN=auto                   # 允许自动下载 go1.25
ENV GOPROXY=https://goproxy.cn,direct
ENV GOSUMDB=sum.golang.google.cn       # 国内可达的校验源（不能用 off）
```

### 5.5 （可选）去掉 --no-cache 加速反复重跑

Harbor `make/photon/Makefile` 第 21 行写死 `--no-cache`，每次 build 都重跑所有层（portal 单组件 7~8 分钟）。**首次无所谓，反复重跑强烈建议去掉**：

```bash
sed -i 's#build --no-cache --network=$(DOCKERNETWORK)#build --network=$(DOCKERNETWORK)#' \
  make/photon/Makefile
sed -n '21p' make/photon/Makefile   # 确认 --no-cache 已移除
```

---

## 6. 预拉 golang 镜像到 containerd（compile_core 必做）

核心组件用 `docker run golang go build` 编译 → 经包装器走 **nerdctl/containerd 存储**，与 buildkit 缓存独立，会去 DockerHub 直连拉 golang 并超时（`registry-1.docker.io ... i/o timeout`）。

用国内 mirror 预拉，再重命名为裸名（版本见 Makefile `GOBUILDIMAGE=`，本版为 `golang:1.24.13`）：

```bash
# 测可用 mirror
for m in docker.m.daocloud.io dockerproxy.net docker.1ms.run hub.rat.dev docker.1panel.live ; do
  echo "==== $m ===="; timeout 25 nerdctl pull ${m}/library/golang:1.24.13 && echo "✅ $m" && break || echo "✗ $m"
done

# 用成功的 mirror 重命名（实测 docker.m.daocloud.io 可用）
MIRROR=docker.m.daocloud.io
nerdctl tag ${MIRROR}/library/golang:1.24.13 golang:1.24.13
nerdctl tag ${MIRROR}/library/golang:1.24.13 docker.io/library/golang:1.24.13
nerdctl images | grep golang
```

---

## 7. 编译（Go + 前端 portal）

容器编译模式，宿主机无需 Go/Node（`go：未找到命令` 仅警告，自动 fallback 容器编译）：

```bash
make compile \
  -e COMPILETAG=compile_golangimage \
  -e PULL_BASE_FROM_DOCKERHUB=true
```

流程：lint_apis(spectral) → gen_apis(swagger 生成 API 代码) → compile_core/jobservice/registryctl(容器内 Go 编译)。

> `make compile` 输出大量 swagger lint warning（如 `295 problems (0 errors, 295 warnings)`）是**正常**的——Harbor 官方 API 定义自带的风格提示，只要 **`0 errors`** 即通过。

**验证编译成功**：

```bash
echo "退出码: $?"                          # 0 = 成功（须紧接 make 后执行）
ls -lh make/photon/core/harbor_core        # 二进制已生成（约 70M）
file make/photon/core/harbor_core          # 须含 ARM aarch64（确认非 amd64）
```

---

## 8. 构建镜像

首次构建用 `PULL_BASE_FROM_DOCKERHUB=true -e BUILD_BASE=true`（建/拉 base 到本地），并用 `-e` 覆盖 trivy（ARM64 包）和 distribution（github 加速）。

> **命令务必写成单行或脚本**——终端粘贴多行 `\` 续行时，长 URL 易被换行截断，导致 `TRIVY_DOWNLOAD_URL` 残缺、`DISTRIBUTION_SRC` 回退原始 github 地址。

写成脚本最稳（heredoc 不受粘贴换行影响）：

```bash
cat > /tmp/build.sh <<'EOF'
#!/bin/bash
cd /home/lzq/harbor/harbor
make build \
  -e COMPILETAG=compile_golangimage \
  -e VERSIONTAG=v2.14.3 \
  -e PULL_BASE_FROM_DOCKERHUB=true \
  -e BUILD_BASE=true \
  -e TRIVYFLAG=true \
  -e NOTARYFLAG=false \
  -e CHARTFLAG=false \
  -e GEN_TLS=true \
  -e TRIVY_DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/aquasecurity/trivy/releases/download/v0.69.3/trivy_0.69.3_Linux-ARM64.tar.gz" \
  -e TRIVY_ADAPTER_DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/goharbor/harbor-scanner-trivy/archive/refs/tags/v0.35.1.tar.gz" \
  -e DISTRIBUTION_SRC="https://gh.llkk.cc/https://github.com/goharbor/distribution.git"
EOF
cat /tmp/build.sh    # 核对 URL 完整、无截断
bash /tmp/build.sh
```

参数说明：

| 参数 | 作用 |
|---|---|
| `VERSIONTAG=v2.14.3` | 镜像 tag |
| `BUILD_BASE=true` | 构建 photon base 层（首次必须） |
| `TRIVYFLAG=true` | 构建 trivy-adapter |
| `NOTARYFLAG/CHARTFLAG=false` | 不构建 notary/chartmuseum |
| `TRIVY_DOWNLOAD_URL=...Linux-ARM64...` | **arm64 必须改 ARM64 包**，默认 `Linux-64bit` 是 amd64，否则 trivy `exec format error` |
| `DISTRIBUTION_SRC=gh.llkk.cc/...` | registry 源码 clone 走 github 加速 |

> 注：google 的 `REGISTRYURL`（预编译 registry 二进制）该路径已 404 失效，但 v2.14.3 会自动 fallback 到 `DISTRIBUTION_SRC` 源码编译，无需处理。

### 8.1 redis 单独处理（DockerHub mirror 顽固坑）

redis 组件构建会报 `exec format error`，根因：**buildkitd 配了 `docker.m.daocloud.io` 作 mirror**，解析 `harbor-redis-base:dev` 时拉 mirror 上的 **amd64** base（digest `ce25e9a8`），无视你本地的 arm64 base。`builder prune`、重启 buildkitd、`--no-cache`、digest 直引都无法绕过（mirror 拦截 HEAD 请求 403）。

**解法：完全绕开 buildkit，用 nerdctl run/commit 手动制作 redis 镜像。**

```bash
# 1. 手动构建 arm64 redis-base（基于本地 photon:5.0，不走 mirror）
nerdctl build -f make/photon/redis/Dockerfile.base \
  -t goharbor/harbor-redis-base:dev make/photon/redis/
nerdctl image inspect goharbor/harbor-redis-base:dev --format '{{.Architecture}}'   # arm64

# 2. 用 arm64 base 起容器，手动执行 Dockerfile 步骤
nerdctl run --name redis-build --network host \
  -v "$PWD/make/photon/redis:/src:ro" \
  goharbor/harbor-redis-base:dev \
  bash -c "
    mkdir -p /var/lib/redis &&
    cp /src/docker-healthcheck /usr/bin/ &&
    cp /src/redis.conf /etc/redis.conf &&
    chmod +x /usr/bin/docker-healthcheck &&
    chown redis:redis /etc/redis.conf
  "

# 3. commit 成 redis-photon 镜像（此版 nerdctl 的 --change 仅支持 CMD）
nerdctl commit \
  --change 'CMD ["redis-server", "/etc/redis.conf"]' \
  redis-build goharbor/redis-photon:v2.14.3

# 4. 清理临时容器 + 确认架构
nerdctl rm redis-build
nerdctl image inspect goharbor/redis-photon:v2.14.3 --format '{{.Architecture}}'   # arm64
```

### 8.2 exporter 单独补构建（若 build 中断未轮到）

```bash
make -f make/photon/Makefile _compile_and_build_exporter \
  -e DOCKERCMD=nerdctl -e DOCKERNETWORK=default -e VERSIONTAG=v2.14.3 \
  -e BASEIMAGETAG=dev -e IMAGENAMESPACE=goharbor -e BASEIMAGENAMESPACE=goharbor \
  -e GOBUILDIMAGE=golang:1.24.13 -e BUILD_BASE=false -e PULL_BASE_FROM_DOCKERHUB=false \
  -e REGISTRYUSER= -e REGISTRYPASSWORD=
```

---

## 9. 验证产物（全部 arm64）

```bash
for img in $(nerdctl images | grep goharbor | grep v2.14.3 | awk '{print $1":"$2}' | sort -u); do
  arch=$(nerdctl image inspect "$img" --format '{{.Architecture}}' 2>/dev/null)
  echo "$arch  $img"
done
```

预期 **12 个全 arm64**：
```
arm64  goharbor/harbor-core:v2.14.3
arm64  goharbor/harbor-db:v2.14.3
arm64  goharbor/harbor-exporter:v2.14.3
arm64  goharbor/harbor-jobservice:v2.14.3
arm64  goharbor/harbor-log:v2.14.3
arm64  goharbor/harbor-portal:v2.14.3
arm64  goharbor/harbor-registryctl:v2.14.3
arm64  goharbor/nginx-photon:v2.14.3
arm64  goharbor/prepare:v2.14.3
arm64  goharbor/redis-photon:v2.14.3
arm64  goharbor/registry-photon:v2.14.3
arm64  goharbor/trivy-adapter-photon:v2.14.3
```

> Helm 部署实际只用 10 个（不含 `prepare`、`harbor-log`，那是 compose 离线安装包才用的）。

---

## 10. 重命名并推送到 SWR

```bash
nerdctl login swr.cn-southwest-2.myhuaweicloud.com

for name in nginx-photon harbor-portal harbor-core harbor-jobservice registry-photon harbor-registryctl trivy-adapter-photon harbor-db redis-photon harbor-exporter prepare harbor-log; do
  echo "==== ${name} ===="
  nerdctl tag goharbor/${name}:v2.14.3 \
    swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
  nerdctl push swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/${name}:v2.14.3-arm
done
```

> 只推 Helm 用到的 10 个：从列表去掉末尾 `prepare harbor-log` 即可。
> SWR `login` 失败：华为云需在控制台「我的凭证 / 客户端上传」获取临时 docker login 指令或长期访问密钥。

---

## 11. Helm values 中使用（tag 加 -arm）

values.yaml 每个组件分开写 `repository` + `tag`，tag 直接用 `v2.14.3-arm` 即可，例如：

```yaml
core:
  image:
    repository: swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-core
    tag: v2.14.3-arm
```

⚠️ **registry 组件有两个镜像**，别漏其中一个：

```yaml
registry:
  registry:
    image:
      repository: swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/registry-photon
      tag: v2.14.3-arm
  controller:
    image:
      repository: swr.cn-southwest-2.myhuaweicloud.com/zqli/goharbor/harbor-registryctl
      tag: v2.14.3-arm
```

10 个组件对应关系：nginx、portal、core、jobservice、registry(registry-photon)、registry.controller(harbor-registryctl)、trivy、database.internal(harbor-db)、redis.internal(redis-photon)、exporter(harbor-exporter)。

---

## 12. 构建后清理（保护服务器 + K3s 其他应用）

> ⚠️ 本服务器跑着 K3s，nerdctl 连的是 K3s 的 containerd（`default` namespace），构建缓存/中间镜像与 K3s 共用 `/dev/sda3`。清理不当会误删集群镜像，**务必按下面顺序、用精确过滤**，不要无脑 `prune -a --all`。

### 12.1 清理前先看占用

```bash
df -h /                                    # 根盘余量
nerdctl system df 2>/dev/null || nerdctl images | head
sudo du -sh /var/lib/buildkit 2>/dev/null  # buildkit 缓存目录占用（最大头）
```

### 12.2 清 buildkit 构建缓存（最大头，安全）

buildkit 缓存独立于 containerd 镜像存储，清它**不影响任何运行中的容器/镜像**：

```bash
nerdctl builder prune -f          # 清 buildkit 构建缓存（本次构建累计可达 20G+）
```

### 12.3 删构建产生的中间/临时镜像（精确，不碰 K3s）

构建过程产生了一批 `*-base:dev` 中间镜像和 `registry-golang`/`trivy-adapter-golang` 临时编译镜像，推送完成后可删。**只删 goharbor 的 dev base 和已知临时镜像，不动 K3s 的 `k8s.io` namespace**：

```bash
# 删 *-base:dev 中间基础镜像（构建用，运行不需要）
for img in $(nerdctl images | grep 'goharbor/harbor-.*-base' | grep dev | awk '{print $1":"$2}'); do
  nerdctl rmi "$img"
done
nerdctl rmi goharbor/harbor-redis-base:dev 2>/dev/null || true

# 删编译临时镜像（若残留）
nerdctl rmi registry-golang:latest trivy-adapter-golang:latest 2>/dev/null || true

# 删测试镜像
nerdctl rmi buildtest:arm 2>/dev/null || true

# 删拉取的 golang 编译镜像（编译已完成，运行不需要）
nerdctl rmi golang:1.24.13 docker.io/library/golang:1.24.13 \
  docker.m.daocloud.io/library/golang:1.24.13 2>/dev/null || true

# 删悬空镜像
nerdctl image prune -f
```

> **不要执行** `nerdctl rmi` 删 `goharbor/*:v2.14.3`（成品，推送后本地留存或删除均可，确认 SWR 已有再删）。
> **绝不执行** `nerdctl --namespace k8s.io rmi ...` 或 `crictl rmi --prune`——那是 K3s 集群在用的镜像。

### 12.4 清理源码临时文件

```bash
# 构建临时目录（registry/trivy 源码 clone 到 /tmp）
rm -rf /tmp/distribution.* /tmp/trivy-adapter.* /tmp/cni.tgz /tmp/sp_test /tmp/build.sh 2>/dev/null

# 源码目录（确认镜像已推送 SWR 后，可整个删掉省空间，约数 GB）
# cd ~ && rm -rf /home/lzq/harbor/harbor
```

### 12.5 移除临时改动（恢复环境）

```bash
# 移除 docker→nerdctl 包装器（构建专用，平时不需要；若日常也想用 docker 命令代理 nerdctl 可保留）
rm -f /usr/local/bin/docker

# buildkitd 若是本次手动 sudo nohup 起的、平时不需要，可停掉（按需）
# pkill -f buildkitd
```

> CNI 插件（`/opt/cni/bin/`）建议**保留**——K3s 本身也用这个目录，删了可能影响集群网络。

### 12.6 清理后复查

```bash
df -h /                                # 确认空间回收
nerdctl images | grep v2.14.3-arm      # 确认成品 -arm 镜像仍在（若已推送也可本地删）
kubectl get pods -A 2>/dev/null | grep -v Running | grep -v Completed   # 确认 K3s 应用未受影响
```

---

## 13. 踩坑速查表

| 报错 | 阶段 | 解决 |
|---|---|---|
| `Need to install docker(20.10.10+)` | compile 前 | §3 包装器伪造 `--version` |
| `go：未找到命令` | compile | 仅警告，容器编译自动 fallback |
| `curl: (52)/(28)`（spectral） | lint_apis | §5.1 github 加速 |
| `needs CNI plugin "bridge"` | lint/registry | §3 包装器 `--network host` + §4 装 CNI 插件 |
| `proxy.golang.org ... timeout`（swagger） | gen_apis | §5.2 GOPROXY 注入 / 包装器 GOPROXY |
| `registry-1.docker.io ... timeout`（compile_core） | compile | §6 预拉 golang 重命名 |
| swagger `0 errors, NNN warnings` | compile | 正常，无需处理 |
| `go.mod requires go >= 1.25.0` | registry | §5.4 GOTOOLCHAIN=auto |
| `checksum database disabled by GOSUMDB=off` | registry | §5.4 GOSUMDB=sum.golang.google.cn |
| db `nothing provides libxml2.so.2`（postgresql14） | db base | 无害，db 用远程 dev base fallback 成功，最终镜像正常 |
| `exec format error`（exporter 运行） | 部署 | §5.3 改 GOARCH=arm64 |
| `exec format error`（redis 构建） | redis | §8.1 绕开 buildkit mirror，nerdctl run/commit 手动制作 |
| trivy `exec format error` | 部署 | §8 TRIVY_DOWNLOAD_URL 改 Linux-ARM64 |
| `-e` 参数 URL 残缺 | build | 命令写单行或脚本，§8 |

---

## 附：本次改动的文件清单

| 文件 | 改动 |
|---|---|
| `/usr/local/bin/docker` | 新建包装器（伪造 version + run/create 注入 host 网络/GOPROXY） |
| `/opt/cni/bin/*` | 安装 CNI 插件 |
| `tools/spectral/Dockerfile` 等 | github URL 加 `gh.llkk.cc` 前缀 |
| `tools/swagger/Dockerfile`、`tools/mockery/Dockerfile` | 加 `ENV GOPROXY` |
| `make/photon/trivy-adapter/Dockerfile.binary` | export 行加 GOPROXY/GOSUMDB |
| `make/photon/exporter/Dockerfile` | `GOARCH=amd64`→`arm64` + GOPROXY/GOSUMDB |
| `make/photon/registry/Dockerfile.binary` | GOTOOLCHAIN=auto + GOPROXY + GOSUMDB=sum.golang.google.cn |
| `make/photon/Makefile` | 第 21 行去掉 `--no-cache`（可选） |

---

*构建环境：arm64 / nerdctl v2.3.3 / containerd v2.2.3-k3s1 / buildkitd v0.31.0 / Harbor v2.14.3 / golang 1.24.13(+自动 1.25 for registry)*
