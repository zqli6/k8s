# Kubernetes 1.28 私有仓库部署版

> 支持 1/3/5 个 Master 与任意数量 Worker；本目录只提供默认示例，实际节点以 `config/cluster.env` 为准。
> **所有镜像从你的私有仓库（Harbor / registry）拉取**

本目录是**完全自包含**的一套，与 `online/`、`offline/` 平级、互不干扰。适用场景：内网已有 Harbor 或私有 registry，希望所有节点统一从私有仓库拉镜像。

## 控制面模式

`MASTER_COUNT=1` 时使用 master1 IP 作为控制面端点，不部署 kube-vip；`MASTER_COUNT>1` 时使用 VIP 并部署 kube-vip。`KUBE_PROXY_MODE` 独立控制 Service 转发模式，private registry 只负责镜像来源和仓库信任。


| 项 | 在线版 (online/) | 私有仓库版 (本目录) |
|----|-----------------|--------------------|
| K8s 镜像 | 阿里云 registry.aliyuncs.com | 你的私有仓库 |
| Calico 镜像 | DaoCloud 加速源 | 你的私有仓库 |
| kube-vip 镜像 | ghcr.io | 你的私有仓库 |
| Calico manifest | gitee 下载 | 本目录 manifests/calico.yaml（不联网） |
| 额外步骤 | 无 | 先推镜像 + 配证书信任 |

## 目录结构

```
private-registry/
├── config/cluster.env          # 配置（改 PRIVATE_REGISTRY + 证书信任）
├── tools/update-kubeadm-cert.sh # 证书续期脚本（内置）
├── manifests/calico.yaml        # Calico 清单（本地，不联网）
└── scripts/
    ├── 00-env-check.sh          # 全部节点｜环境检查
    ├── 01-system-init.sh        # 全部节点｜系统初始化
    ├── 02-install-containerd.sh # 全部节点｜装 containerd + 配私有仓库信任
    ├── 03-install-k8s.sh        # 全部节点｜装 kubeadm/kubelet/kubectl
    ├── 04-init-master1.sh       # 仅 master1｜初始化
    ├── 05-join-master.sh        # 仅 master2/3｜加入控制平面
    ├── 06-join-worker.sh        # 仅 node*｜加入 worker
    ├── 07-install-calico.sh     # 仅 master1｜装 CNI
    ├── 08-renew-certs.sh        # 每个 master｜证书续期 10 年
    ├── 09-verify.sh             # 仅 master1｜验收
    ├── push-to-registry.sh      # 推送所有镜像到私有仓库
    └── deploy-all.sh            # 仅 master1｜一键部署
```

## 部署流程（4 步）

### 第 1 步：配置私有仓库地址

编辑 `config/cluster.env`：

```bash
# 私有仓库地址（含项目名）
PRIVATE_REGISTRY="192.168.104.50/k8s"      # 改成你的 Harbor 地址

# 证书信任方式（见下方"自签证书信任"章节，按你的仓库情况三选一）
REGISTRY_CA_FILE=""                         # A: 自签+有CA证书 → 填CA路径
REGISTRY_TLS_INSECURE="true"                # B: 自签无CA/图省事 → true 跳过校验
REGISTRY_PROTOCOL="https"                   # C: 纯HTTP仓库 → 改 http
```

同时确认节点列表 `MASTER_NODES` / `WORKER_NODES`、VIP 地址正确。

### 第 2 步：推送镜像到私有仓库

在一台**能同时访问外网和私有仓库**的机器上执行（通常是有网的跳板机）：

```bash
cd private-registry/scripts
./push-to-registry.sh --pull
```

这会自动：列出全部镜像（K8s 核心 7 个 + pause + kube-vip + calico 3 个）→ 从公网拉取 → 重打标签为私有仓库地址 → 推送。

> ⚠️ 若跳板机无外网，改用离线介质：先在有网处用 `offline/scripts/fetch-resources.sh` 下载镜像 tar，导入本机后执行 `./push-to-registry.sh`（不带 --pull）。

推送后镜像在私有仓库的路径：

```text
${PRIVATE_REGISTRY}/kube-apiserver:v1.28.15
${PRIVATE_REGISTRY}/pause:3.9
${PRIVATE_REGISTRY}/etcd:3.5.x-0
${PRIVATE_REGISTRY}/coredns:v1.10.1
${PRIVATE_REGISTRY}/kube-vip/kube-vip:v0.8.0
${PRIVATE_REGISTRY}/calico/node:v3.26.4
${PRIVATE_REGISTRY}/calico/cni:v3.26.4
${PRIVATE_REGISTRY}/calico/kube-controllers:v3.26.4
```

### 第 3 步：部署集群

将整个 `private-registry/` 目录上传到 master1，一键部署：

```bash
scp -r private-registry/ root@192.168.104.104:/opt/k8s-deploy/
ssh root@192.168.104.104
cd /opt/k8s-deploy/private-registry/scripts
chmod +x *.sh
./deploy-all.sh
```

`02-install-containerd.sh` 会在每个节点自动配置私有仓库信任（见下）。

### 第 4 步：验收

```bash
./09-verify.sh    # 20 项检查全绿即成功
```

## 分步部署命令速查

前置：完成上面第 1、2 步（配好 `config/cluster.env` 的 `PRIVATE_REGISTRY` + 证书信任变量、镜像已推入仓库），并把 `private-registry/` 目录传到 master1、各节点 SSH 免密已通。脚本自包含，`source ../config/cluster.env`。在每个节点 `scripts/` 目录里按下表执行。

| 步骤 | 执行节点 | 命令 | 说明 |
|------|---------|------|------|
| 0 | 有网跳板机 | `./push-to-registry.sh --pull` | 部署前先推镜像（见第 2 步，仅需一次） |
| 1 | 当前配置中的全部节点 | `./00-env-check.sh` | 环境检查（只读） |
| 2 | 当前配置中的全部节点 | `./01-system-init.sh` | 系统初始化（swap/SELinux/内核/sysctl/hosts） |
| 3 | 当前配置中的全部节点 | `./02-install-containerd.sh` | 装 containerd + 配私有仓库信任 |
| 4 | 当前配置中的全部节点 | `./03-install-k8s.sh` | 装 kubeadm/kubelet/kubectl |
| 5 | 仅 master1 | `./04-init-master1.sh` | 单 Master 直连；多 Master 使用 kube-vip + VIP |
| — | master1 → 其余节点 | `scp /etc/kubernetes/deploy/join.env root@<节点>:/etc/kubernetes/deploy/` | 分发 join 凭据（一键版自动，分步需手动） |
| 6 | 其余 master（串行） | `./05-join-master.sh` | `MASTER_COUNT>1` 时加入控制平面 |
| 7 | 当前配置中的 worker（可并行） | `./06-join-worker.sh` | 加入 worker |
| 8 | 仅 master1 | `./07-install-calico.sh` | 装 Calico CNI（用本地 `manifests/calico.yaml`，VXLAN） |
| 9 | 每个 master（串行） | `./08-renew-certs.sh` | 证书续期 10 年 |
| 10 | 仅 master1 | `./09-verify.sh` | 20 项验收，全绿即成功 |

> 一键：master1 上 `./deploy-all.sh`（自动分发 join.env、串行 join master、并行 join worker、按 phase 编排）。支持 `--from N` 断点续跑、`--only N`、`--dry-run`。
> 与在线版的唯一部署差异：**多出第 0 步推镜像**，且第 3 步的 containerd 会额外配置私有仓库信任；其余步骤编号与逻辑同在线版，但配置从本目录 `config/cluster.env` 读取。

## 自签证书信任配置（重点）

> ⚠️ **containerd 拉不到私有仓库镜像，90% 是证书不被信任。** 报错通常是
> `x509: certificate signed by unknown authority` 或 `http: server gave HTTP response to HTTPS client`。

`02-install-containerd.sh` 会根据 `cluster.env` 的三个变量，自动在每个节点生成 containerd 的 `certs.d` 配置。原理：containerd 1.6+ 用 `/etc/containerd/certs.d/<仓库主机>/hosts.toml` 管理每个仓库的 TLS 策略。下面按你的仓库情况选一种。

### 情况 A：自签证书 + 有 CA 证书文件（推荐，最安全）

Harbor 用自签证书时，会有一个 CA 根证书（Harbor 管理界面「项目 → 仓库证书」或部署目录 `ca.crt`）。把它分发到各节点，并在配置里指向它：

```bash
# 1. 把 CA 证书分发到所有节点（在 master1 上，借免密）
for ip in 192.168.104.{104,137,97,132,180,134,103,90,162}; do
    scp harbor-ca.crt root@$ip:/opt/k8s-deploy/harbor-ca.crt
done

# 2. cluster.env 配置
REGISTRY_CA_FILE="/opt/k8s-deploy/harbor-ca.crt"
REGISTRY_TLS_INSECURE="false"
REGISTRY_PROTOCOL="https"
```

脚本会生成 `/etc/containerd/certs.d/<harbor>/hosts.toml`：

```toml
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
```

### 情况 B：自签证书但没有 CA / 图省事（跳过 TLS 校验）

不校验证书，直接信任。安全性低于 A，但内网可接受：

```bash
REGISTRY_CA_FILE=""
REGISTRY_TLS_INSECURE="true"     # 关键：跳过校验
REGISTRY_PROTOCOL="https"
```

生成的 hosts.toml：

```toml
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
```

### 情况 C：纯 HTTP 仓库（无 TLS）

仓库是 HTTP（如自建 `registry:2` 未配证书）：

```bash
REGISTRY_CA_FILE=""
REGISTRY_TLS_INSECURE="true"
REGISTRY_PROTOCOL="http"          # 关键：改 http
```

### 情况 D：受信任 CA 签发的证书（Let's Encrypt 等）

证书由公网 CA 签发，系统已信任，三个变量保持默认即可，无需额外配置。

### 手动配置（不用脚本时）

若想手动在某个节点配置信任，等价操作：

```bash
# 1. 建目录（目录名 = 仓库主机名，带端口就带上，如 192.168.104.50:5000）
mkdir -p /etc/containerd/certs.d/harbor.example.com

# 2A. 有 CA 证书：放进去并写 hosts.toml
cp harbor-ca.crt /etc/containerd/certs.d/harbor.example.com/ca.crt
cat > /etc/containerd/certs.d/harbor.example.com/hosts.toml <<EOF
server = "https://harbor.example.com"
[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
EOF

# 3. 确认 config.toml 启用了 certs.d（关键，否则上面配置不生效）
grep -q 'config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml || \
  sed -i 's|\(\[plugins."io.containerd.grpc.v1.cri".registry\]\)|\1\n      config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml

# 4. 重启
systemctl restart containerd
```

### 验证信任是否生效

```bash
# 在任一节点测试拉取（应成功，不报 x509 错误）
crictl pull 192.168.104.50/k8s/pause:3.9

# 若还需要认证（Harbor 非公开项目），先登录：
# containerd 本身不存登录态，需在 push 端用 docker/nerdctl login；
# 拉取端用 hosts.toml 的 [host.xxx.auth] 或给 kubelet 配 imagePullSecrets
```

> 说明：`push-to-registry.sh` 推镜像时会 `docker/nerdctl login`。若 Harbor 项目设为**公开**，节点拉取无需认证；若为**私有**项目，需给工作负载配 `imagePullSecrets`，或把项目设为公开（内网常用）。

## 证书 10 年说明

与在线版一致：`08-renew-certs.sh` 用内置的 `tools/update-kubeadm-cert.sh`，通过 `--days 3650`（`KUBE_CERT_DAYS`）把叶子证书续到 10 年，CA 默认已 10 年。详见脚本内注释。

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `x509: certificate signed by unknown authority` | 自签证书未信任 | 情况 A 配 CA，或情况 B 设 `REGISTRY_TLS_INSECURE=true` |
| `http: server gave HTTP response to HTTPS client` | 仓库是 HTTP，containerd 按 HTTPS 访问 | 情况 C 设 `REGISTRY_PROTOCOL=http` |
| `pull access denied` / `unauthorized` | Harbor 私有项目需认证 | 把项目设为公开，或配 imagePullSecrets |
| Pod 一直 ImagePullBackOff | 镜像没推全 / 地址不对 | 确认 `push-to-registry.sh` 成功、`crictl pull` 手测 |
| certs.d 配了还是不信任 | config.toml 没启用 config_path | 确认有 `config_path = "/etc/containerd/certs.d"` 并重启 containerd |


## 部署参数详解 / 最终 YAML 位置

仓库地址、仓库密码、kube-proxy 模式（查/改/影响）、自定义 Service 域名、Pod/Service/Calico 三网段、长期证书原理——每项的「改哪里 + 部署后最终落地在集群哪个 YAML」，统一见顶层 `../README.md` 的「配置详解 FAQ」章节。
