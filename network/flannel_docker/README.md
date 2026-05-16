1. The container images referenced in this YAML manifest are sourced from Huawei Cloud Container Registry, pulled by lizhiquan.
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/network/flannel_docker/kube-flannel-lzq.yaml
```
3. flannel GitHub  
<https://github.com/flannel-io/flannel>
4. Download Flannel manifests from GitHub:
```
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```
4. To download the latest Flannel release from GitHub  
<https://github.com/flannel-io/flannel/releases>
