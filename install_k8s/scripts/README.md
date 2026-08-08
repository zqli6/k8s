# 相关网址
1. k8s关于使用kubeadm安装k8s集群的说明  
[kubeadm安装k8s集群的说明](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)  
2. LZQ学习笔记  
[LZQ的安装文档](https://www.yuque.com/jianglai-iayzx/sa1zul/lxkwah6m1zw0h7vb#coJvj)  
```
# pod基于docker此处增加--cri-socket
# 使用lzq SWR私人仓库加速，只支持K8S_RELEASE_VERSION=1.35.0
K8S_RELEASE_VERSION=1.35.0 &&
kubeadm init --kubernetes-version=v${K8S_RELEASE_VERSION} --control-plane-endpoint kubeapi.lzq.org --pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12 --token-ttl=0 --image-repository swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers --upload-certs --cri-socket=unix:///run/cri-dockerd.sock
```

**lzq 后缀的脚本使用的k8s组件镜像使用lzq SWR镜像仓库进行加速**
# 1.insatll_ kubernetes_docker.sh  
1. Place the script install_kubernetes_docker.sh and the file cri-dockerd-0.3.23.amd64.tgz in the same directory.
```
# 下载脚本
wget https://gitee.com/zqli6/k8s/raw/main/scripts/install_kubernetes_docker_lzq.sh
```
```
# 下载 LZQ Gitee cri-docekr 0.3.23，脚本中默认这个版本
wget https://gitee.com/zqli6/k8s/raw/main/scripts/cri-dockerd-0.3.23.amd64.tgz
```
如果 Gitee无法下载，可访问 [cri-docker Github](https://github.com/Mirantis/cri-dockerd)下载
```
# 下载官方 Github cri-docker 0.3.23
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.23/cri-dockerd-0.3.23.amd64.tgz
```
2. Modify the script to choose K8s version and edit hosts configuration.
3. To download the latest cri-dockerd release  
<https://github.com/Mirantis/cri-dockerd/releases>
3. Kubernetes  
<https://github.com/kubernetes/kubernetes>

# 2. install_kubernetes_containerd.sh  
1. 下载脚本，使用前先修改脚本，选择单主或多主架构
```
wget https://gitee.com/zqli6/k8s/raw/main/scripts/install_kubernetes_containerd_lzq.sh
``` 
2. To download the latest containerd form GitHub  
<https://github.com/containerd/containerd>
# 3. 使用sync_images_SWR.sh
功能：  
    自动打标签，自动上传私有仓库  
使用注意事项：  
    使用前需先登录私有仓库  
    修改`私有仓库前缀:MY_REGISTRY`及`源镜像前缀:FROM_REGISTRY`  
    修改镜像列表为所需列表`images=(  )`
