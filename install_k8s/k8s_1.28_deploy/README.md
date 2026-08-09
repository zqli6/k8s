# Kubernetes 1.28 高可用集群 · 部署与网络技术参考

> 3 Master + 6 Worker | containerd | kube-vip HA | Calico VXLAN | 证书 10 年
> 已在 9 台 CentOS 7.9 真机完整跑通，验收 20/20。



下载离线包
```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.8.9
```
复制出文件可参考[Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/mlda3n2mcphvzo2o#wpXxl)
```
docker create --name temp-extract \
  swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.8.9 echo
docker cp temp-extract:/data/k8s_1.28_deploy.zip ./
docker rm temp-extract
```
```
ctr image mount swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy:26.8.9 /mnt/
cp /mnt/k8s_1.28_deploy.zip ./
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
| containerd | 1.6.33 | 阿里云 docker-ce 源 |
| kube-vip | v0.8.0 | ghcr.io（ARP 静态 Pod） |
| Calico | v3.26.4 | VXLAN 数据面（DaoCloud 加速） |
| 证书 | 10 年 | update-kubeadm-cert.sh（openssl 重签） |
| kube-proxy | IPVS 模式 | 11 种调度算法 |

---

## 四套部署方案

本仓库提供**四套平级、独立自包含**的部署方案，按场景选用：

| 目录 | 场景 | 镜像来源 | 脚本数 |
|------|------|---------|:---:|
| [`online/`](online/README.md) | **在线部署**（节点能上外网） | 阿里云 + DaoCloud | 11 |
| [`offline/`](offline/README.md) | **离线部署**（air-gap 无外网） | 本地 tar 导入 | 12 |
| [`private-registry/`](private-registry/README.md) | **Harbor 私有仓库** | Harbor（自签证书） | 12 |
| [`swr/`](swr/README.md) | **华为云 SWR 仓库** | SWR private 组织 | 12 |

每套目录结构（自包含）：`config/cluster.env` + `scripts/*.sh` + `tools/` + `manifests/`。

**增减节点**只改 `config/cluster.env` 的 `MASTER_NODES` / `WORKER_NODES` 列表，脚本全程自动适配。

---

## 快速开始（在线版一键部署）

```bash
# 1. 修改 config/cluster.env 中的 VIP 为实际空闲 IP
# 2. 上传到 master1
scp -r virtual-k8s/ root@192.168.104.104:/opt/k8s-deploy/

# 3. 一键部署
ssh root@192.168.104.104
cd /opt/k8s-deploy/online/scripts && chmod +x *.sh
./deploy-all.sh
```

支持 `--from N`（断点续跑）、`--only N`、`--dry-run`。

---

## 网络深度手册（必读）

**[`docs/k8s-network-guide.md`](docs/k8s-network-guide.md)** — 941 行、20 个 mermaid 图的完整 K8s 网络技术文档：

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
- **kube-vip**：v1.28 挂载 `/etc/kubernetes/admin.conf`（v1.29+ 才有 super-admin.conf）
- **CentOS7 内核**：Calico 用 iptables+VXLAN（非 eBPF，3.10 不支持）
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
| 9 | containerd hosts.toml 无 auth | SWR private 拉不到 | 改用 config.toml registry.configs |

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
