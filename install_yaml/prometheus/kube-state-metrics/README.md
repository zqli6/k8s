# 注意：使用kube-prometheus安装自带kube-state-metric，不需要自行安装
# 相关网址  
1. GitHub：[kube-state-metric](https://github.com/kubernetes/kube-state-metrics)  
2. LZQ文档：[3.3 kube-state-metrics文档查看](https://www.yuque.com/office/yuque/0/2026/pdf/61945248/1776278242382-25897578-e08d-44a4-9300-2d92696eccd7.pdf?from=https%3A%2F%2Fwww.yuque.com%2Fjianglai-iayzx%2Fsa1zul%2Fibluos9f0g5aks1n)  

# 部署及说明  
## 1. 部署清单
```
[root@master1 kube-state-metrics]# ls
kube-state-metrics-deploy.yaml kube-state-metrics-rbac.yaml kube-state-metrics-svc.yaml
```
## 2. 部署步骤
1. 创建命名空间并应用所有配置  
```
kubectl create ns prom
```
2. 创建 Deployment 配置文件
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-state-metrics/kube-state-metrics-deploy.yaml
```
3. 创建 Service 配置文件
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-state-metrics/kube-state-metrics-svc.yaml
```
kube-state-metrics Service 是否包含 annotations：
```
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
```
`如果 Prometheus 的 scrape_configs 使用了 kubernetes_sd_config 并配置了相应的 relabel 规则（例如过滤 __meta_kubernetes_service_annotation_prometheus_io_scrape = "true"），它就会自动发现该 Service 并开始抓取 /metrics。`  
4. 创建 RBAC 配置文件
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-state-metrics/kube-state-metrics-rbac.yaml
```

## 3. 验证  
1. 确认安装  
```
[root@master1 k8s-prom]# kubectl get pod,svc -n prom
# NAME                                         READY   STATUS    RESTARTS       AGE
# pod/kube-state-metrics-8bfc6ff57-qhg2k       1/1     Running   0              4m14s
# pod/prometheus-server-554b65958d-5xmhm       1/1     Running   4 (4h5m ago)   12d
# NAME                                 TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
# service/kube-state-metrics           ClusterIP  10.104.193.129   <none>        8080/TCP        4m14s
```
2. 访问 kube-state-metrics 对应的 SVC  
```
[root@master1 ~]# curl 10.104.193.129:8080/metrics
# 以下为输出示例（仅展示部分）
# TYPE kube_certificatesigningrequest_labels gauge
# HELP kube_certificatesigningrequest_created Unix creation timestamp
# TYPE kube_certificatesigningrequest_created gauge
# HELP kube_certificatesigningrequest_condition The number of each certificatesigningrequest condition
# TYPE kube_certificatesigningrequest_condition gauge
# HELP kube_certificatesigningrequest_cert_length Length of the issued cert
# TYPE kube_certificatesigningrequest_cert_length gauge
# HELP kube_certificatesigningrequest_annotations Kubernetes annotations converted to Prometheus labels.
# TYPE kube_certificatesigningrequest_annotations gauge
.....

[root@master1 ~]# curl -s 10.99.171.118:8080/metrics | grep kube_deployment_create | head
# HELP kube_deployment_created Unix creation timestamp
# TYPE kube_deployment_created gauge
kube_deployment_created{namespace="custom-metrics",deployment="custom-metrics-apiserver"} 1.767520961e+09
kube_deployment_created{namespace="default",deployment="hpav2-demo-deployment"} 1.767518101e+09
kube_deployment_created{namespace="default",deployment="myapp"} 1.76717534e+09
kube_deployment_created{namespace="kube-system",deployment="calico-typha"} 1.766743168e+09
kube_deployment_created{namespace="sc-nfs",deployment="nfs-client-provisioner"} 1.765957031e+09
kube_deployment_created{namespace="default",deployment="metrics-app"} 1.767522438e+09
kube_deployment_created{namespace="default",deployment="myweb2"} 1.767576595e+09
kube_deployment_created{namespace="kube-system",deployment="metrics-server"} 1.765510572e+09
```
3. 通过 Prometheus 查看相关指标：  
kube_service_info  
kube_persistentvolume_info  
kube_deployment_created  
kube_statefulset_created  
kube_node_status_condition