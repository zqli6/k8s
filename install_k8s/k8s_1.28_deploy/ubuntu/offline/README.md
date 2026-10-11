# Kubernetes 1.28 部署 · Ubuntu 离线版（air-gap）

> 支持 1/3/5 个 Master 与任意数量 Worker。完全离线部署：软件包来自本地 deb 源，镜像来自本地 tar 导入。
> 适用 OS：**Ubuntu 22.04 LTS (jammy) / 24.04 LTS (noble)**，amd64。

## 与 RedHat offline 版的关系

本目录是 `redhat/offline/` 的 Ubuntu 版。容器镜像层通常与宿主 OS 无关，但复用 tar 必须同时满足：CPU 架构、Kubernetes/Calico/kube-vip 版本一致，且 tar 内的**完整镜像引用名**与本目录 manifest/config 一致。当前 Red Hat `calico.tar` 使用 `docker.io/calico/*` 名称，而本目录 `calico.yaml` 使用 `m.daocloud.io/docker.io/calico/*`；复制后必须按 [`../../docs/Kubernetes完全离线介质制备与验收指南.md`](../../docs/Kubernetes完全离线介质制备与验收指南.md) 补 tag 并验收。需要按 OS 重制的是软件包（rpm → deb 本地源）。

| 项 | CentOS offline/ | 本目录 ubuntu/offline/ |
|----|----------------|----------------------|
| 离线包 | rpm + repodata | deb + Packages.gz |
| 本地源 | yum file:// | apt `deb [trusted=yes] file://` |
| 版本锁定 | yum versionlock | apt-mark hold |
| 防火墙 | firewalld | ufw |
| 镜像 tar | amd64（**复用**） | 同左 |

## 完整镜像清单与自行制备全部离线材料

本目录中的镜像、deb、manifest、脚本、校验清单如何查看和从零制备，统一见：

- [`../../docs/Kubernetes完全离线介质制备与验收指南.md`](../../docs/Kubernetes完全离线介质制备与验收指南.md)

当前基准包含 7 个 Kubernetes 核心镜像、3 个 Calico 镜像和 1 个 kube-vip 镜像。不要只按 `k8s-core.tar`、`calico.tar` 文件名判断完整性；必须按该手册将 kubeadm 清单、Calico manifest 的完整镜像引用和 tar 导入后的实际名称逐项对账。

> ⚠️ `fetch-resources.sh` 必须在与目标一致的干净 Ubuntu 制备机上运行，并在真正断网的同版本干净节点进行安装验收。包管理器在已有软件较多的制备机上解析依赖时，可能漏掉目标干净系统需要的包。

## 两步流程

### 第 1 步：制备离线包（一台能访问外网的 Ubuntu 机器）

```bash
cd ubuntu/offline/scripts && chmod +x *.sh
./fetch-resources.sh
```

这会生成到 `ubuntu/offline/` 下：

- `packages/*.deb + Packages.gz` —— 离线 deb 源
- `images/k8s-core.tar / calico.tar / kube-vip.tar` —— 离线镜像
- `manifests/calico.yaml` —— Calico manifest（gitee 国内源下载）

打包分发：

```bash
cd ubuntu/offline/..
tar czf k8s-offline-ubuntu-noble.tar.gz offline/
```

### 第 2 步：部署（离线节点）

```bash
# 各节点解压 offline/ 到 /opt/k8s-deploy/
scp k8s-offline-ubuntu-noble.tar.gz root@<master1>:/opt/k8s-deploy/
ssh root@<master1>
cd /opt/k8s-deploy && tar xzf k8s-offline-ubuntu-noble.tar.gz
cd offline/scripts && chmod +x *.sh
./deploy-all.sh --dry-run   # 先看计划
./deploy-all.sh             # 全量部署
```

> `deploy-all.sh` 会自动把 offline 目录（含 deb + tar + Packages.gz）分发到所有节点，并在 Phase 2.5 执行 `import-resources.sh`（配置 deb 本地源 + 导入镜像）。

## 分步命令速查

| 步骤 | 执行节点 | 命令 |
|------|---------|------|
| 0 | 有网制备机 | `./fetch-resources.sh`（制备离线包，仅一次） |
| 1 | 全部节点 | `./import-resources.sh`（配 deb 本地源 + 导入镜像） |
| 2 | 全部节点 | `./01-system-init.sh` |
| 3 | 全部节点 | `./02-install-containerd.sh` |
| 4 | 全部节点 | `./03-install-k8s.sh` |
| 5 | 仅 master1 | `./04-init-master1.sh` |
| 6 | 其余 master | `./05-join-master.sh` |
| 7 | worker | `./06-join-worker.sh` |
| 8 | 仅 master1 | `./07-install-calico.sh` |
| 9 | 每个 master | `./08-renew-certs.sh` |
| 10 | 仅 master1 | `./09-verify.sh` |

## 关键说明

- **deb 本地源**：`import-resources.sh` 用 `dpkg-scanpackages` 生成 `Packages.gz`，写入 `deb [trusted=yes] file:<dir> ./`，并禁用在线源（备份到 `sources.list.d/backup/`）。
- **镜像离线检查**：`04-init-master1.sh` 会先 `ctr -n k8s.io images ls` 检查本地是否有镜像，有则跳过 `kubeadm config images pull`（离线正常）。
- **镜像复用**：CentOS offline 的 `k8s-core.tar` 和 `kube-vip.tar` 在版本、架构及引用名一致时可以复用。当前 Red Hat `calico.tar` 与 Ubuntu manifest 的 registry 引用不同，复制后必须补齐 `m.daocloud.io/docker.io/calico/*` tag；按离线介质手册对账通过后才能部署。

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `apt-get update` 卡住/超时 | 在线源未禁用 | `import-resources.sh` 会禁用在线源 |
| 装包报依赖缺失 | deb 依赖没下全 | 制备机用 `--download-only` 重跑，确认 `/var/cache/apt/archives` 里依赖齐全 |
| kubeadm init 卡在拉镜像 | 镜像未导入 | 确认 `import-resources.sh` 已跑、`ctr -n k8s.io images ls` 有镜像 |
| calico.yaml 缺失 | fetch 未下载 | 有网机器跑 `fetch-resources.sh`，或手动放 `manifests/calico.yaml` |
