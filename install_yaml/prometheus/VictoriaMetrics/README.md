# VictoriaMetrics 对接 Prometheus 部署文档

## 1. 相关链接

- VictoriaMetrics Operator 项目：<https://github.com/VictoriaMetrics/operator>
- lzq 文档：[VictoriaMetrics/operator 安装作为 Prometheus 持久化储存文档](https://www.yuque.com/jianglai-iayzx/sa1zul/podq5g7kxggtzots#sdwVE)

---

## 2. 部署

> 前提：已安装 Prometheus Operator 并配置 Ingress，集群存在默认 StorageClass（可用 `kubectl get storageclass` 确认）。

### 2.1 部署 VM Operator

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/install-no-webhook-lzq-0.68.3.yaml
```

### 2.2 创建 VM 实例（存储层）

根据场景选择其中一种：

**场景 A：单机版（极简高效）**

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/vm-single.yaml
```

**场景 B：集群版（高可用，推荐生产使用）**

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/vm-cluster.yaml
```

**验证**

```bash
kubectl get pod -n vm
```

---

### 2.3 对接 Prometheus（数据同步）

将 Prometheus 的 remoteWrite 指向 VM：

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/prometheus-prometheus-vm.yaml
```

核心修改内容：

```yaml
spec:
  remoteWrite:
    # 单机版地址（二选一）
    # - url: "http://vmsingle-vm-database.vm.svc:8429/api/v1/write"

    # 集群版地址（二选一）
    - url: "http://vminsert-vm-cluster-ha.vm.svc:8480/insert/0/prometheus/api/v1/write"
      # vminsert-vm-cluster-ha：写入层 Service 名
      # 8480：vminsert 默认端口
      # /insert/0/prometheus/...：集群版固定路径，'0' 代表租户 ID
```

可选：重启 Prometheus 使配置快速生效：

```bash
kubectl rollout restart sts -n monitoring prometheus-k8s
# 或直接删除 Pod
kubectl delete pod -n monitoring prometheus-k8s-0 prometheus-k8s-1
```

**验证**

① 在 Prometheus Web 查询以下指标，有值说明 remote_write 连接成功：

```
prometheus_remote_storage_samples_total
```

② 直接查询 VM 是否包含数据：

```bash
# 端口转发 vmselect
kubectl port-forward -n vm svc/vmselect-vm-cluster-ha 8481:8481 > /dev/null 2>&1 &

# 查询典型指标
curl -G 'http://localhost:8481/select/0/prometheus/api/v1/query' \
  --data-urlencode 'query=kube_node_info'

# 验证完毕后关闭端口转发
kill %1
```

---

## 3. 指标去重（集群版 + 双副本必须配置）

### 3.1 为什么需要去重

kube-prometheus 默认部署两个 Prometheus 副本（`prometheus-k8s-0` 和 `prometheus-k8s-1`）以实现高可用。两个副本采集相同指标并同时写入 VM，若不处理，查询时同一指标会出现两条，导致 Grafana 图表双线、告警重复触发等问题。

VM 的去重机制（`dedup.minScrapeInterval`）要求**写入的时间序列标签集完全一致**才能识别为同一序列并去重。Prometheus Operator 默认会为每个副本注入不同值的 `prometheus_replica` 标签（如 `prometheus-k8s-0` / `prometheus-k8s-1`），导致两副本数据被 VM 视为两条不同序列，去重失效。因此，**必须在写入前通过 `writeRelabelConfigs` 将该标签 drop 掉**，使两副本写入 VM 的标签集完全一致，VM 才能正常去重。

---

### 3.2 方案说明

本文采用**写入前 drop `prometheus_replica` 标签**的方案：

| 维度 | 说明 |
|------|------|
| 原理 | 写入前 drop 区分标签，两副本标签集相同，VM 视为同一序列并去重 |
| 存储层数据 | 去重后只保留一份（后写覆盖先写） |
| HA 可靠性 | VM 自身 `replicationFactor: 2` 在存储层提供冗余；Prometheus 双副本保证采集连续性 |
| Prometheus 配置 | 需配置 `writeRelabelConfigs` drop 标签 |
| Grafana 配置 | 无需额外配置，数据在存储层已去重 |
| 适用场景 | 生产环境通用推荐方案 |

> **注意**：`externalLabels`（如 `cluster`、`env`）是业务维度标签，用于多集群区分，与去重无关，不能替代 drop `prometheus_replica`。

---

### 3.3 现象确认（可选）

```bash
kubectl port-forward -n vm svc/vmselect-vm-cluster-ha 8481:8481 > /dev/null 2>&1 &

# 同一个 instance 出现多次即为重复（dedup=false 关闭去重查看原始数据）
curl -s 'http://localhost:8481/select/0/prometheus/api/v1/query?query=up&dedup=false' \
  | grep -o '"instance":"[^"]*"' \
  | sort | uniq -c

kill %1
```

输出示例（未去重时，每个 instance 出现两次）：

```
2 "instance":"10.0.0.101:10250"
2 "instance":"10.0.0.101:6443"
```

---

### 3.4 配置 Prometheus

添加统一的业务标签，并通过 `writeRelabelConfigs` drop `prometheus_replica` 标签。

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/prometheus-prometheus-vm-dedup.yaml
```

核心修改内容：

```yaml
spec:
  # 统一业务标签，方便多集群区分（与去重无关）
  externalLabels:
    cluster: my-k8s-cluster   # 替换为实际集群标识
    env: prod                  # 替换为实际环境

  remoteWrite:
    - url: "http://vminsert-vm-cluster-ha.vm.svc:8480/insert/0/prometheus/api/v1/write"
      writeRelabelConfigs:
        - action: labeldrop
          regex: prometheus_replica   # 关键：drop 区分标签，使两副本写入标签集完全一致
      queueConfig:
        capacity: 25000
        maxSamplesPerSend: 10000
        # maxShards: 200
        # batchSendDeadline: 5s
```

> ⚠️ `pod` 标签不需要 drop，它代表被采集对象的 pod 名称，是正常业务维度标签，必须保留，否则按 pod 维度的查询和告警会失效。

重启 Prometheus 使配置生效：

```bash
kubectl rollout restart sts -n monitoring prometheus-k8s
```

---

### 3.5 配置 VictoriaMetrics（vmselect 开启查询层去重）

在 `vmselect` 的 `extraArgs` 中开启去重参数。

> ⚠️ `dedup.minScrapeInterval` 必须与实际 `scrape_interval` 对齐。kube-prometheus 默认为 `30s`，如有修改请按实际值填写。

```bash
# 查看 Prometheus 的全局 scrape_interval
kubectl get prometheus k8s -n monitoring -o jsonpath='{.spec.scrapeInterval}'
```

> 如果不同 job 有不同的 scrape_interval，应选择最小值，否则部分慢采集的指标可能被错误去重。

**方式一：apply YAML 文件**

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/vm-cluster-dedup.yaml
```

核心修改内容（在 `spec.vmselect` 下新增 `extraArgs`）：

```yaml
spec:
  vmselect:
    extraArgs:
      replicationFactor: "2"
      dedup.minScrapeInterval: "30s"   # 与 Prometheus scrape_interval 对齐
```

> `replicationFactor: "2"` 告诉 vmselect 查询时需从多个 vmstorage 节点获取数据并去重内部副本，与 Prometheus HA 去重是两件独立的事。

**方式二：直接编辑**

```bash
kubectl edit vmcluster vm-cluster-ha -n vm
```

保存后 Operator 自动触发滚动重启。

---

### 3.6 验证去重效果
> ⚠ 可以先查询配置是否生效，指标去重查询可能需要5分钟左右才会生效
```bash
kubectl port-forward -n vm svc/vmselect-vm-cluster-ha 18481:8481 > /dev/null 2>&1 &
```

**第一步：确认 prometheus_replica 标签已被 drop**

```bash
# 查询 up 指标，确认结果中不含 prometheus_replica 标签
curl -s 'http://localhost:18481/select/0/prometheus/api/v1/query?query=up&dedup=false' \
  | python3 -m json.tool | grep -c 'prometheus_replica'
```

✅ 预期：输出 `0`，说明 `prometheus_replica` 标签已在写入前被成功 drop。

❌ 若输出非 0：说明 `writeRelabelConfigs` 未生效，检查 Prometheus 是否已重启，配置是否正确。

**第二步：确认 vmselect 去重参数已生效**

```bash
kubectl exec -n vm vmselect-vm-cluster-ha-0 -- \
  cat /proc/1/cmdline | tr '\0' '\n' | grep -E 'dedup|replication'
```

✅ 预期：

```
-dedup.minScrapeInterval=30s
-replicationFactor=2
```

**新增第三步：确认双副本都在正常写入**

```bash
# 分别查看两个副本的 remote_write 成功样本数
kubectl exec -n monitoring prometheus-k8s-0 -- \
  wget -qO- http://localhost:9090/metrics | grep prometheus_remote_storage_samples_total

kubectl exec -n monitoring prometheus-k8s-1 -- \
  wget -qO- http://localhost:9090/metrics | grep prometheus_remote_storage_samples_total
```

✅ 预期：两个命令都返回非零且持续增长的值，说明双副本均在正常写入 VM。

❌ 若某个副本返回 0 或命令报错：检查该 Pod 是否正常运行，以及 remoteWrite url 是否可达。

---


**第四步：验证查询层去重效果（核心）**

```bash
# 关闭去重：两个副本各贡献一份，总数翻倍
curl -s 'http://localhost:18481/select/0/prometheus/api/v1/query?query=count%28up%29+by+%28job%2Cinstance%29&dedup=false' \
  | python3 -m json.tool | grep -c '"metric"'

# 默认去重（不加 dedup=false）：每个 job+instance 合并为一份
curl -s 'http://localhost:18481/select/0/prometheus/api/v1/query?query=count%28up%29+by+%28job%2Cinstance%29' \
  | python3 -m json.tool | grep -c '"metric"'
```

✅ 预期：两次查询返回**相同数量**。

> 与之前不同：drop 标签后两副本写入的是同一序列，存储层已经去重，所以 `dedup=false` 和默认查询的结果数量应当一致（或非常接近）。若 `dedup=false` 明显多于默认查询，说明 drop 未生效，仍有残余重复数据。

**第五步：确认业务数据正常**

```bash
# 确认 cluster/env 等业务标签正常附加
curl -s 'http://localhost:18481/select/0/prometheus/api/v1/query?query=up%7Bjob%3D"kubelet"%7D' \
  | python3 -m json.tool | grep -E '"cluster"|"env"|"prometheus_replica"'
```

✅ 预期：能看到 `cluster` 和 `env` 标签，**不出现** `prometheus_replica` 标签。

**整体判断标准**

| 检查项 | ✅ 正常 | ❌ 异常及排查方向 |
|--------|---------|-----------------|
| prometheus_replica 标签 | 查询结果中不存在该标签 | 仍存在，检查 writeRelabelConfigs 及 Prometheus 重启状态 |
| vmselect dedup 参数 | `minScrapeInterval=30s`，`replicationFactor=2` | 参数缺失，检查 VMCluster extraArgs |
| dedup=false vs 默认查询数量 | 两者数量一致或非常接近 | dedup=false 明显偏多，说明仍有重复数据写入 |
| 业务标签 | cluster/env 标签存在 | 缺失，检查 externalLabels 配置及 Prometheus 重启状态 |

```bash
# 验证完毕后关闭端口转发
kill %1
```

---

## 4. 修改 Grafana 数据源

将数据源从 Prometheus 切换为 VictoriaMetrics。

由于采用 drop 标签方案，存储层数据已去重，Grafana 数据源**无需配置** `customQueryParameters`，直接指向 vmselect 即可，kube-prometheus 自带 dashboard 无需任何改动。

```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/VictoriaMetrics/grafana-dashboardDatasources-vm.yaml
```

数据源配置完整内容：

```yaml
apiVersion: v1
kind: Secret
metadata:
  labels:
    app.kubernetes.io/component: grafana
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: kube-prometheus
    app.kubernetes.io/version: 12.4.1
  name: grafana-datasources
  namespace: monitoring
stringData:
  datasources.yaml: |-
    {
        "apiVersion": 1,
        "datasources": [
            {
                "access": "proxy",
                "editable": false,
                "name": "VictoriaMetrics",
                "uid": "victoriametrics-datasource",
                "orgId": 1,
                "type": "prometheus",
                "url": "http://vmselect-vm-cluster-ha.vm.svc:8481/select/0/prometheus/",
                "isDefault": true,
                "version": 1
            }
        ]
    }
type: Opaque
```

> ⚠️ Grafana 默认使用 SQLite 存储配置，文件位于容器内 `/var/lib/grafana/grafana.db`。未配置持久化存储时 Pod 重启后数据丢失，建议配置 PVC 或通过环境变量 `GF_SECURITY_ADMIN_PASSWORD` 注入初始密码。

忘记密码时重置：

```bash
kubectl exec -it <grafana-pod-name> -n monitoring -- \
  grafana-cli admin reset-admin-password <新密码>
```

**验证**

```bash
# 验证 Secret 内容是否正确
kubectl get secret -n monitoring grafana-datasources \
  -o jsonpath='{.data.datasources\.yaml}' | base64 -d

# 端口转发 Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &

# 验证数据源（替换为实际密码）
curl -s -u admin:<密码> http://localhost:3000/api/datasources \
  | jq '.[] | {name, type, url, jsonData}'

kill %1
```

✅ 预期输出：

```json
{
  "name": "VictoriaMetrics",
  "type": "prometheus",
  "url": "http://vmselect-vm-cluster-ha.vm.svc:8481/select/0/prometheus/",
  "jsonData": {}
}
```