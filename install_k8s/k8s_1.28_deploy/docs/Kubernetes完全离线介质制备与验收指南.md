# Kubernetes v1.28.15 完全离线介质制备与验收手册

> **适用项目**：本仓库 `redhat/offline/` 与 `ubuntu/offline/`
> **当前基准**：Kubernetes v1.28.15、Calico v3.26.4、kube-vip v0.8.0、amd64
> **目标**：在目标节点完全不能访问互联网、没有私有镜像仓库的情况下，仅依赖本地介质完成部署。

---

## 1. 先回答两个关键问题

### 1.1 镜像清单在哪里看

本仓库可从四个位置确认镜像，优先级如下：

1. **本手册第 3 节**：当前基准版本的完整清单。
2. `*/offline/config/cluster.env`：Kubernetes、Calico、kube-vip 版本及仓库前缀。
3. `*/offline/manifests/calico.yaml`：Calico 部署真正引用的镜像名。
4. 实际 tar 或 containerd：这是最终事实来源。

```bash
# kubeadm 核心镜像清单
kubeadm config images list \
  --kubernetes-version v1.28.15 \
  --image-repository registry.aliyuncs.com/google_containers

# Calico manifest 中真正引用的镜像
awk '/^[[:space:]]*image:/ {print $2}' manifests/calico.yaml | sort -u

# tar 导入后查看实际镜像名
ctr -n k8s.io images import images/k8s-core.tar
ctr -n k8s.io images import images/calico.tar
ctr -n k8s.io images import images/kube-vip.tar
ctr -n k8s.io images list -q | sort -u
```

> 不能只看 tar 文件名。`calico.tar` 只表示归档用途；kubelet 能否使用它，取决于归档中的完整镜像引用是否和 YAML 中的 `image:` 完全一致。

### 1.2 “完全离线材料”不只是镜像

一套可独立部署的离线介质至少包含六类内容：

| 类别 | 内容 | 是否与宿主 OS 有关 |
|------|------|---------------------|
| 容器镜像 | K8s 核心、Calico、kube-vip | 通常与 OS 无关；与 CPU 架构、版本有关 |
| 系统软件包 | containerd、kubelet、kubeadm、kubectl 及依赖 | **有关**；Ubuntu 用 deb，CentOS 7 用 rpm |
| 仓库元数据 | `Packages.gz` 或 `repodata/` | **有关** |
| 部署清单 | `calico.yaml` 等 | 与组件版本、镜像引用、网络模式有关 |
| 脚本和配置 | `scripts/`、`config/`、`tools/` | 通常按发行版区分 |
| 完整性资料 | 镜像清单、包清单、SHA-256、制备环境信息 | 必须随介质保存 |

另外还应准备目标操作系统安装 ISO、网卡/存储驱动、固件以及可能缺失的内核模块包。这些不属于 Kubernetes 项目文件，但在真正 air-gap 的机房中同样重要。

---

## 2. 当前目录中的离线材料

### 2.1 Ubuntu 24.04 noble amd64

路径：`ubuntu/offline/`

当前实际包含：

| 内容 | 当前状态 |
|------|----------|
| deb | 401 个 |
| apt 索引 | `packages/Packages.gz` |
| 核心镜像 | `images/k8s-core.tar` |
| Calico 镜像 | `images/calico.tar` |
| kube-vip 镜像 | `images/kube-vip.tar` |
| Calico 清单 | `manifests/calico.yaml` |
| 制备脚本 | `scripts/fetch-resources.sh` |
| 导入脚本 | `scripts/import-resources.sh` |
| 证书工具 | `tools/update-kubeadm-cert.sh` |

> 当前 deb 是按 **Ubuntu 24.04 noble amd64** 的依赖树制备的。不能把它直接用于 Ubuntu 22.04、Debian、ARM64 或其他发行版；这些环境必须重新制备 packages。

### 2.2 CentOS 7.9 x86_64

路径：`redhat/offline/`

当前实际包含：

| 内容 | 当前状态 |
|------|----------|
| rpm | 32 个 |
| yum 元数据 | `packages/repodata/repomd.xml` |
| 核心镜像 | `images/k8s-core.tar` |
| Calico 镜像 | `images/calico.tar` |
| kube-vip 镜像 | `images/kube-vip.tar` |
| Calico 清单 | `manifests/calico.yaml` |
| 导入脚本 | `scripts/import-resources.sh` |
| 证书工具 | `tools/update-kubeadm-cert.sh` |

> 当前 Red Hat 系列脚本的已验证目标是 **CentOS 7.9 x86_64**，不是泛指所有 RHEL、Rocky、AlmaLinux 或 CentOS Stream。不同发行版/大版本必须重新解析 RPM 依赖并重新验证。

---

## 3. 当前完整容器镜像清单

### 3.1 Kubernetes 核心镜像：7 个

```text
registry.aliyuncs.com/google_containers/kube-apiserver:v1.28.15
registry.aliyuncs.com/google_containers/kube-controller-manager:v1.28.15
registry.aliyuncs.com/google_containers/kube-scheduler:v1.28.15
registry.aliyuncs.com/google_containers/kube-proxy:v1.28.15
registry.aliyuncs.com/google_containers/etcd:3.5.15-0
registry.aliyuncs.com/google_containers/coredns:v1.10.1
registry.aliyuncs.com/google_containers/pause:3.9
```

不要手工猜 etcd、CoreDNS 和 pause 的标签。升级 Kubernetes 后应重新执行 `kubeadm config images list`。

### 3.2 Calico 镜像：3 个

当前 Ubuntu 和两套离线 `calico.yaml` 实际引用：

```text
m.daocloud.io/docker.io/calico/node:v3.26.4
m.daocloud.io/docker.io/calico/cni:v3.26.4
m.daocloud.io/docker.io/calico/kube-controllers:v3.26.4
```

同一内容也可能存在官方名字：

```text
docker.io/calico/node:v3.26.4
docker.io/calico/cni:v3.26.4
docker.io/calico/kube-controllers:v3.26.4
```

**离线部署中必须保证 manifest 引用的完整名称存在。** 如果 tar 只有官方名，而 YAML 使用 DaoCloud 名，导入后需要补 tag：

```bash
for component in node cni kube-controllers; do
  ctr -n k8s.io images tag \
    "docker.io/calico/${component}:v3.26.4" \
    "m.daocloud.io/docker.io/calico/${component}:v3.26.4"
done
```

也可以反向打 tag，或在制备时直接按 manifest 的名称拉取和导出。不要只比较 tag；若需确认内容相同，应比较目标平台的 digest。

### 3.3 kube-vip 镜像：1 个

```text
ghcr.io/kube-vip/kube-vip:v0.8.0
```

单 Master 不部署 kube-vip，可以不带该镜像；为了让同一介质同时支持单 Master 和多 Master，建议仍然保留。

### 3.4 总数

当前完整功能集共 **11 个镜像引用**：

- Kubernetes 核心：7 个；
- Calico：3 个；
- kube-vip：1 个。

若增加 metrics-server、Ingress Controller、MetalLB、存储 CSI、日志、监控或业务镜像，必须另行加入；本清单不自动包含这些可选组件。

---

## 4. 制备机必须满足的条件

### 4.1 与目标环境匹配

| 项目 | 要求 |
|------|------|
| OS 软件包 | 制备机与目标机使用相同发行版、版本、架构和仓库快照 |
| 镜像平台 | 当前为 `linux/amd64`；ARM64 应重新拉取 `linux/arm64` |
| Kubernetes | 固定为 v1.28.15 |
| CNI | 固定为 Calico v3.26.4 |
| kube-vip | 固定为 v0.8.0 |
| containerd namespace | 导入/导出使用 `k8s.io` |
| 时间 | 记录制备日期和仓库状态，防止以后仓库更新导致依赖漂移 |

### 4.2 为什么必须使用同版本干净制备机

包管理器按制备机当时的已安装状态解析依赖。如果制备机已经安装大量软件，简单执行 `--download-only` 可能不再下载目标节点缺少的依赖。因此推荐：

1. 使用与目标节点相同 ISO 新建一台干净虚拟机；
2. 应用与目标节点相同的系统更新级别；
3. 清理包缓存；
4. 运行制备流程；
5. 在另一台断网、同版本干净虚拟机上做完整安装验收。

只有“能下载并打包”不算验证成功；必须在真正断网的干净节点安装一遍。

---

## 5. Ubuntu 完整离线介质制备

### 5.1 推荐方式：使用仓库脚本

在一台能联网的、与目标节点一致的 Ubuntu 机器上：

```bash
cd ubuntu/offline

# 先核对版本、仓库和架构
sed -n '1,120p' config/cluster.env
dpkg --print-architecture
. /etc/os-release
echo "$PRETTY_NAME / $VERSION_CODENAME"

chmod +x scripts/*.sh
sudo ./scripts/fetch-resources.sh
```

脚本生成：

```text
ubuntu/offline/
├── packages/
│   ├── *.deb
│   └── Packages.gz
├── images/
│   ├── k8s-core.tar
│   ├── calico.tar
│   └── kube-vip.tar
└── manifests/
    └── calico.yaml
```

### 5.2 deb 必需功能包

制备脚本至少需要解析并保存以下包及其完整依赖：

```text
containerd
kubelet=1.28.15-*
kubeadm=1.28.15-*
kubectl=1.28.15-*
kubernetes-cni
cri-tools
conntrack
socat
ipset
ipvsadm
chrony
wget
curl
net-tools
bash-completion
ca-certificates
gnupg
```

`dpkg-dev` 用于生成 `Packages.gz`；目标节点如果已经随介质带有正确的 `Packages.gz`，部署时不一定需要安装它。

某些 Ubuntu 内核/安装镜像可能把 `br_netfilter`、IPVS 等模块放在对应内核的 `linux-modules-extra-$(uname -r)` 中。制备前应在与目标相同的内核上验证：

```bash
for module in overlay br_netfilter ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack; do
  modinfo "$module" >/dev/null || echo "缺少内核模块: $module"
done
```

如果缺少，应把匹配目标内核版本的 `linux-modules-extra-*` 及依赖加入离线 deb；不能拿其他内核版本的模块包代替。

### 5.3 重新生成 apt 本地索引

```bash
cd ubuntu/offline
dpkg-scanpackages packages /dev/null | gzip -9c > packages/Packages.gz

gzip -t packages/Packages.gz
zcat packages/Packages.gz | grep -E '^Package: (containerd|kubeadm|kubelet|kubectl)$'
```

`Packages.gz` 中的 `Filename:` 必须指向介质中真实存在的相对路径，不能残留制备机上的 `/root/...` 绝对路径。

### 5.4 拉取和导出镜像

仓库脚本会自动处理。手工制备时可采用：

```bash
KUBE_VERSION=v1.28.15
REPO=registry.aliyuncs.com/google_containers
PLATFORM=linux/amd64

K8S_IMAGES="$(kubeadm config images list \
  --kubernetes-version "$KUBE_VERSION" \
  --image-repository "$REPO")"

for image in $K8S_IMAGES; do
  ctr -n k8s.io images pull --platform "$PLATFORM" "$image"
done

ctr -n k8s.io images export images/k8s-core.tar $K8S_IMAGES

CALICO_IMAGES="
m.daocloud.io/docker.io/calico/node:v3.26.4
m.daocloud.io/docker.io/calico/cni:v3.26.4
m.daocloud.io/docker.io/calico/kube-controllers:v3.26.4
"
for image in $CALICO_IMAGES; do
  ctr -n k8s.io images pull --platform "$PLATFORM" "$image"
done
ctr -n k8s.io images export images/calico.tar $CALICO_IMAGES

KUBEVIP_IMAGE=ghcr.io/kube-vip/kube-vip:v0.8.0
ctr -n k8s.io images pull --platform "$PLATFORM" "$KUBEVIP_IMAGE"
ctr -n k8s.io images export images/kube-vip.tar "$KUBEVIP_IMAGE"
```

> 任一 pull 失败都应终止制备，不能继续导出并宣称介质完整。网络不稳定时应重试并最终核对完整清单。

### 5.5 获取 Calico manifest

```bash
curl -fL \
  https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml \
  -o manifests/calico.yaml

# 如果根据本项目需要改成 DaoCloud 引用：
sed -i 's#docker.io/calico/#m.daocloud.io/docker.io/calico/#g' manifests/calico.yaml

awk '/^[[:space:]]*image:/ {print $2}' manifests/calico.yaml | sort -u
```

还要保留本项目对 Pod CIDR、VXLAN、BGP、网卡探测和健康探针所做的定制。不要仅下载上游文件后直接覆盖已经验证的项目 manifest；应对比差异后再替换。

---

## 6. CentOS 7.9 完整离线介质制备

### 6.1 使用同版本制备机

应使用 CentOS 7.9 x86_64 制备 RPM。安装下载及建库工具：

```bash
yum install -y yum-utils createrepo
mkdir -p /tmp/k8s-offline-rpms
```

配置与本项目相同的 Kubernetes v1.28 和 containerd 仓库后，解析完整依赖：

```bash
yumdownloader --resolve --alldeps \
  --destdir=/tmp/k8s-offline-rpms \
  containerd.io \
  kubelet-1.28.15 kubeadm-1.28.15 kubectl-1.28.15 \
  kubernetes-cni cri-tools \
  conntrack-tools socat ipset ipvsadm chrony \
  libseccomp bash-completion wget curl net-tools yum-utils \
  yum-plugin-versionlock

createrepo /tmp/k8s-offline-rpms
```

把 RPM 和整个 `repodata/` 一起复制到：

```text
redhat/offline/packages/
```

仅复制 rpm 而不带 `repodata/repomd.xml`，当前导入脚本会认定本地仓库不完整。

### 6.2 RPM 的注意事项

- `--resolve --alldeps` 仍应在干净、同版本制备机上执行并做断网验收。
- 当前目标是 CentOS 7.9，不要混入 EL8/EL9 包。
- 不要混用 x86_64 与 aarch64。
- CentOS 7 的 libseccomp 较旧，必须以实际 containerd/pause 启动测试为准。
- 软件包来源可能下线或改变；长期保存时应同时保存 RPM、repodata 和 SHA-256，而不是只保存下载 URL。
- 当前目录已有 RPM 不代表未来新装的目标 OS 一定具备所有底层依赖；断网干净机验证才是最终标准。

### 6.3 镜像和 manifest

镜像与 Ubuntu 的制备方法相同，只要以下条件完全一致：

- `linux/amd64`；
- Kubernetes v1.28.15；
- Calico v3.26.4；
- kube-vip v0.8.0；
- manifest 中的完整镜像引用一致。

因此可以复制 Ubuntu 已验证的三个 tar，也可以重新拉取。复制后仍必须执行第 8 节的镜像名称对账，不能仅凭 tar 大小相近判断相同。

---

## 7. 必须随介质保存的非包文件

以下目录缺一不可：

```text
offline/
├── README.md
├── config/
│   └── cluster.env
├── scripts/
│   ├── 00-env-check.sh
│   ├── 01-system-init.sh
│   ├── 02-install-containerd.sh
│   ├── 03-install-k8s.sh
│   ├── 04-init-master1.sh
│   ├── 05-join-master.sh
│   ├── 06-join-worker.sh
│   ├── 07-install-calico.sh
│   ├── 08-renew-certs.sh
│   ├── 09-verify.sh
│   ├── deploy-all.sh
│   └── import-resources.sh
├── tools/
│   └── update-kubeadm-cert.sh
├── manifests/
│   └── calico.yaml
├── images/
│   ├── k8s-core.tar
│   ├── calico.tar
│   └── kube-vip.tar
└── packages/
    ├── *.deb + Packages.gz       # Ubuntu
    └── *.rpm + repodata/         # CentOS 7
```

同时建议在介质中额外生成：

```text
inventory/
├── build-info.txt
├── images.txt
├── packages.txt
└── SHA256SUMS
```

---

## 8. 生成清单和 SHA-256

在 `offline/` 根目录执行：

```bash
mkdir -p inventory

{
  date -u '+built_at_utc=%Y-%m-%dT%H:%M:%SZ'
  uname -m
  cat /etc/os-release
  kubeadm version -o short 2>/dev/null || true
  containerd --version 2>/dev/null || true
} > inventory/build-info.txt

# 保存声明的镜像清单
{
  kubeadm config images list \
    --kubernetes-version v1.28.15 \
    --image-repository registry.aliyuncs.com/google_containers
  awk '/^[[:space:]]*image:/ {print $2}' manifests/calico.yaml
  echo ghcr.io/kube-vip/kube-vip:v0.8.0
} | sort -u > inventory/images.txt

# 保存软件包文件清单
find packages -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) \
  -printf '%f\n' | sort > inventory/packages.txt

# 对介质关键文件计算校验和；不要把 SHA256SUMS 自身算进去
find config scripts tools manifests images packages \
  -type f -print0 | sort -z | xargs -0 sha256sum > inventory/SHA256SUMS

sha256sum -c inventory/SHA256SUMS
```

如果使用的 `find` 不支持 `-printf`，可改用：

```bash
find packages -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) \
  -exec basename {} \; | sort > inventory/packages.txt
```

---

## 9. 镜像名称、平台和 digest 验收

### 9.1 在临时 containerd 中导入

```bash
for archive in images/*.tar; do
  ctr -n k8s.io images import "$archive"
done

ctr -n k8s.io images list
ctr -n k8s.io images list -q | sort -u
```

### 9.2 自动检查缺失镜像

```bash
EXPECTED=/tmp/expected-images.txt
ACTUAL=/tmp/actual-images.txt

{
  kubeadm config images list \
    --kubernetes-version v1.28.15 \
    --image-repository registry.aliyuncs.com/google_containers
  awk '/^[[:space:]]*image:/ {print $2}' manifests/calico.yaml
  echo ghcr.io/kube-vip/kube-vip:v0.8.0
} | sort -u > "$EXPECTED"

ctr -n k8s.io images list -q | sort -u > "$ACTUAL"

comm -23 "$EXPECTED" "$ACTUAL" > /tmp/missing-images.txt
if [ -s /tmp/missing-images.txt ]; then
  echo '离线介质缺少以下镜像：'
  cat /tmp/missing-images.txt
  exit 1
fi

echo '镜像完整性检查通过'
```

单 Master 若有意不携带 kube-vip，可从期望清单排除它；多 Master 必须保留。

### 9.3 检查平台

```bash
for image in $(cat "$EXPECTED"); do
  ctr -n k8s.io images inspect "$image" >/dev/null || {
    echo "无法检查: $image"
    continue
  }
  echo "[存在] $image"
done
```

制备时已使用 `--platform linux/amd64`。如果目标是 ARM64，应把所有 pull 的 platform 改成 `linux/arm64`，并重新准备 deb/rpm；不能只重制镜像。

---

## 10. 软件包仓库验收

### 10.1 Ubuntu

```bash
gzip -t packages/Packages.gz

# 查看关键包是否存在
for package in containerd kubelet kubeadm kubectl kubernetes-cni cri-tools; do
  if zcat packages/Packages.gz | grep -qx "Package: $package"; then
    echo "[存在] $package"
  else
    echo "[缺失] $package"
  fi
done
```

最终必须在断网干净 Ubuntu 节点上验证：

```bash
# 确保外网不可用后执行项目导入脚本
./scripts/import-resources.sh

apt-cache policy containerd kubelet kubeadm kubectl
apt-get --no-download install -y containerd kubelet kubeadm kubectl
```

### 10.2 CentOS 7

```bash
test -f packages/repodata/repomd.xml
rpm -qip packages/*.rpm >/dev/null

cat >/etc/yum.repos.d/k8s-media-test.repo <<EOF
[k8s-media-test]
name=Kubernetes Offline Media Test
baseurl=file://$(pwd)/packages
enabled=1
gpgcheck=0
EOF

yum --disablerepo='*' --enablerepo=k8s-media-test clean all
yum --disablerepo='*' --enablerepo=k8s-media-test makecache
yum --disablerepo='*' --enablerepo=k8s-media-test list \
  containerd.io kubelet kubeadm kubectl kubernetes-cni cri-tools
```

最终同样要在无外网、干净 CentOS 7.9 节点执行安装验证。

---

## 11. 打包、传输和目标端验签

### 11.1 打包

```bash
# 在 ubuntu/ 或 redhat/ 目录执行
OS_FLAVOR=ubuntu-noble-amd64   # CentOS 可改为 centos7-amd64
tar --numeric-owner -czf "k8s-v1.28.15-${OS_FLAVOR}-offline.tar.gz" offline/
sha256sum "k8s-v1.28.15-${OS_FLAVOR}-offline.tar.gz" \
  > "k8s-v1.28.15-${OS_FLAVOR}-offline.tar.gz.sha256"
```

### 11.2 目标端验证

```bash
sha256sum -c k8s-v1.28.15-*-offline.tar.gz.sha256
tar -tzf k8s-v1.28.15-*-offline.tar.gz >/dev/null

tar -xzf k8s-v1.28.15-*-offline.tar.gz -C /opt/k8s-deploy/
cd /opt/k8s-deploy/offline
sha256sum -c inventory/SHA256SUMS
```

校验失败时不要继续安装，应重新复制介质或重新制备。

---

## 12. 真正断网验收流程

离线介质只有通过下面测试，才能称为“完整”：

1. 新建一台与目标完全相同的干净虚拟机；
2. 禁用默认路由或在防火墙上阻止互联网；
3. 将离线介质复制进去；
4. 验证 SHA-256；
5. 配置本地 deb/yum 仓库；
6. 仅从本地仓库安装 containerd、Kubernetes 和依赖；
7. 导入所有镜像；
8. 运行 `kubeadm config images list` 对账；
9. 初始化至少一个单 Master 测试集群；
10. 安装 Calico并等待 Pod Ready；
11. 创建测试 Pod 和 Service，验证 DNS、Pod 跨节点通信和 Service；
12. 检查日志中不存在镜像外拉和软件包联网请求。

建议断网方式之一：

```bash
# 测试机保留局域网传输能力，但移除互联网默认路由前先记录
ip route > /root/route-before-offline-test.txt
ip route del default

# 验证确实无法访问公网
curl --connect-timeout 3 https://registry.k8s.io && {
  echo '错误：测试机仍可访问公网'
  exit 1
} || true
```

> 远程执行删除默认路由会断开跨网段 SSH。只应在 console、同二层管理网或可恢复的测试虚拟机中执行。

---

## 13. 常见遗漏与判断方法

| 现象 | 最可能遗漏 | 检查方法 |
|------|------------|----------|
| containerd 装不上 | deb/rpm 依赖不全 | 使用 `--no-download` 或仅启用本地 yum repo 测试 |
| kubeadm init 尝试联网 | 镜像名不匹配或缺镜像 | `kubeadm config images list` 对比 `ctr -n k8s.io images list -q` |
| Calico ImagePullBackOff | tar 中镜像名与 `calico.yaml` 不一致 | 对比完整 registry/path/tag，必要时补 tag |
| kubelet 看不到已导入镜像 | 导入到错误 namespace | 必须使用 `ctr -n k8s.io` |
| 包索引指向不存在路径 | `Packages.gz` 中 Filename 错误 | `zcat Packages.gz` 检查 `Filename:` |
| br_netfilter/IPVS 加载失败 | 内核模块包未准备 | `modinfo`，Ubuntu 检查匹配内核的 modules-extra |
| 多 Master 初始化缺镜像 | 未携带 kube-vip | 检查 `kube-vip.tar` 和完整镜像名 |
| ARM 节点启动报 exec format | 制备的是 amd64 | 重新按 linux/arm64 拉镜像和准备系统包 |
| 以后无法复现同一介质 | 未保存包文件和校验清单 | 保存 packages、仓库元数据、build-info、SHA256SUMS |

---

## 14. 升级版本时必须重新做什么

修改任意一项后，都应重新生成并完整验收介质：

- Kubernetes 版本；
- Calico 版本或网络模式；
- kube-vip 版本；
- Ubuntu/CentOS 版本；
- CPU 架构；
- containerd 版本；
- 镜像仓库前缀；
- Calico manifest；
- 新增 Ingress、MetalLB、CSI、metrics-server、监控等组件。

更新顺序：

1. 修改 `config/cluster.env`；
2. 用 kubeadm 重新生成核心镜像清单；
3. 下载对应组件 manifest 并确认其镜像；
4. 重新准备系统包及依赖；
5. 重新导出镜像；
6. 生成 inventory 与 SHA-256；
7. 在断网干净机完整部署；
8. 验收通过后才替换生产离线介质。

---

## 15. 最终交付检查表

- [ ] OS 发行版、版本、架构与目标一致
- [ ] Kubernetes/Calico/kube-vip/containerd 版本已记录
- [ ] 7 个 Kubernetes 核心镜像齐全
- [ ] 3 个 Calico 镜像名称与 manifest 完全一致
- [ ] 多 Master 所需 kube-vip 镜像齐全
- [ ] deb/rpm 及完整依赖齐全
- [ ] `Packages.gz` 或 `repodata/` 有效
- [ ] `calico.yaml` 是当前项目已验证版本
- [ ] scripts/config/tools 全部随介质打包
- [ ] build-info、images、packages 清单已保存
- [ ] SHA256SUMS 校验通过
- [ ] 压缩包传输后校验通过
- [ ] 在真正断网、干净节点完成安装
- [ ] kubeadm 没有尝试联网拉镜像
- [ ] Calico、CoreDNS、kube-proxy 全部 Ready
- [ ] Pod、DNS、Service 和跨节点网络验证通过

只有全部完成，才能把该介质标记为“可用于完全 air-gap 部署”。
