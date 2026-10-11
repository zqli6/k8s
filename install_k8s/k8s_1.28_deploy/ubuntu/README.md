# Kubernetes 1.28 部署 · Ubuntu 系列

> 与 RedHat/CentOS 系列（`redhat/online/`、`redhat/offline/`、`redhat/swr/`）平级的 Ubuntu 部署方案。支持 **Ubuntu 22.04 LTS (jammy) / 24.04 LTS (noble)**，amd64。
> 所有软件源使用**中国境内可访问**的阿里云 / DaoCloud / gitee 镜像，容器镜像与宿主 OS 无关（仅与 CPU 架构有关）。

## 三个子方案

| 目录 | 场景 | 软件包源 | 镜像来源 |
|------|------|---------|---------|
| [`online/`](online/README.md) | 在线部署（节点能上外网） | 阿里云 apt（deb） | 阿里云 + DaoCloud + ghcr |
| [`offline/`](offline/README.md) | 离线部署（air-gap） | 本地 deb 源 | 本地 tar 导入（复用 CentOS amd64 tar） |
| [`swr/`](swr/README.md) | 华为云 SWR 仓库 | 阿里云 apt（deb） | SWR（**复用 CentOS 版已推镜像，无需重推**） |

每个子方案自包含：`config/cluster.env + scripts/*.sh + tools/ + manifests/`，流程与 CentOS 版一致（`00-env-check → 01-system-init → 02-containerd → 03-k8s → 04-init-master1 → ... → 09-verify`）。

## 与 CentOS 版的差异

Ubuntu 版**只重写了 `00/01/02/03` 四个脚本 + `cluster.env` 的软件包源**，其余（`04-init-master1` 之后的 kubeadm init/join、kube-vip、Calico、证书续期、验收）与 OS 无关，逻辑完全一致。

| 项 | CentOS | Ubuntu |
|----|--------|--------|
| 包管理 | yum / rpm | apt / deb |
| K8s 源 | kubernetes-new **rpm** | kubernetes-new **deb** |
| containerd 源 | docker-ce yum | docker-ce apt（含 codename） |
| SELinux | 关闭 | 无（AppArmor） |
| 防火墙 | firewalld | ufw |
| 时间同步 | chronyd | chrony |
| 版本锁定 | yum versionlock | apt-mark hold |
| 离线本地源 | rpm + repodata | deb + Packages.gz |

## 版本识别

`cluster.env` 的 `UBUNTU_CODENAME=""` 留空时，脚本自动从 `/etc/os-release` 探测 `VERSION_CODENAME`（jammy/noble）；手动指定可覆盖。同一套脚本同时兼容 22.04 和 24.04。

## 快速开始

```bash
# 在线版（最简）
scp -r ubuntu/online/ root@<master1>:/opt/k8s-deploy/
ssh root@<master1>
cd /opt/k8s-deploy/ubuntu/online/scripts && chmod +x *.sh
./deploy-all.sh --dry-run
./deploy-all.sh
```

SWR 版先确认 `cluster.env` 的 `SWR_AK` / `SWR_LOGIN_KEY`；离线版先在有网 Ubuntu 上跑 `fetch-resources.sh` 制备 deb 离线包。

## 注意事项

- **镜像不用重推**：SWR 的 K8s/Calico/kube-vip 镜像与 CentOS 版是同一批 amd64 镜像。
- **SERVICE_CIDR 已补**：CentOS 版 `cluster.env` 漏定义 `SERVICE_CIDR`，Ubuntu 版已补为 `10.96.0.0/12`。
- **源全部境内可达**：阿里云（kubernetes-new deb / docker-ce）、DaoCloud（Calico 镜像）、gitee（Calico manifest）。
