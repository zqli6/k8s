# k8s

用于在国内网络环境下部署 Kubernetes 集群及常用组件。由于 `registry.k8s.io`、`gcr.io` 等官方镜像在国内无法直接拉取，仓库中带 `_lzq` 后缀的脚本和清单文件均已将镜像地址替换为自建在华为云容器镜像服务（SWR）上的私有仓库。部署前先通过 `sync_images_SWR.sh` 将所需镜像从官方源拉取并推送至华为云 SWR，集群节点统一从私有仓库拉取，无需科学上网。

## 包含内容

1. **scripts**：K8s 集群安装脚本，支持 Docker（cri-dockerd）和 Containerd 两种运行时。每种运行时各有两个版本：原版使用官方镜像源，`_lzq` 后缀版本镜像地址已替换为华为云 SWR 私有仓库，适合内网或无外网环境；`sync_images_SWR.sh` 用于提前将官方镜像同步至华为云 SWR
2. **cri-docker**：cri-dockerd 离线安装包及 systemd 配置文件（K8s 1.24+ 移除内置 Docker 支持后的适配方案）
3. **flannel_docker**：Flannel 网络插件安装清单，`kube-flannel-lzq.yaml` 中镜像地址已替换为华为云 SWR 私有仓库
4. **ingress**：ingress-nginx 控制器安装清单（`ingress-controller-lzq.yaml` 镜像已替换为华为云 SWR）及离线镜像包
5. **metalLB**：MetalLB 安装清单（`metallb-native-v0.19.0-lzq.yaml` 镜像已替换为华为云 SWR），含 IP 地址池和 L2 广播模式配置
6. **install_yaml/Jenkins**：在 K8s 上部署 Jenkins 的完整清单，按 namespace、RBAC、存储、Deployment、Service、Ingress 顺序拆分为 6 个文件，附离线安装包和汉化插件
7. **install_yaml/gitlab**：使用 Operator 方式在 K8s 上部署 GitLab，含 cert-manager 证书管理配置
8. **install_yaml/prometheus**：Prometheus 相关服务的 Ingress 路由配置

## 镜像同步思路

国内部署 K8s 时镜像拉取是最常见的障碍，这里的解决方式是：

1. 在有外网访问的环境中运行 `sync_images_SWR.sh`，将部署所需的所有官方镜像（包括 kubeadm 组件镜像、Flannel、ingress-nginx、MetalLB 等）拉取后统一推送至华为云 SWR 私有仓库
2. 将各组件 YAML 清单中的镜像地址批量替换为 SWR 私有仓库地址，生成带 `_lzq` 后缀的定制版本
3. 集群节点配置华为云 SWR 的访问凭证，部署时直接从私有仓库拉取，整个过程不依赖外网

## 快速获取
```bash
# GitHub（支持 ghproxy 加速）
wget https://ghproxy.net/https://raw.githubusercontent.com/zqli6/k8s/main/path/to/file

# Gitee（国内推荐）
wget https://gitee.com/zqli6/k8s/raw/main/path/to/file
```

## 克隆仓库
```bash
git clone https://github.com/zqli6/k8s/
git clone https://gitee.com/zqli6/k8s/
```

> 环境：Ubuntu 20.04 / 22.04（k8s 集群部署仅支持 Ubuntu），Kubernetes 1.26+，运行时 cri-dockerd / Containerd，网络插件 Flannel，负载均衡 MetalLB，镜像仓库 华为云SWR
