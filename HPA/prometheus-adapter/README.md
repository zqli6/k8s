# Kubernetes HPA 基于 Prometheus 自定义指标扩缩容实战

本项目演示了如何通过 `prometheus-adapter` 采集业务 Pod 的自定义 HTTP QPS 指标，并驱动 **HorizontalPodAutoscaler (HPA v2)** 实现自动扩缩容。

## 🚀 部署流程速览

### 1. 基础环境准备
首先需要安装 Prometheus 监控系统及相关的 Operator。
* **参考文档**: [LZQ雨雀 部署文档](https://www.yuque.com/office/yuque/0/2026/pdf/61945248/1776278242382-25897578-e08d-44a4-9300-2d92696eccd7.pdf)
* **安装包**: [LZQ Gitee Prometheus 安装源](https://gitee.com/zqli6/prometheus)

### 2. 部署自定义指标路由 (APIService)
这是关键的一步，它在 K8s API 中注册自定义指标组，将请求转发给 Adapter。
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/prometheus-adapter/custom-metrics-apiservice.yaml
```

### 3. 部署测试应用 (Metrics App)
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/prometheus-adapter/metrics-example-app.yaml
```

### 4. 开启指标采集 (ServiceMonitor)
让 Prometheus 能够发现并抓取测试应用的指标数据。
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/prometheus-adapter/metrics-app-sm.yaml
```

### 5. 配置指标转换规则 (Adapter)
定义 Prometheus 原始数据到 K8s 指标的映射逻辑。
```bash
# 覆盖 Adapter 配置
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/prometheus-adapter/custom-metrics-config-map.yaml
# 重启以加载新规则
kubectl rollout restart deployment -n monitoring prometheus-adapter
```

### 6. 部署 HPA 策略
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/prometheus-adapter/metrics-app-hpa.yaml
```

---

## 🛠 资源清单深度说明

| 资源文件 | 作用项 | 核心逻辑点 |
| :--- | :--- | :--- |
| **custom-metrics-apiservice.yaml** | **API 注册中心** | **必不可少**。它告诉 K8s：如果你想要 `custom.metrics.k8s.io` 的数据，请去找 `monitoring` 命名空间下的 `prometheus-adapter` 服务。 |
| **metrics-example-app.yaml** | **业务应用源** | 使用 `statsd-exporter` 镜像。Service 暴露 80 端口，后端 Pod 监听 9102 端口。 |
| **metrics-app-sm.yaml** | **采集配置** | 关联 Service 到 Prometheus。必须携带 `release: prometheus-k8s` 标签，否则 Prometheus 无法识别。 |
| **custom-metrics-config-map.yaml** | **计算工厂** | 核心规则定义。通过 `sum(rate(...[1m]))` 将 Prometheus 的**累计请求总数**转换为**每秒请求数 (QPS)**。 |
| **metrics-app-hpa.yaml** | **扩缩容大脑** | 设定目标为 `averageValue: 3`。当平均每个 Pod 的 QPS 超过 3 时，触发扩容。 |

---

## 📊 指标收集与计算原理

为了实现“通过正常 curl 访问即扩容”，链路逻辑如下：

1.  **产生压力**: 用户通过 `curl` 访问 `http://<Service-IP>/metrics`。
2.  **指标变动**: `statsd-exporter` 内部的 `promhttp_metric_handler_requests_total` 计数器随访问上涨。
3.  **数据抓取**: Prometheus 每 15s 抓取一次该值。
4.  **转换暴露**: Adapter 通过 APIService 接收到 HPA 的请求，去 Prometheus 执行 Rate 运算，并将结果以 `http_requests_per_second` 的名义返回给 K8s。

---

## 🧪 验证与压力测试

### 1. 检查指标管道是否通畅
使用以下命令直接从 API 获取自定义指标数据，若能看到具体数值（如 `300m`），说明链路已通：
```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second" | jq
```

### 2. 执行压力测试
```bash
# 查看svc中ClusterIP
kubectl get svc

# 疯狂 curl 访问 metrics 路径产生 QPS 指标
while true; do curl -s http://<Cluster IP>/metrics > /dev/null; done
```

### 3. 监控 HPA 状态
```bash
kubectl get hpa metrics-app-hpa -w
```
你会看到 `TARGETS` 字段从 `0/3` 变为类似 `10273m/3`（代表 QPS 约为 10.2），随后 `REPLICAS` 会从 2 自动增长到 10。

---

## ⚠️ 避坑总结
* **APIService 状态**: 如果 `kubectl get apiservice` 看到 `v1beta1.custom.metrics.k8s.io` 的 `AVAILABLE` 为 `False`，请检查 Adapter 容器是否正常运行。
* **路径关键**: 必须访问 `/metrics` 路径，因为 `statsd-exporter` 镜像的 HTTP 计数器只在该接口触发。
* **重启机制**: 修改 `ConfigMap` 后一定要 `rollout restart` Adapter 容器，否则新指标不会生效。
