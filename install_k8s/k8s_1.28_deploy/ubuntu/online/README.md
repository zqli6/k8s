# Kubernetes 1.28 部署 · Ubuntu 在线版

> 支持 1/3/5 个 Master 与任意数量 Worker。节点能上外网，镜像来自阿里云 + DaoCloud 加速，软件包来自阿里云 apt（deb）源。
> 适用 OS：**Ubuntu 22.04 LTS (jammy) / 24.04 LTS (noble)**，amd64。

## 与 CentOS online 版的关系

本目录是 `online/` 的 Ubuntu 版，**仅 `00/01/02/03` 四个脚本 + `config/cluster.env` 的软件包源不同**（apt 替代 yum）。`04-init-master1` 之后的脚本（join/calico/证书/验收）与 OS 无关，逻辑完全一致。

| 项 | CentOS online/ | 本目录 ubuntu/online/ |
|----|---------------|----------------------|
| 包管理 | yum / rpm | apt / deb |
| K8s 源 | kubernetes-new **rpm** 源 | kubernetes-new **deb** 源 |
| containerd 源 | docker-ce yum 源 | docker-ce apt 源（含 codename） |
| SELinux | 关闭 | 无（Ubuntu 用 AppArmor，无需关） |
| 防火墙 | firewalld | ufw |
| 时间同步 | chronyd | chrony |
| 版本锁定 | yum versionlock | apt-mark hold |
| 镜像 | 阿里云/DaoCloud/ghcr（**与 OS 无关，完全一致**） | 同左 |

## 快速开始

```bash
# 1. 修改 config/cluster.env 的 VIP、节点列表（UBUNTU_CODENAME 留空会自动探测）
# 2. 上传到 master1
scp -r ubuntu/online/ root@<master1>:/opt/k8s-deploy/

# 3. 一键部署
ssh root@<master1>
cd /opt/k8s-deploy/ubuntu/online/scripts && chmod +x *.sh
./deploy-all.sh
```

支持 `--from N`（断点续跑）、`--only N`、`--dry-run`。

## 分步部署命令速查

| 步骤 | 执行节点 | 命令 |
|------|---------|------|
| 0 | 全部节点 | `./00-env-check.sh` |
| 1 | 全部节点 | `./01-system-init.sh` |
| 2 | 全部节点 | `./02-install-containerd.sh` |
| 3 | 全部节点 | `./03-install-k8s.sh` |
| 4 | 仅 master1 | `./04-init-master1.sh` |
| 5 | 其余 master（串行） | `./05-join-master.sh` |
| 6 | worker（并行） | `./06-join-worker.sh` |
| 7 | 仅 master1 | `./07-install-calico.sh` |
| 8 | 每个 master（串行） | `./08-renew-certs.sh` |
| 9 | 仅 master1 | `./09-verify.sh` |

## 关键差异说明

- **codename 自动探测**：`config/cluster.env` 的 `UBUNTU_CODENAME=""` 留空时，脚本自动从 `/etc/os-release` 读取 `VERSION_CODENAME`（jammy/noble），用于拼接 docker-ce apt 源的发行版路径。手动指定可覆盖。
- **`SERVICE_CIDR` 已补**：CentOS 版 `cluster.env` 漏定义 `SERVICE_CIDR`（`04-init-master1.sh` 会用到），本目录已补为默认 `10.96.0.0/12`。
- **镜像无需重推**：容器镜像与宿主 OS 无关（只与 CPU 架构有关），Ubuntu 节点直接复用阿里云/DaoCloud/ghcr 同一批 amd64 镜像。

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `apt-get update` 报 GPG 错误 | keyring 未生成 | 确认 `02/03` 脚本里 `gpg --dearmor` 成功、`/etc/apt/keyrings/` 有对应文件 |
| `kubelet/kubeadm/kubectl` 装不上 | deb 版本号通配不匹配 | 阿里云 deb 源版本形如 `1.28.15-1.1`，脚本用 `=1.28.15-*` 匹配 |
| containerd 拉镜像 x509 报错 | 无（本版用公网镜像，无自签证书） | — |
| ufw 未关闭导致端口不通 | 01 脚本已 `ufw disable` | 手动 `ufw disable` |
