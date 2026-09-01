# Kubernetes 1.28 离线部署版（air-gap）

> 支持 1/3/5 个 Master 与任意数量 Worker；本目录只提供默认示例，实际节点以 `config/cluster.env` 为准。
> **镜像已随目录打包，节点无需联网，直接加载部署**

本目录与 `online/`（在线）、`private-registry/`（私有仓库）平级，各自独立自包含。适用场景：内网无外网、无私有仓库，靠本地介质完成部署。

## 控制面模式

`MASTER_COUNT=1` 时使用 master1 IP 作为控制面端点，不部署 kube-vip；`MASTER_COUNT>1` 时使用 VIP 并部署 kube-vip。离线镜像 tar 必须与所选模式匹配；单 Master 不要求 kube-vip 镜像。


| 项 | 在线版 (online/) | 离线版 (本目录) |
|----|-----------------|----------------|
| 容器镜像 | 部署时从阿里云/DaoCloud 拉取 | **已导出为 tar 放在 `images/`，部署时本地导入** |
| Calico manifest | 部署时从 gitee 下载 | 已放在 `manifests/calico.yaml` |
| 证书脚本 | 内置 | 内置 `tools/update-kubeadm-cert.sh` |
| 软件包(rpm) | 阿里云 yum 源 | `packages/` 有则用本地，无则回退阿里云在线源 |
| 是否需外网 | 需要 | **镜像不需要**；软件包若用在线源仍需（见下） |

## 目录结构（自包含）

```
offline/
├── README.md
├── config/cluster.env           # 配置（节点/VIP/版本）
├── tools/update-kubeadm-cert.sh # 证书续期脚本
├── manifests/calico.yaml        # Calico 清单（本地）
├── images/                      # ★ 离线镜像 tar（约 400M，随目录附带）
│   ├── k8s-core.tar             #   K8s 核心 7 镜像（apiserver/etcd/coredns/pause 等）
│   ├── calico.tar               #   Calico 3 镜像（node/cni/kube-controllers）
│   └── kube-vip.tar             #   kube-vip 镜像
├── packages/                    # 离线 RPM（可选，空则用在线 yum 源）
└── scripts/
    ├── 00-env-check.sh          # 全部节点｜环境检查
    ├── 01-system-init.sh        # 全部节点｜系统初始化（含 arp_ignore）
    ├── 02-install-containerd.sh # 全部节点｜装 containerd
    ├── import-resources.sh      # 全部节点｜★导入本地镜像 tar（namespace=k8s.io）
    ├── 03-install-k8s.sh        # 全部节点｜装 kubeadm/kubelet/kubectl
    ├── 04-init-master1.sh       # 仅 master1｜kube-vip + init（镜像已本地，不拉取）
    ├── 05-join-master.sh        # 仅 master2/3｜加入控制平面
    ├── 06-join-worker.sh        # 仅 node1~6｜加入 worker
    ├── 07-install-calico.sh     # 仅 master1｜装 CNI（用本地 manifest）
    ├── 08-renew-certs.sh        # 每个 master｜证书续期 10 年
    ├── 09-verify.sh             # 仅 master1｜验收
    └── deploy-all.sh            # 仅 master1｜一键部署（分发全套资源+镜像）
```

## 快速开始

### 一键部署

```bash
# 1. 整个 offline 目录（含 images/）拷贝到 master1
scp -r offline/ root@192.168.104.104:/opt/k8s-deploy-offline/
# 2. master1 上一键部署（会自动分发脚本+镜像到所有节点并导入）
ssh root@192.168.104.104
cd /opt/k8s-deploy-offline/scripts && chmod +x *.sh
./deploy-all.sh
```

`deploy-all.sh` 的 phase 流程比在线版多一步 **Phase 2.5：导入本地镜像**——在 containerd 装好后、装 K8s 组件前，各节点执行 `import-resources.sh` 把 `images/*.tar` 用 `ctr -n k8s.io images import` 导入（namespace 必须 k8s.io，否则 kubelet 看不到）。

### 分步执行

先把整个 `offline/` 目录（含 `images/`）传到 master1，各节点 SSH 免密已通；配置只需确认 `config/cluster.env` 里的节点列表 / VIP / 网卡（本目录自包含，脚本 `source ../config/cluster.env`）。在每个节点的 `scripts/` 目录里按下表执行。

## 分步部署命令速查

| 步骤 | 执行节点 | 命令 | 说明 |
|------|---------|------|------|
| 1 | 当前配置中的全部节点 | `./00-env-check.sh` | 环境检查（只读，不改系统） |
| 2 | 当前配置中的全部节点 | `./01-system-init.sh` | 系统初始化（swap/SELinux/内核模块/sysctl/hosts） |
| 3 | 当前配置中的全部节点 | `./02-install-containerd.sh` | 装 containerd（本地 RPM，`packages/` 空则回退阿里云源） |
| 4 | 当前配置中的全部节点 | `./import-resources.sh` | ★离线专属：导入 `images/*.tar`（`ctr -n k8s.io images import`） |
| 5 | 当前配置中的全部节点 | `./03-install-k8s.sh` | 装 kubeadm/kubelet/kubectl |
| 6 | 仅 master1 | `./04-init-master1.sh` | 单 Master 直连；多 Master 使用本地 kube-vip 镜像和 VIP |
| — | master1 → 其余节点 | `scp /etc/kubernetes/deploy/join.env root@<节点>:/etc/kubernetes/deploy/` | 分发 join 凭据（一键版自动做，分步需手动） |
| 7 | 其余 master（串行） | `./05-join-master.sh` | `MASTER_COUNT>1` 时加入控制平面 |
| 8 | 当前配置中的 worker（可并行） | `./06-join-worker.sh` | 加入 worker |
| 9 | 仅 master1 | `./07-install-calico.sh` | 装 Calico CNI（用本地 `manifests/calico.yaml`，VXLAN） |
| 10 | 每个 master（串行） | `./08-renew-certs.sh` | 证书续期 10 年（用本地 `tools/update-kubeadm-cert.sh`） |
| 11 | 仅 master1 | `./09-verify.sh` | 20 项验收，全绿即成功 |

> 与在线版唯一的顺序差异：**第 4 步 `import-resources.sh`**（在 containerd 装好后、装 K8s 组件前导入本地镜像）。其余步骤编号与逻辑同在线版。一键 `deploy-all.sh` 已把这一步编排为 Phase 2.5。

## 镜像清单与在线下载来源（介质如何产生 / 如何更新）

`images/` 里的 tar 是从已部署集群导出的。若你要自行重新制备或更新版本，各资源的**在线下载来源**如下：

| 资源 | 在线来源 | 导出/获取方式 |
|------|---------|--------------|
| K8s 核心镜像 | `registry.aliyuncs.com/google_containers/*` | `kubeadm config images list` 列清单，逐个 `ctr -n k8s.io images pull` 后 `ctr -n k8s.io images export k8s-core.tar <镜像...>` |
| Calico 镜像 | 官方 `docker.io/calico/*`（国内用 `m.daocloud.io/docker.io/calico/*` 加速） | pull 后 `ctr -n k8s.io images tag` 回官方名，再 export calico.tar |
| kube-vip 镜像 | `ghcr.io/kube-vip/kube-vip:v0.8.0` | pull 后 export kube-vip.tar |
| Calico manifest | gitee: `https://gitee.com/mirrors/calico/raw/v3.26.4/manifests/calico.yaml`；官方: `raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml` | curl 下载放入 `manifests/` |
| 证书脚本 | `github.com/yuyicai/update-kube-cert` | 已内置 `tools/` |
| 软件包(rpm) | 阿里云 kubernetes-new / docker-ce 源 | 有网机器 `yumdownloader --resolve` 下载放入 `packages/` 并 `createrepo` |

> 镜像 tar 里的确切版本：K8s v1.28.15、etcd 3.5.15-0、coredns v1.10.1、pause 3.9、Calico v3.26.4、kube-vip v0.8.0。

## 证书 10 年在哪里指定

与在线版一致：`08-renew-certs.sh` 用本地 `tools/update-kubeadm-cert.sh`，**10 年在 `--days 3650`（或 `KUBE_CERT_DAYS`）指定**。离线场景优势：脚本已内置，不依赖联网。

## 离线特有注意事项

- **镜像 namespace**：必须用 `ctr -n k8s.io images import`，导错 namespace kubelet 看不到（脚本已处理）。
- **软件包**：`packages/` 为空时脚本回退到阿里云在线 yum 源——**这一步仍需外网**。要完全离线，需自行把 containerd.io / kubelet / kubeadm / kubectl / kubernetes-cni / cri-tools 及依赖的 RPM 放入 `packages/`。
- **架构**：镜像 tar 为 amd64（x86_64），ARM 环境需重新制备。
- **libseccomp**：CentOS 7 自带偏旧，若 pause/容器起不来需升级 libseccomp ≥2.4。


## 部署参数详解 / 最终 YAML 位置

仓库地址、仓库密码、kube-proxy 模式（查/改/影响）、自定义 Service 域名、Pod/Service/Calico 三网段、长期证书原理——每项的「改哪里 + 部署后最终落地在集群哪个 YAML」，统一见顶层 `../README.md` 的「配置详解 FAQ」章节。

---

## 如何准备离线 RPM/二进制包（完全无外网部署）

当前 `packages/` 目录是空的——默认走"镜像离线 + 软件包在线阿里云源"的混合模式。如果目标环境**完全无外网**,需自行把 RPM 包放进 `packages/`:

### 需要的 RPM 包清单

| 包名 | 用途 | 来源 |
|------|------|------|
| `containerd.io` | 容器运行时 | 阿里云 docker-ce 源 |
| `kubelet-1.28.15` | 节点代理 | 阿里云 kubernetes-new/v1.28/rpm 源 |
| `kubeadm-1.28.15` | 集群引导工具 | 同上 |
| `kubectl-1.28.15` | 命令行工具 | 同上 |
| `kubernetes-cni` | CNI 二进制 | 同上 |
| `cri-tools` | crictl 命令 | 同上 |
| `conntrack-tools` | 连接跟踪 | CentOS base/extras |
| `socat` | 端口转发 | CentOS base |
| `ipset` / `ipvsadm` | IPVS 工具 | CentOS base |
| `chrony` | 时间同步 | CentOS base |
| `libseccomp` (≥2.4) | 容器安全 | CentOS base/updates（⚠️ CentOS 7 自带可能偏旧） |
| `bash-completion` / `wget` / `curl` / `net-tools` | 基础工具 | CentOS base |

### 准备步骤（在一台**有外网的同版本 CentOS 7** 机器上执行）

```bash
# 1. 配置阿里云源（与部署脚本一致）
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo

cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes v1.28
baseurl=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/rpm/repodata/repomd.xml.key
EOF

# 2. 下载所有 RPM 及其依赖（--resolve 会拉完整依赖树）
mkdir -p /tmp/k8s-rpms
yumdownloader --resolve --destdir=/tmp/k8s-rpms \
    containerd.io \
    kubelet-1.28.15 kubeadm-1.28.15 kubectl-1.28.15 \
    kubernetes-cni cri-tools \
    conntrack-tools socat ipset ipvsadm chrony \
    libseccomp bash-completion wget curl net-tools yum-utils

# 3. 生成本地 yum repo 元数据
yum install -y createrepo
createrepo /tmp/k8s-rpms

# 4. 打包
tar czf k8s-rpms.tar.gz -C /tmp k8s-rpms/
echo "产出: k8s-rpms.tar.gz（约 200-300MB）"
echo "将它解压到 offline/packages/ 即可:"
echo "  tar xzf k8s-rpms.tar.gz --strip-components=1 -C offline/packages/"
```

### 放入 `packages/` 后的效果

- `import-resources.sh` 检测到 `packages/*.rpm` 后自动配本地 yum 源(`file://`)
- `02-install-containerd.sh` 和 `03-install-k8s.sh` 的 `yum install` 走本地 repo，不联网
- 实现**完全 air-gap 部署**（镜像 + 软件包全部离线）

### 验证本地 repo 可用

```bash
# 在目标节点执行 import-resources.sh 后
yum --disablerepo='*' --enablerepo='k8s-local' list containerd.io kubeadm
# 应能列出包名+版本
```

### 注意事项

- **同 OS 版本**：准备 RPM 的机器必须和目标节点同为 CentOS 7.x（依赖树与小版本相关）
- **libseccomp ≥2.4**：CentOS 7 自带 2.3.1，`pause:3.9` 等新容器可能需要 ≥2.4。若 `yumdownloader` 拉不到新版，手动从 [EPEL](https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/l/) 下载放入 `packages/`
- **架构**：上述命令默认下 x86_64 包；ARM(aarch64) 需在 ARM 机器上执行或指定 `--archlist=aarch64`
- **已有镜像但缺 RPM** 的现象：`02` 装 containerd 时报"No package containerd.io available" → 检查 `packages/` 是否有 RPM 和 `repodata/`
- **Debian/Ubuntu**：RPM 不适用，需用 `apt-get download` + `dpkg-scanpackages` 制备 deb 包（见总 README 环境说明章节）
