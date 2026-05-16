官方：<https://github.com/kubernetes-sigs/metrics-server>  
lzq文档：[点击跳转lzq文档](https://www.yuque.com/jianglai-iayzx/sa1zul/ibluos9f0g5aks1n)
# MetricServer部署  
1. lzq优化版  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/components_lzq.yaml
```
优化两处如下：
```
kind: Deployment
...
  template:
      - args:
        - --kubelet-insecure-tls #添加本行和下面共两行,不加此行导致Pod无法ready，提示：Warning Unhealthy 5s (x19 over 2m45s) kubelet   Readiness probe failed: HTTP probe failed with statuscode: 500
        - --cert-dir=/tmp
        ...
        image: registry.cn-hangzhou.aliyuncs.com/google_containers/metrics-server:v0.8.1
        #image: registry.k8s.io/metrics-server/metrics-server:v0.8.1
```