# NetworkPolicy配置白名单
0.17.0更为严格，之前版本可以不修改
注意每一个软件都需要单独开启：
```
# 方法一：直接该文件
当前位置： /data/prometheus/kube-prometheus-0.17.0 
[root@master1 kube-prometheus-0.17.0 ]# ls manifests/ | grep networkPolicy
alertmanager-networkPolicy.yaml
blackboxExporter-networkPolicy.yaml
grafana-networkPolicy.yaml
kubeStateMetrics-networkPolicy.yaml
nodeExporter-networkPolicy.yaml          # 不改
prometheusAdapter-networkPolicy.yaml     # 不改
prometheus-networkPolicy.yaml            # 不改
prometheusOperator-networkPolicy.yaml    # 不改

# 方法二：应用后在线改
[root@master1 kube-prometheus-0.17.0 ]# kubectl edit networkpolicy -n monitoring 
alertmanager-main    blackbox-exporter    grafana              kube-state-metrics   node-exporter        prometheus-adapter   prometheus-k8s       prometheus-operator
Prometheus
```
# 具体修改
```
# prometheus
[root@master1 kube-prometheus-0.17.0 ]# kubectl edit networkpolicy -n monitoring prometheus-k8s
# 添加：
  # 允许 Ingress Controller 访问
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/component: controller
    ports:
    - port: 9090
    - port: 8080
```
```
# Grafana
[root@master1 kube-prometheus-0.17.0 ]# kubectl edit networkpolicy -n monitoring grafana
# 添加：
  # 允许 Ingress Controller 访问
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/component: controller
    ports:
    - port: 3000
```
```
Alertmanager
[root@master1 kube-prometheus-0.17.0 ]# kubectl edit networkpolicy -n monitoring alertmanager-main
# 添加：
  # 允许 Ingress Controller 访问
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/component: controller
    ports:
    - port: 9093
    - port: 8080
```
```
Blackbox Exporter
[root@master1 kube-prometheus-0.17.0 ]# kubectl edit networkpolicy -n monitoring blackbox-exporter
# 添加：
  # 允许 Ingress Controller 访问
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/component: controller
    ports:
    - port: 9115
    - port: 19115
```
不需要修改的（它们不需要被 Ingress 访问）
| NetworkPolicy | 原因 |
| :-: | :-: |
| kube-state-metrics | 只被 Prometheus 抓取，不对外暴露 |
| node-exporter | 只被 Prometheus 抓取，不对外暴露 |
| prometheus-adapter | 只被 HPA/API 使用，不通过 Ingress |
| prometheus-operator | 只管理 CRD，不对外暴露 |
# 一键添加所有规则（推荐）
```
# Prometheus
kubectl patch networkpolicy -n monitoring prometheus-k8s --type='json' -p='[
  {"op": "add", "path": "/spec/ingress/-", "value": {"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "ingress-nginx"}}, "podSelector": {"matchLabels": {"app.kubernetes.io/component": "controller"}}}], "ports": [{"port": 9090, "protocol": "TCP"}, {"port": 8080, "protocol": "TCP"}]}}
]'
```
```
# Grafana
kubectl patch networkpolicy -n monitoring grafana --type='json' -p='[
  {"op": "add", "path": "/spec/ingress/-", "value": {"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "ingress-nginx"}}, "podSelector": {"matchLabels": {"app.kubernetes.io/component": "controller"}}}], "ports": [{"port": 3000, "protocol": "TCP"}]}}
]'
```
```
# Alertmanager
kubectl patch networkpolicy -n monitoring alertmanager-main --type='json' -p='[
  {"op": "add", "path": "/spec/ingress/-", "value": {"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "ingress-nginx"}}, "podSelector": {"matchLabels": {"app.kubernetes.io/component": "controller"}}}], "ports": [{"port": 9093, "protocol": "TCP"}, {"port": 8080, "protocol": "TCP"}]}}
]'
```
```
# Blackbox Exporter
kubectl patch networkpolicy -n monitoring blackbox-exporter --type='json' -p='[
  {"op": "add", "path": "/spec/ingress/-", "value": {"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "ingress-nginx"}}, "podSelector": {"matchLabels": {"app.kubernetes.io/component": "controller"}}}], "ports": [{"port": 9115, "protocol": "TCP"}, {"port": 19115, "protocol": "TCP"}]}}
]'
```