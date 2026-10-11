# Kubernetes 1.28 高可用集群 · 部署与网络技术参考

> 支持 1/3/5 个 Master 与任意数量 Worker。每套方案均在自己的 `config/cluster.env` 中配置节点；单 Master 不部署 kube-vip，多 Master 使用 VIP + kube-vip。

## 操作系统适用范围（先读）

本仓库当前包含两套**独立且不可混用**的操作系统方案：

| 方案目录 | 适用系统 | 包管理/运行时 | 当前状态 | 不适用场景 |
|---|---|---|---|---|
| `redhat/online/`、`redhat/offline/`、`redhat/swr/` | **CentOS 7.9 x86_64** | yum/rpm，containerd.io | 已有验证方案 | Ubuntu、Debian、CentOS Stream、Rocky/AlmaLinux、ARM |
| `ubuntu/online/` | **Ubuntu 24.04 LTS (noble) x86_64** | apt/deb，Ubuntu `containerd` 2.2.x | 已在 3 Master + 1 Worker 环境验证 | Debian、Ubuntu 以外系统、ARM |
| `ubuntu/offline/` | **Ubuntu 24.04 LTS (noble) x86_64** | 本地 deb 源，Ubuntu `containerd` 2.2.x | 已在 3 Master + 1 Worker 环境完成离线验证 | Debian、Ubuntu 以外系统、ARM |
| `ubuntu/swr/` | Ubuntu apt/deb 方案 | 需按 SWR 仓库权限配置认证 | 待在具备有效 SWR 凭据/公开仓库的环境验证 | 不能直接拿顶层 `swr/` 替代 |

> **`redhat/` 下的 `online/`、`offline/`、`swr/` 是 CentOS 7.9 方案。** 它们使用 `yum`、`rpm`、`/etc/yum.repos.d`，不可直接在 Ubuntu 或 Debian 上运行。
>
> **Ubuntu 离线包不能用于 Debian。** `ubuntu/offline/packages/` 中的 deb 包按 Ubuntu 24.04 noble 的依赖链制备；镜像 tar 可在同为 amd64 的系统间复用，但 deb 包必须按目标发行版重新制备。
>
> Debian 当前没有经过验证的专用目录；不要把 `ubuntu/` 改名或宣称为 Debian 通用方案。

## 下载离线包
*先克隆本目录，然后需拉取images及依赖packages(不一定需要),对应目录中有拉取方法*
```
.
├── docs
├── README.md
├── redhat
│   ├── offline
│   │   ├── images
│   │   │   └── README.md
│   │   ├── packages
│   │   │   └── README.md
└── ubuntu
    ├── offline
    │   ├── images
    │   │   └── README.md
    │   ├── packages
    │   │   └── README.md
```
```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.9.2
```
复制出文件可参考[Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/mlda3n2mcphvzo2o#wpXxl)
```
docker create --name temp-extract \
  swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.9.2 echo
docker cp temp-extract:/data/k8s-1.20.11-offline.tar ./host/
docker rm temp-extract
```
```
ctr image mount swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.9.2 /mnt/
cp /mnt/ ./
ctr image unmount /mnt/
```



## 集群拓扑

| 角色 | 主机名 | IP |
|------|--------|-----|
| Master(×3) | master1/2/3 | 192.168.104.104 / 137 / 97 |
| Worker(×6) | node1~6 | 192.168.104.132/180/134/103/90/162 |
| VIP(kube-vip) | k8s-api | 192.168.104.200 |

## 技术栈

| 组件 | 版本 | 来源 |
|------|------|------|
| Kubernetes | v1.28.15 | 阿里云 kubernetes-new 源 |
| containerd（CentOS 方案） | 1.6.33 | 阿里云 docker-ce 源 |
| containerd（Ubuntu 方案） | Ubuntu apt 当前候选版本；24.04 实测 2.2.1 | Ubuntu apt 源 |
| kube-vip | v0.8.0 | ghcr.io（ARP 静态 Pod） |
| Calico | v3.26.4 | VXLAN 数据面（DaoCloud 加速） |
| 证书 | 10 年 | update-kubeadm-cert.sh（openssl 重签） |
| kube-proxy | IPVS 模式 | 11 种调度算法 |

---

## 部署方案

本仓库提供 **CentOS 7.9 三套平级方案 + Ubuntu 系列**，按场景选用。顶层三套方案就是 CentOS 方案，请勿在 Ubuntu/Debian 上执行：

| 目录 | 场景 | OS | 镜像来源 |
|------|------|----|---------|
| [`redhat/online/`](redhat/online/README.md) | **CentOS 在线部署**（节点能上外网） | CentOS 7.9 x86_64 | 阿里云 + DaoCloud |
| [`redhat/offline/`](redhat/offline/README.md) | **CentOS 离线部署**（air-gap 无外网） | CentOS 7.9 x86_64 | 本地 rpm + tar |
| [`redhat/swr/`](redhat/swr/README.md) | **CentOS 华为云 SWR** | CentOS 7.9 x86_64 | SWR private 组织 |
| [`ubuntu/`](ubuntu/README.md) | **Ubuntu 系列**（online/offline/SWR） | Ubuntu 22.04/24.04 x86_64；offline 已按 Ubuntu 24.04 noble 验证 | 阿里云 / 本地 / SWR |

每套目录结构（自包含）：`config/cluster.env` + `scripts/*.sh` + `tools/` + `manifests/`。

### 目录自包含与节点配置

每套方案只使用自身目录下的 `config/cluster.env`、`tools/` 和 `manifests/`；根目录不再保留运行时配置。单 Master 不部署 kube-vip，多 Master 使用 VIP + kube-vip。节点增减只修改对应方案的节点数组。


---

## 快速开始（在线版一键部署）

```bash
# 1. 修改 redhat/online/config/cluster.env 中的 VIP、节点列表和 kube-proxy 模式
# 2. 上传 redhat/online/ 目录到 master1；该 scp 命令最终生成 /opt/k8s-deploy/online/
scp -r redhat/online/ root@192.168.104.104:/opt/k8s-deploy/

# 3. 一键部署
ssh root@192.168.104.104
cd /opt/k8s-deploy/online/scripts && chmod +x *.sh
./deploy-all.sh
```

支持 `--from N`（断点续跑）、`--only N`、`--dry-run`。

---

## 完全离线介质如何自行准备

完整镜像清单、Ubuntu deb、CentOS 7 RPM、Calico manifest、仓库元数据、SHA-256 清单、打包和真正断网验收流程见：

- **[`docs/Kubernetes完全离线介质制备与验收指南.md`](docs/Kubernetes完全离线介质制备与验收指南.md)**

当前基准完整功能集包含 7 个 Kubernetes 核心镜像、3 个 Calico 镜像和 1 个 kube-vip 镜像；镜像 tar 可在版本与 CPU 架构相同的 Ubuntu/CentOS 间复用，但 deb/rpm 必须按目标发行版重新制备。新增 Ingress、MetalLB、CSI、监控等组件时，还要把它们各自的镜像和清单加入离线介质。

---

## 容器运行时与 Kubernetes 镜像仓库配置

**[`docs/容器运行时与Kubernetes镜像仓库配置指南.md`](docs/容器运行时与Kubernetes镜像仓库配置指南.md)** — 区分 containerd/Docker 的仓库连接、TLS、密码认证，以及 kubeadm、Calico、kube-vip 的镜像配置位置；同时逐项对应本项目脚本的实现。

---

## 网络深度手册（必读）

**[`docs/Kubernetes网络原理与实践指南.md`](docs/Kubernetes网络原理与实践指南.md)** — 941 行、20 个 mermaid 图的完整 K8s 网络技术文档：

- OSI 七层模型与 K8s（什么是 L2/L3/L4/L7、为什么 VIP ping 不通）
- kube-proxy 三种模式详解（iptables/IPVS/nftables 数据流、kube-ipvs0 网卡、怎么查/改/风险）
- Service 四种类型流量路径（ClusterIP/NodePort/LoadBalancer/ExternalName + externalTrafficPolicy）
- Pod 间通信（同主机 vs 跨主机、veth pair、cni0/cali/lxc）
- CNI 插件对比（Flannel/Calico/Cilium 每种模式精确路径 + **proxy ARP 机制对比**）
- 外部流量完整链路（Ingress + MetalLB + IPVS 端到端 8 步）
- 配置修改操作手册（每项两种方式：脚本 + 不依赖脚本直接改）
- 故障排查 + 3 个真机实测事故复盘
- 附录：虚拟网卡速查表 + 官方文档链接

> 该文档通过 tech-deploy-doc skill 的三重校验（技术正确性+来源真实性+小白可读性），所有关键事实 ≥3 个独立来源交叉核实。

---

## 证书 10 年

| 方式 | 指定位置 | 适用 |
|------|---------|------|
| **A. openssl 重签（默认）** | `update-kube-cert.sh --days 3650` | 离线友好，只需 openssl |
| B. 重编译 kubeadm | 源码 `constants.go` 的 `CertificateValidity` 常量 | 需 Go 环境 |
| C. v1beta4 字段 | `certificateValidityPeriod: 87600h` | **仅 v1.31+，v1.28 不可用** |

详见各套目录的 `08-renew-certs.sh`。

---

## 注意事项

- **阿里云源**：1.28 必须用 `kubernetes-new` 新路径（旧源已冻结）
- **Pod CIDR**：`10.244.0.0/16`（Calico 默认 192.168.0.0/16 会与宿主网段冲突）
- **kube-vip**：仅多 Master 部署；单 Master 使用 master1 IP 作为 controlPlaneEndpoint，不生成 kube-vip static Pod。
- **k8s-api hosts 别名**：每次系统初始化都会重建受管区域；单 Master 指向 master1 IP，多 Master 指向 VIP。
- **kube-vip**：v1.28 多 Master 模式挂载 `/etc/kubernetes/admin.conf`（v1.29+ 才有 super-admin.conf）
- **IPVS + MetalLB**：必须 `arp_ignore=1 / arp_announce=2`（01 脚本已配）

---

## 真机验证踩坑记录（已全部固化进脚本）

| # | 坑 | 现象 | 修复 |
|---|---|------|------|
| 1 | `((VAR++))` + set -e | 检查脚本自杀 | 改 `$((VAR+1))` |
| 2 | 阿里云旧源冻结 | 1.28 装不上 | kubernetes-new 新路径 |
| 3 | raw.githubusercontent 被墙 | Calico manifest 超时 | gitee + ghproxy |
| 4 | docker.io 被墙 | Calico 镜像拉不到 | DaoCloud 加速 |
| 5 | Calico VXLAN/BGP 冲突 | BIRD 语法错 NotReady | backend=vxlan + 去 bird 探针 |
| 6 | Calico 网卡选错 kube-ipvs0 | 多节点 IP 冲突崩溃 | interface= 精确网卡 |
| 7 | MetalLB ARP 泄漏 | 多节点抢答 VIP | arp_ignore=1 |
| 8 | SWR 拒多平台 OCI index | kube-vip push 失败 | --platform linux/amd64 |
| 9 | containerd hosts.toml 无 auth | SWR private 拉不到 | CentOS 1.6 可用旧式 auth；Ubuntu 2.x 必须 `crictl pull` 实测，必要时预拉 static Pod 镜像/为普通 Pod 配 `imagePullSecret` |

---

## 部署环境说明

### 当前环境（本套脚本默认）

| 项 | 值 |
|----|-----|
| OS | CentOS 7.9.2009 (x86_64) |
| 内核 | 3.10.0-1160.el7 |
| 架构 | amd64 (x86_64) |
| 包管理 | yum |
| 容器运行时 | containerd 1.6.x（阿里云 docker-ce 源） |
| K8s | v1.28.15（阿里云 kubernetes-new rpm 源） |
| 节点数 | 3 master + 6 worker（数组驱动，改 cluster.env 增减） |

### 如果想在 Debian/Ubuntu 系统安装

本套脚本使用 `yum` 安装软件包。迁移到 Debian/Ubuntu 需改以下几处：

| 改什么 | 从 | 改成 |
|--------|-----|------|
| **01-system-init.sh** | `yum install -y conntrack-tools...` | `apt-get install -y conntrack socat ipset ipvsadm chrony...` |
| **02-install-containerd.sh** | `yum-config-manager --add-repo` + docker-ce yum 源 | `curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \| gpg --dearmor -o /etc/apt/keyrings/docker.asc` + apt 源 |
| **03-install-k8s.sh** | kubernetes-new rpm 源 (`baseurl=.../rpm/`) | kubernetes-new deb 源 (`deb [signed-by=...] .../deb/ /`) |
| **cluster.env** | `KUBE_REPO_URL=.../rpm`、`DOCKER_CE_REPO=.../centos/...` | 改成 deb 源 URL |
| **01** SELinux 段 | `setenforce 0` + `/etc/selinux/config` | 删除（Debian/Ubuntu 默认无 SELinux） |
| **01** 防火墙段 | `systemctl stop firewalld` | `ufw disable`（若有） |
| **版本锁定** | `yum versionlock` | `apt-mark hold kubelet kubeadm kubectl` |

**阿里云 Debian/Ubuntu K8s 源**（1.28）：

```bash
# GPG key
curl -fsSL https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# apt 源
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update && apt-get install -y kubelet=1.28.15-* kubeadm=1.28.15-* kubectl=1.28.15-*
apt-mark hold kubelet kubeadm kubectl
```

**containerd apt 源**（阿里云 docker-ce）：

```bash
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | tee /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y containerd.io
```

其余逻辑（kube-vip/Calico/证书/验收）不变——这些不依赖包管理器。

### 如果想在 ARM (aarch64) 系统安装

| 改什么 | 说明 |
|--------|------|
| **镜像架构** | 所有镜像拉取/导出必须指定 `--platform linux/arm64`；离线 tar 需重新制备（当前 images/ 是 amd64） |
| **二进制** | kubeadm/kubelet/kubectl 下载路径改 `dl.k8s.io/release/v1.28.15/bin/linux/arm64/` |
| **containerd** | 用 `containerd-1.6.x-linux-arm64.tar.gz`（GitHub releases） |
| **CNI plugins** | `cni-plugins-linux-arm64-vX.Y.Z.tgz` |
| **kube-vip** | `ghcr.io/kube-vip/kube-vip:v0.8.0` 是多架构镜像，arm64 能拉；但 SWR 推送时需 `--platform linux/arm64` |
| **Calico** | `docker.io/calico/{node,cni,kube-controllers}` 均有 arm64 variant |
| **cluster.env** | 无需改（架构透明） |
| **离线 images/** | 必须用 arm64 机器重新 `ctr pull --platform linux/arm64` + export |

> ⚠️ CentOS 7 的 arm64 版（AltArch）已 EOL 且生态差，ARM 建议用 Ubuntu 22.04/Rocky 9。
