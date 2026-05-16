# kuboard官网安装教程
<https://kuboard.cn/install/v3/install-in-k8s.html>
# 安装环境准备  
1. metalLB
2. StorageClass
3. Ingress  
4. 部署  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/board/kuboard/01-kuboard-v3_lzq.yaml
```
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/board/kuboard/01-kuboard-v3.yaml
```
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/board/kuboard/02-ingress-kuboard.yaml
```