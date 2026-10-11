# Kubernetes 1.28 部署 · Ubuntu + 华为云 SWR 版

> 支持 1/3/5 个 Master 与任意数量 Worker。所有镜像从华为云 SWR 拉取，软件包来自阿里云 apt（deb）源。
> 适用 OS：**Ubuntu 22.04 LTS (jammy) / 24.04 LTS (noble)**，amd64。

## 镜像仓库配置总指南

以下内容统一见 [`../../docs/容器运行时与Kubernetes镜像仓库配置指南.md`](../../docs/容器运行时与Kubernetes镜像仓库配置指南.md)：

- containerd 与 Docker 分别怎样配置仓库、CA 和密码；
- kubeadm 核心镜像、Calico、kube-vip、普通 Pod 分别在哪里指定镜像；
- 手工安装命令与本目录 `cluster.env`、`02`、`04`、`07` 脚本之间的对应关系；
- containerd 1.6 与 2.x 的认证差异，以及 static Pod 不能直接引用 `imagePullSecret` 的处理方式。

> ⚠️ Ubuntu 24.04 当前使用 containerd 2.2.x。旧式 `io.containerd.grpc.v1.cri.registry.configs.*.auth` 曾在 strict mode 下被忽略，不能仅凭配置文件里出现用户名/密码就声称认证成功。必须用 `crictl pull` 实测；当前可靠兜底为使用显式凭据预拉镜像，普通工作负载则使用 `imagePullSecret`。

## 与 RedHat SWR 版的关系

本目录是 `redhat/swr/` 的 Ubuntu 版。**镜像完全复用 CentOS 版已推送的同一批 amd64 镜像，无需重新推送**（容器镜像与宿主 OS 无关，只与 CPU 架构有关）。只有 `00/01/02/03` 四个脚本 + `cluster.env` 的软件包源改为 apt，其余（04-09、push-to-registry、kube-vip、证书）与 OS 无关。

| 项 | CentOS swr/ | 本目录 ubuntu/swr/ |
|----|------------|-------------------|
| 包管理 | yum / rpm | apt / deb |
| K8s 源 | kubernetes-new rpm 源 | kubernetes-new deb 源 |
| containerd 源 | docker-ce yum 源 | docker-ce apt 源（含 codename） |
| 防火墙 | firewalld | ufw |
| 时间同步 | chronyd | chrony |
| 版本锁定 | yum versionlock | apt-mark hold |
| 镜像 | SWR（**与 OS 无关，直接复用**） | 同左 |
| Calico manifest | 本地文件 | gitee 国内源下载（Ubuntu 可外网） |

## 前置条件

1. `config/cluster.env` 填 `SWR_AK` 和 `SWR_LOGIN_KEY`（华为云「我的凭证 → 访问密钥 → 生成登录指令」）。
2. SWR 组织里已有 K8s 1.28 镜像（即 CentOS 版已推送过）；若没有，先执行 `./push-to-registry.sh --pull`。
3. 节点能访问 `swr.<region>.myhuaweicloud.com` 和阿里云/gitee 国内源。
4. master1 能免密 ssh 其余节点。

## 快速开始

```bash
scp -r ubuntu/swr/ root@<master1>:/opt/k8s-deploy/
ssh root@<master1>
cd /opt/k8s-deploy/ubuntu/swr/scripts && chmod +x *.sh
./deploy-all.sh --dry-run   # 先看计划
./deploy-all.sh             # 全量部署
```

## 分步命令速查

| 步骤 | 执行节点 | 命令 |
|------|---------|------|
| 0 | 有网跳板机（可选） | `./push-to-registry.sh --pull`（SWR 缺镜像时才跑） |
| 1 | 全部节点 | `./00-env-check.sh` |
| 2 | 全部节点 | `./01-system-init.sh` |
| 3 | 全部节点 | `./02-install-containerd.sh`（含 SWR private 认证） |
| 4 | 全部节点 | `./03-install-k8s.sh` |
| 5 | 仅 master1 | `./04-init-master1.sh` |
| 6 | 其余 master（串行） | `./05-join-master.sh` |
| 7 | worker（并行） | `./06-join-worker.sh` |
| 8 | 仅 master1 | `./07-install-calico.sh` |
| 9 | 每个 master（串行） | `./08-renew-certs.sh` |
| 10 | 仅 master1 | `./09-verify.sh` |

## 关键：private 组织认证

控制面和 kube-vip 是 static Pod，不能直接引用 Kubernetes API 中的 `imagePullSecret`。本目录的 `02-install-containerd.sh` 会配置 `certs.d` 的仓库路由/TLS，并保留旧式 `registry.configs.<host>.auth` 兼容逻辑；但 Ubuntu containerd 2.2.x 曾实测忽略该旧式认证段。因此部署前必须执行 `crictl pull` 端到端验证。若返回 401，应使用显式凭据在各节点预拉核心/pause/kube-vip，普通 Calico/业务 Pod 则配置 `imagePullSecret`；不要把旧式 auth 描述为 containerd 2.2 的通用解决方案。详见镜像仓库配置总指南。

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| static pod ImagePullBackOff | private 未配 containerd 认证 | 确认 SWR_AK/LOGIN_KEY 已填、02 已跑 |
| 镜像拉不到 | SWR 组织里没有该镜像 | `push-to-registry.sh --pull` 推送 |
| Calico manifest 下载失败 | gitee 不可达 | 把 `swr/manifests/calico.yaml` 复制到本目录 manifests/ |
