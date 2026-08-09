# Kubernetes 1.28 部署 · 华为云 SWR 私有仓库版

> 3 Master + 6 Worker | containerd | kube-vip HA | Calico | 证书 10 年
> 所有镜像从华为云 SWR（private 组织）拉取。与 online/offline/private-registry 平级、独立自包含。

## 与 Harbor 版区别

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

| 步骤 | 执行节点 | 命令 | 说明 |
|------|---------|------|------|
| 0 | 有网跳板机 | `./push-to-registry.sh --pull` | 部署前先推 11 镜像到 SWR（`--platform linux/amd64` 转单平台，SWR 拒多平台 OCI index）。仅需一次 |
| 1 | 全部 9 节点 | `./00-env-check.sh` | 环境检查（只读） |
| 2 | 全部 9 节点 | `./01-system-init.sh` | 系统初始化（swap/SELinux/内核/sysctl/arp_ignore） |
| 3 | 全部 9 节点 | `./02-install-containerd.sh` | 装 containerd + ★配 SWR private 认证（写 `config.toml` 的 `registry.configs.<host>.auth`，来源 `SWR_AK`/`SWR_LOGIN_KEY`） |
| 4 | 全部 9 节点 | `./03-install-k8s.sh` | 装 kubeadm/kubelet/kubectl |
| 5 | 仅 master1 | `./04-init-master1.sh` | kube-vip + kubeadm init（镜像从 SWR 拉），生成 `/etc/kubernetes/deploy/join.env` |
| — | master1 → 其余节点 | `scp /etc/kubernetes/deploy/join.env root@<节点>:/etc/kubernetes/deploy/` | 分发 join 凭据（一键版自动，分步需手动） |
| 6 | 仅 master2、master3（串行） | `./05-join-master.sh` | 加入控制平面，逐台等 etcd 健康 |
| 7 | 仅 node1~6（可并行） | `./06-join-worker.sh` | 加入 worker |
| 8 | 仅 master1 | `./07-install-calico.sh` | 装 Calico CNI（用本地 `manifests/calico.yaml`，VXLAN） |
| 9 | 每个 master（串行） | `./08-renew-certs.sh` | 证书续期 10 年 |
| 10 | 仅 master1 | `./09-verify.sh` | 20 项验收，全绿即成功 |

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
