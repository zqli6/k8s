# 1. 相关网址  
[lzq的部署文档](https://www.yuque.com/office/yuque/0/2026/pdf/61945248/1776278242382-25897578-e08d-44a4-9300-2d92696eccd7.pdf?from=https%3A%2F%2Fwww.yuque.com%2Fjianglai-iayzx%2Fsa1zul%2Fibluos9f0g5aks1n)
# 2. 安装Prometheus  
<https://gitee.com/zqli6/k8s/tree/main/install_yaml/prometheus>  
# 3. 部署prometheus-adapter  
1. 使用Prometheus operator中的rometheus-adapter  
在`安装Prometheus`步骤中已安装
<https://gitee.com/zqli6/k8s/tree/main/install_yaml/prometheus>
2. 使用kubernetes-sigs/prometheus-adapter  
官方：<https://github.com/kubernetes-sigs/prometheus-adapter/tree/master/deploy/manifests>
lzq文档：[点击查看](https://www.yuque.com/office/yuque/0/2026/pdf/61945248/1776278242382-25897578-e08d-44a4-9300-2d92696eccd7.pdf?from=https%3A%2F%2Fwww.yuque.com%2Fjianglai-iayzx%2Fsa1zul%2Fibluos9f0g5aks1n)  
# 4. 部署kube-state-metrics (可选)  
[查看lzq文档部署](https://www.yuque.com/office/yuque/0/2026/pdf/61945248/1776278242382-25897578-e08d-44a4-9300-2d92696eccd7.pdf?from=https%3A%2F%2Fwww.yuque.com%2Fjianglai-iayzx%2Fsa1zul%2Fibluos9f0g5aks1n)
# 5. 部署测试 APP  
```
kubectl apply -f metrics-example-app.yaml
```  
# 6. 部署ServerMetric
kubectl apply -f metrics-app-sm.yaml
# 7. 部署部署 HPAv2  
```
kubectl apply -f metrics-app-hpa.yaml
```  
# 8. 自定义指标流水线规则  
在Prometheus operator中带有kube-prometheus-0.17.0/manifests/prometheusAdapter-configMap.yaml
此处新建覆盖  
```
kubectl apply -f custom-metrics-config-map.yaml
```
重启prometheus-adapter
```
kubectl rollout restart deployment -n monitoring  prometheus-adapter
```
# 9. 查看指标  
```
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second" | jq
```
# 10. 测试查看HPA是否自动缩容  
```
while true;do curl 10.111.171.119;sleep 0.0$[RANDOM%10];done
```
```
kubectl get pod
kubectl get hpa
```
