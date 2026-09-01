# Kubernetes 1.20.11 部署包说明

本目录用于在 **Ubuntu** 或 **CentOS 7** 服务器上部署 Kubernetes 1.20.11、Flannel 0.25.7 和 Helm 3.0.3。所有命令均按直接登录目标服务器后执行的场景编写。



下载离线包
```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s-1.20.11-offline:26.9.2
```
复制出文件可参考[Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/mlda3n2mcphvzo2o#wpXxl)
```
docker create --name temp-extract \
  swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s-1.20.11-offline:26.9.2 echo
docker cp temp-extract:/data/k8s-1.20.11-offline.tar ./
docker rm temp-extract
```
```
ctr image mount swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s-1.20.11-offline:26.9.2 /mnt/
cp /mnt/k8s-1.20.11-offline.tar ./
ctr image unmount /mnt/
```



## 文档入口

| 场景 | 文档 |
|------|------|
| Ubuntu 公网在线部署 | [`docs/ubuntu.md`](docs/ubuntu.md) |
| CentOS 7 公网在线部署 | [`docs/centos.md`](docs/centos.md) |
| Ubuntu 完全离线部署 | [`docs/ubuntu-offline.md`](docs/ubuntu-offline.md) |
| CentOS 7 完全离线部署 | [`docs/centos-offline.md`](docs/centos-offline.md) |
| 华为云 SWR 私有仓库部署 | [`docs/swr-images.md`](docs/swr-images.md) |

## 版本

| 组件 | 版本 |
|------|------|
| Kubernetes | 1.20.11 |
| Helm | 3.0.3 |
| Flannel | 0.25.7 |
| Flannel CNI plugin | 1.5.1-flannel2 |
| CoreDNS | 1.7.0 |
| etcd | 3.4.13-0 |
| pause | 3.2 |

> Kubernetes 1.20.11 已停止维护，仅适合兼容性要求明确的环境。生产环境应规划升级。

## 目录结构

```text
k8s-1.20.11-offline/
├── README.md
├── docs/
│   ├── ubuntu.md                      # Ubuntu 公网在线版
│   ├── centos.md                      # CentOS 7 公网在线版
│   ├── ubuntu-offline.md              # Ubuntu 完全离线版
│   ├── centos-offline.md              # CentOS 7 完全离线版
│   └── swr-images.md                  # Ubuntu/CentOS 通用 SWR 私有仓库版
├── packages/
│   ├── ubuntu/
│   │   ├── os-packages/                  # Ubuntu Docker/containerd deb 包
│   │   ├── kubernetes/                   # Ubuntu Kubernetes deb 包
│   │   ├── cni/                          # Ubuntu CNI、cri-tools、crictl
│   │   ├── systemd/                      # Ubuntu systemd 配置
│   │   ├── checksums/                    # Ubuntu 包校验文件
│   │   └── README.md
│   └── centos/
│       ├── os-packages/                  # CentOS Docker/containerd RPM 包
│       ├── kubernetes/                   # CentOS Kubernetes 二进制
│       ├── cni/                          # CentOS CNI 和网络工具
│       ├── systemd/                      # CentOS systemd 配置
│       ├── checksums/                    # CentOS 文件校验
│       └── README.md
├── images/
│   └── k8s-images-offline.tar          # Ubuntu/CentOS x86_64 共用的 9 个核心镜像
├── helm/
│   └── helm-v3.0.3-linux-amd64.tar.gz # Ubuntu/CentOS 共用
├── deploy/
    ├── kube-flannel-online.yaml        # 在线公网，镜像名为 Docker Hub（由 Docker 镜像加速器拉取）
    ├── kube-flannel-swr.yaml            # SWR 私有仓库，直接从 SWR 拉取
    └── kube-flannel-offline.yaml        # 完全离线，使用本地已导入镜像
```

## 哪些文件可以共用

Ubuntu 和 CentOS 均为 Linux x86_64 时，下列内容可以共用：

- Kubernetes、etcd、CoreDNS、pause 镜像；
- Flannel 和 Flannel CNI plugin 镜像；
- Helm `linux-amd64` 二进制包；
- Flannel Kubernetes YAML 清单。

系统安装包不能混用：Ubuntu 使用 `.deb`，CentOS 使用 `.rpm`。

## 三种部署方式

| 方式 | 系统组件来源 | Kubernetes 核心镜像 | Flannel 镜像 | 凭据 |
|------|--------------|---------------------|--------------|------|
| **公网在线** | 阿里云 Docker CE APT/Yum 源 | 阿里云 `registry.aliyuncs.com/google_containers` | Docker Hub `docker.io/flannel/*`（经 `docker.1panel.live`） | 无 |
| **完全离线** | 本地 deb/RPM | `images/k8s-images-offline.tar` | 同一离线 tar | 无 |
| **SWR 私有仓库** | 按系统在线安装组件 | SWR `zqli/google_containers` | SWR `zqli/flannel` | SWR 用户名/密码 |

公网在线与 SWR 私有仓库是两个独立方案：公网在线文档中不需要任何 SWR 配置；SWR 账号、密码和 `config.json` 仅在 SWR 文档中出现。

## 快速验证

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get daemonset -n kube-flannel
helm version --short
```

期望所有节点为 `Ready`，`kube-system` 和 `kube-flannel` 命名空间中的 Pod 均为 `Running`。
