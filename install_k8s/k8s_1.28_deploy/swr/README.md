# Kubernetes 1.28 部署 · 华为云 SWR 私有仓库版

> 支持 1/3/5 个 Master 与任意数量 Worker。默认示例可按需修改；本次实测拓扑为 1 Master + 3 Worker。
> 所有镜像从华为云 SWR（private 组织）拉取。与 online/offline/private-registry 平级、独立自包含。

## 本次实验验证结果（1 Master + 3 Worker）

已在以下节点按本文档完成真实部署验证：

| 项目 | 结果 |
|------|------|
| 节点 | `192.168.104.231` master，`232/233/234` worker |
| OS / 架构 | CentOS 7.9 / x86_64 |
| Kubernetes | v1.28.15 |
| containerd | 1.6.33，四台均为运行时 |
| SWR private 认证 | containerd CRI 拉取成功 |
| kube-vip | v0.8.0，SWR 镜像拉取成功，VIP 可达 |
| Calico | v3.26.4，纯 VXLAN，4/4 Ready |
| 节点状态 | 4/4 Ready |
| API Server / etcd | 健康 |
| 证书 | 叶子证书已续期到 2036 年 |
| 最终验收 | 19 项通过，0 项失败 |

本次实验还修正了以下真实问题：containerd 默认 `config_path` 重复导致启动失败、SWR 用户名重复拼接、CentOS RPM kubelet 被旧 `/usr/local/bin/kubelet` systemd 单元覆盖、动态节点一键分发未调用、验收脚本误将未推送的 `busybox:latest` 当作 DNS 前置条件。完整多 master HA 尚未在本次 1 master 实验中验证，需使用 3 个或其他奇数 master 重新执行控制平面 join。

## kube-proxy Service 转发模式

当前方案在 `Kubernetes v1.28.15 + CentOS 7.9 + kernel 3.10` 上验证的是 IPVS：

```bash
KUBE_PROXY_MODE="ipvs"
```

新集群由 `scripts/04-init-master1.sh` 把该值写入 `KubeProxyConfiguration.mode`。可切换到 `iptables`，但必须先确认 `01-system-init.sh` 的内核和网络前置条件。`nftables` 不属于本方案在 Kubernetes 1.28/CentOS 7 的支持和验证范围，不能仅把值改成 `nftables`。

已有集群切换模式需要修改 `kube-system/kube-proxy` ConfigMap 后滚动重启其 DaemonSet；切换后用 `ipvsadm -Ln` 或 `iptables-save` 检查实际规则。

## 3 Master 高可用验证

当前 `1 Master + 3 Worker` 已实测通过。验证 3 Master 前必须先完整清理全部节点，不能把已加入集群的 worker 直接改成 master。将配置改为三个奇数 master，例如：

```bash
MASTER_NODES=(
    "192.168.104.231 master1"
    "192.168.104.232 master2"
    "192.168.104.233 master3"
)
WORKER_NODES=(
    "192.168.104.234 node1"
)
```

重新部署后必须确认：3 个控制平面节点均为 `Ready`；`etcd` 成员数为 3 且均为 started；`kube-apiserver`、`kube-controller-manager`、`kube-scheduler` 和 kube-vip 各有 3 个实例；VIP `192.168.104.200:6443` 可连接；Calico DaemonSet 覆盖全部节点。仅满足这些条件后，才能将结果记录为 3 Master HA 验证通过。


重新使用已有节点前，先阅读并按需执行 [`CLEANUP-README.md`](CLEANUP-README.md)。其中包含 kubeadm、kubelet、etcd、Calico、Flannel、CNI 网卡、iptables/IPVS 及旧配置的清理步骤。清理命令具有破坏性，请先确认节点无业务数据。

## 节点信息可编辑，且保留多节点机制

本目录不是固定的 3 Master + 6 Worker。编辑 `config/cluster.env` 中的 `MASTER_NODES` 和 `WORKER_NODES` 即可用于实验拓扑；脚本会自动重新派生 IP、主机名、节点总数和验收数量。例如单 master 测试：

```bash
MASTER_NODES=(
    "192.168.104.231 master1"
)
WORKER_NODES=(
    "192.168.104.232 node1"
    "192.168.104.233 node2"
    "192.168.104.234 node3"
)
```

需要验证高可用时，将 `MASTER_NODES` 改为 3 个或其他奇数 master，worker 仍可按需增减。不要把节点 IP 重复配置，也不要把 VIP 配成节点 IP。`00-env-check.sh` 会检查这些约束。


| 项 | Harbor | 本 SWR 版 |
|----|--------|----------|
| TLS | 常自签，需配 CA/skip_verify | 华为云受信证书，无需配 |
| 认证 | 用户名密码 | region@AK + 登录密钥 |
| 网络 | 内网 | 需访问 swr.<region>.myhuaweicloud.com |

## 镜像路径（已实际推送验证，11 个）

前缀 `swr.cn-southwest-2.myhuaweicloud.com/zqli/`，保留原仓库层级：

| 组件 | SWR 路径 |
|------|---------|
| K8s 核心 ×7 | `zqli/google_containers/{kube-apiserver,kube-controller-manager,kube-scheduler,kube-proxy,etcd,coredns,pause}` |
| kube-vip | `zqli/ghcr.io/kube-vip/kube-vip:v0.8.0` |
| calico ×3 | `zqli/docker.io/calico/{node,cni,kube-controllers}:v3.26.4` |

> 规则：阿里云去域名留 `google_containers/`，ghcr.io/docker.io 保留完整域名。
> `config/cluster.env` 镜像变量已对齐（`IMAGE_REPOSITORY=.../zqli/google_containers` 等）。

## 部署前置条件清单

本目录自包含，脚本 `source ../config/cluster.env`。部署前逐项确认：

- **SWR 凭据（必填）**：`config/cluster.env` 里
  - `SWR_AK`：Access Key ID（SWR 控制台 → 右上角「我的凭证」→ 访问密钥 AK/SK）。
  - `SWR_LOGIN_KEY`：用 AK/SK 生成的登录密钥（华为云「客户端上传 → 生成登录指令」）。
  - `SWR_USERNAME` 自动派生为 `<region>@<AK>`，`PRIVATE_REGISTRY` 自动派生为 `swr.<region>.myhuaweicloud.com/<org>`，无需手改。
- **region / org**：`SWR_REGION`（默认 `cn-southwest-2`）、`SWR_ORG`（默认 `zqli`）与你的 SWR 实际组织一致。
- **组织权限**：`SWR_PRIVATE="true"`（private 组织，默认）。private 时每个节点必须配 containerd 认证，脚本已处理；若组织设为公开可改 `false`。
- **网络**：9 节点能访问 `swr.<region>.myhuaweicloud.com`（无外网需先走代理）；VIP `192.168.104.200` 为同网段空闲 IP。
- **SSH 免密**：master1 能免密 `ssh root@` 其余 8 台。
- **节点/网段**：`MASTER_NODES` / `WORKER_NODES` / `CALICO_INTERFACE` 等同在线版，改配置只改本目录 `config/cluster.env`。
- **TLS**：SWR 用华为云受信 CA 证书，`REGISTRY_TLS_INSECURE=false` 保持默认，无需配 CA/skip_verify。

## 分步部署命令速查

| 0 | 有网跳板机（可选） | `./push-to-registry.sh --pull` | **可选**：仅当 SWR 缺少所需镜像时执行；镜像已存在时跳过。 |
| 1 | 当前配置中的全部节点 | `./00-env-check.sh` | 环境检查（只读） |
| 2 | 当前配置中的全部节点 | `./01-system-init.sh` | 系统初始化（swap/SELinux/内核/sysctl/arp_ignore） |
| 3 | 当前配置中的全部节点 | `./02-install-containerd.sh` | 安装/配置 containerd 和 SWR private 认证 |
| 4 | 当前配置中的全部节点 | `./03-install-k8s.sh` | 安装 kubeadm/kubelet/kubectl |
| 5 | 仅 master1 | `./04-init-master1.sh` | kube-vip + kubeadm init |
| — | master1 → 其余节点 | 分发 `join.env` | 一键版自动，分步执行需手动分发 |
| 6 | 其余 master（串行） | `./05-join-master.sh` | 仅当 `MASTER_COUNT > 1` 时执行 |
| 7 | 当前配置中的 worker（可并行） | `./06-join-worker.sh` | 加入 worker |
| 8 | 仅 master1 | `./07-install-calico.sh` | 安装 Calico CNI（VXLAN） |
| 9 | 每个 master（串行） | `./08-renew-certs.sh` | 证书续期 |
| 10 | 仅 master1 | `./09-verify.sh` | 按当前节点数量验收 |

> 一键：拷 `swr/` 到 master1 → `./deploy-all.sh`（自动分发 join.env、串行 join master、并行 join worker）。支持 `--from N`、`--only N`、`--dry-run`。
> 与 Harbor 版的唯一差异：认证走 SWR AK/登录密钥、且写在 `config.toml` 的 `registry.configs`（见下）；其余步骤编号与逻辑一致。

## 关键：private 组织认证（为什么能直接部署）

控制面/kube-vip 是 static pod，kubelet 直接拉、**不认 imagePullSecrets**。private SWR 必须在每个节点 containerd 配认证——`02-install-containerd.sh` 会：

1. 写 `/etc/containerd/certs.d/<host>/hosts.toml`：只管路由与 `capabilities = ["pull","resolve"]`。**containerd 的 hosts.toml 不支持 auth 字段**（写了会被静默忽略）。
2. 把认证写进 `/etc/containerd/config.toml` 的 `[plugins."io.containerd.grpc.v1.cri".registry.configs."<host>".auth]`（`username`=`<region>@<AK>`、`password`=登录密钥），并 `chmod 600`。

这是 SWR private+kubeadm 最易翻车处（认证放错文件就 ImagePullBackOff），脚本已解决。

## 部署参数详解 / 最终 YAML 位置

仓库/网段/proxy/域名/证书等所有配置项的「改哪里 + 最终落地 YAML 位置」，见顶层 `../README.md` 的「配置详解 FAQ」章节。

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| static pod ImagePullBackOff | private 未配 containerd 认证 | 确认 SWR_AK/LOGIN_KEY 已填、02 已跑 |
| push 报 Invalid image, fail to parse manifest.json | SWR 拒多平台 OCI index | `--platform linux/amd64` 转单平台 |
| 节点连不上 SWR | 无外网/未走代理 | 确认能访问 swr.<region>.myhuaweicloud.com |
| unauthorized | AK/密钥错或过期 | SWR 控制台重新生成登录指令 |
