# 完整部署  
1. 部署kube-Prometheus  
2. 部署VictoriaMetrics做kube-Prometheus持久化  
3. grafana的数据持久化  storage_for_grafana
   1. k8s中部署MySQL做持久化  
   2. 使用传统应用MySQL做持久化  
4. kube-state-metrics 
   1. kube-prometheus自带 kube-state-metric，不需要自行安装  
      若Prometheus web页面kube-state-metric为down，可能是rbac未生效，可再次应用相关清单  
      ```
      kubectl apply -f kubeStateMetrics-clusterRole.yaml
      kubectl apply -f kubeStateMetrics-clusterRoleBinding.yaml
      ```
   2. 其他形式安装Prometheus需自行安装kube-state-metrics  
      1. 暴露集群内资源的状态：生成关于资源状态的指标，而非资源使用情况（如CPU/内存）。  
      2. 提供对象元数据信息：指标包含资源的元数据，例如 Pod 的状态、标签、重启次数，或 Deployment 的理想和实际副本数。  
      3. 兼容Prometheus格式：通过HTTP API（默认端口8080，路径/metrics）暴露指标，能被Prometheus直接抓取。  
      4. 支持原生与自定义资源：原生支持Node、Pod等标准资源，并可扩展以监控Custom Resource Definitions (CRDs)。  
