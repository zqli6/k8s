# 相关网址
1. 官网：https://docs.rancher.cn/  
2. github：https://github.com/rancher/rancher  
3. 部署文档：[官方部署](https://ranchermanager.docs.rancher.com/v2.15/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster/#_kubernetes_cluster)  

# 部署方法  
## 部署步骤  
1. 安装cert-manager  
如果关闭ingress可以不用安装cert-manager，但需要开启NodePort
见 https://gitee.com/zqli6/HA-cluster/tree/master/cert-manager  
2. 拉取Lzq 华为SWR chart  
```
helm registry login swr.cn-southwest-2.myhuaweicloud.com \
  -u 'cn-southwest-2@HST3W9FUH6ZLDOHSK024' \
  -p '62d19715523dda75a55903bc5d1f5b251adc821f7e29a3a9bcd6038f54d4dcac'
```
```
# 直接部署
helm install rancher oci://swr.cn-southwest-2.myhuaweicloud.com/zqli_c/rancher-lzq \
  --version 2.15.3 -n rancher --create-namespace
# 增加`--set hostname=rancher.example.com`指定域名，默认为`rancher.lzq.org`
```
```
# 拉取chart进行修改部署
helm pull oci:helm pull oci://swr.cn-southwest-2.myhuaweicloud.com/zqli_c/rancher \
  --version 2.15.3
```
##  pull secret patch  
参考：https://gitee.com/zqli6/HA-cluster/blob/master/SWR-AUTH.md#%E5%A4%9A%E4%B8%AApod%E5%90%8C%E6%97%B6
```
# 1. 创建 Secret（存储 SWR 登录凭据）需登录swr 更新
kubectl create secret docker-registry swr-auth -n rancher \
  --docker-server=swr.cn-southwest-2.myhuaweicloud.com \
  --docker-username='cn-southwest-2@HST3WBRU8484RY3AGAFX' \
  --docker-password='8eb15bd0873dc162d8be3057ba45653764d344d3926484c1bbf1e1836b2a01cd'

# 2. 绑定到 ServiceAccount
kubectl get pod -n rancher -o jsonpath='{range .items[*]}{.spec.serviceAccountName}{"\n"}{end}' \
  | sort -u \
  | while read sa; do
      [ -z "$sa" ] && continue
      echo ">>> patching SA: $sa"
      kubectl patch serviceaccount "$sa" -n rancher \
        -p '{"imagePullSecrets": [{"name": "swr-auth"}]}'
    done
# 3. 删除pod重新拉取镜像
kubectl delete pod -n rancher --all
```

# chart改造说明  
根据官方chart改造  
```
# 先添加 repo（如果还没加）
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# 查看所有版本
helm search repo rancher-stable/rancher --versions

# 拉取rancher-stable/rancher  2.15.3
helm pull rancher-stable/rancher  --version=2.15.3
```
## 改造点  
1. 使用修改使用nginx ingress，默认为k3s中Traefik  
2. 指定域名为：rancher.lzq.org  
3. 指定镜像为LZQ swr 仓库镜像


