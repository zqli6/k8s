# Kubernetes 1.28 在线部署版（阿里云仓库）

> 支持 1/3/5 个 Master 与任意数量 Worker；本目录只提供默认示例，实际节点以 `config/cluster.env` 为准。
> **镜像与软件包全部走阿里云公网源，节点需能访问外网**

本目录与 `offline/`（离线）、`private-registry/`（私有仓库）平级，各自独立。本套已在 9 台 CentOS 7.9 真机完整跑通、验收 20/20。

## 控制面模式

`MASTER_COUNT=1` 时使用 master1 IP 作为控制面端点，不部署 kube-vip；`MASTER_COUNT>1` 时使用 VIP 并部署 kube-vip。`KUBE_PROXY_MODE` 独立控制 Service 转发模式。


| 角色 | 主机名 | IP |
|------|--------|-----|
| Master | master1 | 192.168.104.104 |
| Master | master2 | 192.168.104.137 |
| Master | master3 | 192.168.104.97 |
| Worker | node1~node6 | 192.168.104.132/180/134/103/90/162 |
| VIP（kube-vip） | k8s-api | 192.168.104.200 |

## 技术栈与来源

| 组件 | 版本 | 来源 |
|------|------|------|
| Kubernetes | v1.28.15 | 阿里云 kubernetes-new 源 |
| containerd | 1.6.x | 阿里云 docker-ce 源 |
| kube-vip | v0.8.0 | ghcr.io（ARP 模式静态 Pod） |
| Calico | v3.26.4 | manifest 走 gitee 镜像，镜像走 DaoCloud 加速 |
| 证书 | 10 年 | update-kubeadm-cert.sh（openssl 重签） |

## 目录结构

```
online/
├── README.md                    # 本文件
└── scripts/
    ├── 00-env-check.sh          # 全部节点｜环境检查（只读）
    ├── 01-system-init.sh        # 全部节点｜系统初始化（swap/SELinux/内核/sysctl/arp_ignore）
    ├── 02-install-containerd.sh # 全部节点｜装 containerd（阿里云源）
    ├── 03-install-k8s.sh        # 全部节点｜装 kubeadm/kubelet/kubectl（阿里云源）
    ├── 04-init-master1.sh       # 仅 master1｜kube-vip + kubeadm init
    ├── 05-join-master.sh        # 仅 master2/3｜加入控制平面（串行）
    ├── 06-join-worker.sh        # 仅 node1~6｜加入 worker（可并行）
    ├── 07-install-calico.sh     # 仅 master1｜装 CNI（VXLAN）
    ├── 08-renew-certs.sh        # 每个 master｜证书续期 10 年（串行）
    ├── 09-verify.sh             # 仅 master1｜全量验收（20 项）
    └── deploy-all.sh            # 仅 master1｜一键部署（SSH 分发）
```

> 变量集中在 `config/cluster.env`。改集群信息（节点、VIP、版本）只改此文件；节点增减改 `MASTER_NODES` / `WORKER_NODES` 两个列表即可。

## 快速开始

### 方式一：一键部署（推荐）

```bash
# 1. 编辑 config/cluster.env，确认 VIP、节点列表、网卡正确
# 2. 整个 online/ 目录上传到 master1
scp -r online/ root@192.168.104.104:/opt/k8s-deploy/
# 3. 在 master1 一键部署
ssh root@192.168.104.104
cd /opt/k8s-deploy/online/scripts && chmod +x *.sh
./deploy-all.sh
```

`deploy-all.sh` 按 phase 编排：环境检查 → 系统初始化 → containerd → K8s 组件 → master1 init（单 Master 直连 / 多 Master 使用 kube-vip）→ 其余 master 串行 join → worker 并行 join → Calico → 证书 → 验收。支持 `--from N`（断点续跑）、`--only N`、`--dry-run`。

### 方式二：分步执行

按脚本编号顺序，注意每步的执行节点（见上方目录结构注释）。master1 init 后，join.env 会生成在 `/etc/kubernetes/deploy/`，需 scp 到其他节点。

## 部署前置条件清单

部署前逐项确认（在线版脚本 `source ../config/cluster.env`，改配置只改本目录 `config/cluster.env` 一处）：

- **网络**：当前配置中的全部节点能访问外网（阿里云/DaoCloud/ghcr.io）。仅多 Master 需要 VIP；单 Master 不部署 kube-vip，`k8s-api` 指向 master1。
- **SSH 免密**：master1 能免密 `ssh root@` 其余 8 台（`deploy-all.sh` 靠这个分发）。
- **`config/cluster.env` 必确认项**：
  - `MASTER_NODES` / `WORKER_NODES`：节点 IP+主机名列表（增减节点只改这两处，master 数量须为奇数）。
  - `VIP`：kube-vip 虚拟 IP，须空闲。
  - `CALICO_INTERFACE`：多网卡或探测不准时填具体网卡名（如 `ens192`）；单网卡留空自动探测。
  - `KUBEVIP_INTERFACE`：同理，留空自动探测默认路由网卡。
  - `POD_CIDR` / `SERVICE_CIDR`：默认 `10.244.0.0/16` / `10.96.0.0/12`，与宿主网段不冲突即可（勿用 `192.168.0.0/16`）。
  - `KUBE_VERSION`：默认 `1.28.15`，改版本前确认阿里云 kubernetes-new 有对应 RPM。
- **系统**：CentOS 7.9、每节点 ≥2C4G、时间同步（脚本不装 NTP）。
- 版本/仓库地址等其余变量一般无需改，含义见顶层 `../README.md` 的「配置详解 FAQ」。

## 分步部署命令速查

整个 `online/` 目录传到 master1 后，在 `online/scripts/` 目录里按下表执行。

| 步骤 | 执行节点 | 命令 | 说明 |
|------|---------|------|------|
| 1 | 当前配置中的全部节点 | `./00-env-check.sh` | 环境检查（只读，不改系统） |
| 2 | 当前配置中的全部节点 | `./01-system-init.sh` | 系统初始化（swap/SELinux/内核模块/sysctl/hosts） |
| 3 | 当前配置中的全部节点 | `./02-install-containerd.sh` | 装 containerd（阿里云 docker-ce 源） |
| 4 | 当前配置中的全部节点 | `./03-install-k8s.sh` | 装 kubeadm/kubelet/kubectl（阿里云 kubernetes-new 源） |
| 5 | 仅 master1 | `./04-init-master1.sh` | 单 Master 直连；多 Master 生成 kube-vip 并使用 VIP |
| — | master1 → 其余节点 | `scp /etc/kubernetes/deploy/join.env root@<节点>:/etc/kubernetes/deploy/` | 分发 join 凭据（一键版自动做，分步需手动） |
| 6 | 其余 master（串行） | `./05-join-master.sh` | `MASTER_COUNT>1` 时加入控制平面 |
| 7 | 当前配置中的 worker（可并行） | `./06-join-worker.sh` | 加入 worker |
| 8 | 仅 master1 | `./07-install-calico.sh` | 装 Calico CNI（VXLAN） |
| 9 | 每个 master（串行） | `./08-renew-certs.sh` | 证书续期 10 年 |
| 10 | 仅 master1 | `./09-verify.sh` | 20 项验收，全绿即成功 |

> 一键等价：master1 上 `./deploy-all.sh`（自动分发 join.env、串行 join master、并行 join worker）。支持 `--from N` 断点续跑、`--only N`、`--dry-run`。

## 证书 10 年在哪里指定

K8s v1.28 叶子证书默认 1 年、CA 默认 10 年。本套用 `08-renew-certs.sh` 调用 `update-kubeadm-cert.sh`，**10 年在 `--days 3650`（或环境变量 `KUBE_CERT_DAYS`）指定**：

```bash
KUBE_CERT_DAYS=3650 bash update-kubeadm-cert.sh --cri containerd --days 3650
```

原理：用现有 CA 私钥经 openssl 重签所有叶子证书，脚本内部自动 `crictl` 重启控制面。每个 master 各跑一次（脚本已在 deploy-all 的 Phase 8 编排为串行 + etcd 健康校验）。

> 另两种方式（文档备查）：① 重编译 kubeadm 改源码常量 `CertificateValidity`（需 Go 环境）；② v1beta4 字段 `certificateValidityPeriod`——**仅 K8s v1.31+ 支持，v1.28 用不了**。

## 已知坑与规避（均在真机验证并固化进脚本）

| 坑 | 现象 | 脚本已规避 |
|----|------|-----------|
| 阿里云旧源冻结 | 1.28 装不上 | 用 kubernetes-new 新路径 |
| Calico manifest 被墙 | raw.githubusercontent 超时 | 走 gitee 镜像 + ghproxy 兜底 |
| Calico 镜像 docker.io 拉不到 | ImagePullBackOff | 走 DaoCloud 加速源 |
| Calico VXLAN/BGP 冲突 | BIRD 语法错、节点 NotReady | backend=vxlan + CLUSTER_TYPE=k8s + 去 bird 探针 |
| Calico 网卡选错 | 探测到 kube-ipvs0 上 Service IP、calico 崩溃 | IP_AUTODETECTION_METHOD=interface=网卡名 |
| MetalLB/IPVS ARP 泄漏 | 多节点抢答 LoadBalancer VIP 的 ARP | 01 脚本设 arp_ignore=1 / arp_announce=2 |

## 验收

`09-verify.sh` 检查 20 项：9 节点 Ready、3 控制面组件各 3 副本、etcd 3 成员、kube-vip VIP 可达、Calico 就绪、Pod CIDR 无冲突、DNS 解析、证书 ≥9 年等。全绿即部署成功。


## 部署参数详解 / 最终 YAML 位置

仓库地址、仓库密码、kube-proxy 模式（查/改/影响）、自定义 Service 域名、Pod/Service/Calico 三网段、长期证书原理——每项的「改哪里 + 部署后最终落地在集群哪个 YAML」，统一见顶层 `../README.md` 的「配置详解 FAQ」章节。
