这份 README 文档专门为生产环境设计，涵盖了 **K8s 内部 MariaDB** 和 **外部传统 MySQL** 两种对接场景。它基于 `kube-prometheus` 官方文件进行手术级修改，确保监控面板不丢失。

---

# Grafana 生产级持久化部署手册 (基于 kube-prometheus)

本项目是对 `kube-prometheus` (v12.4.1) 官方 Grafana 部署方案的增强。通过将数据迁移至 MySQL/MariaDB，解决了 Pod 重启或重建后配置丢失的问题。

##  修改逻辑说明 (Why we do this?)

我们对官方原始 YAML 进行了以下核心改动：

1.  **文件来源**：`grafana-deployment.yaml` 和 `grafana-config.yaml`。
2.  **环境变量注入**：在 `containers` 中新增了 `envFrom`，通过 `Secret` 动态解耦数据库连接信息。
3.  **精准挂载技术 (关键)**：
    * **官方原生**：使用 `mountPath: /etc/grafana` 直接覆盖整个目录。这会导致容器内 `/etc/grafana/provisioning` (存储官方面板的目录) 被清空。
    * **本项目修改**：改用 `subPath: grafana.ini` 挂载。仅替换配置文件，**保留**官方预设的所有监控面板。
4.  **数据库驱动切换**：在 `grafana.ini` 中显式配置 `[database]` 段落，强制 Grafana 弃用 SQLite。

---

##  第一步：准备数据库环境 (二选一)

### 场景 A：使用 K8s 内部 MariaDB (推荐用于实验/全栈环境)
直接运行本项目提供的 StatefulSet 脚本：
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-mysql.yaml
```
* **数据库地址**：`mysql-grafana.monitoring:3306`
* **存储类要求**：需存在 `sc-nfs`。

### 场景 B：使用外部传统 MySQL (推荐用于高可用生产环境)
在你的物理机/虚拟机 MySQL 上执行：
```sql
CREATE DATABASE grafana DEFAULT CHARACTER SET utf8mb4;
CREATE USER 'grafana_user'@'%' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON grafana.* TO 'grafana_user'@'%';
FLUSH PRIVILEGES;
```
* **数据库地址**：你的物理机 IP (如 `192.168.1.100:3306`)。

---

##  第二步：配置连接凭证 (Secret)

你需要创建一个名为 `grafana-db-secret` 的密钥。  
三种方式 三选一 即可  

### 方式 1：手动命令行创建 (推荐，安全快捷)
根据你的场景修改 `GF_DATABASE_HOST` 和密码：
```bash
kubectl create secret generic grafana-db-secret \
  --from-literal=GF_DATABASE_TYPE=mysql \
  --from-literal=GF_DATABASE_HOST=mysql-grafana.monitoring:3306 \
  --from-literal=GF_DATABASE_NAME=grafana \
  --from-literal=GF_DATABASE_USER=grafana_user \
  --from-literal=GF_DATABASE_PASSWORD=your_password \
  -n monitoring
```

### 方式 2：应用 YAML 文件
如果你偏好 GitOps，修改 `grafana-db-secret.yaml` 中的 Base64 编码后执行：
```bash
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-db-secret.yaml
```

---
### 方式 3：场景 B  映射为 K8s 内部 Service（最专业）
如果你希望在 YAML 配置文件中保持域名化，而不是写死 IP，可以为物理机 MySQL 创建一个 ExternalName Service。

1. 创建 Endpoint 和 Service
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-mysql-externalname-svc.yaml
```
具体内容如下：需修改具体IP地址
```
apiVersion: v1
kind: Service
metadata:
  name: external-mysql
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - name: mysql           # 关键点：增加端口名称
    port: 3306            # 集群内访问端口
    targetPort: 3306      # 后端外部数据库端口
    protocol: TCP

---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-mysql
  namespace: monitoring
  labels:
    kubernetes.io/service-name: external-mysql
addressType: IPv4
ports:
  - name: mysql           # 关键点：必须与 Service 中的 name 保持一致
    port: 3306
    protocol: TCP
endpoints:
  - addresses:
      - "10.0.0.101"
    conditions:
      ready: true

```
2. 创建 Secret 时引用 Service 名，需修改your_password  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-db-secret-externalname.yaml
```
```Bash
kubectl create secret generic grafana-db-secret \
  --from-literal=GF_DATABASE_TYPE=mysql \
  --from-literal=GF_DATABASE_HOST=external-mysql:3306 \
  --from-literal=GF_DATABASE_NAME=grafana \
  --from-literal=GF_DATABASE_USER=grafana_user \
  --from-literal=GF_DATABASE_PASSWORD=your_password \
  -n monitoring
```

##  第三步：部署 Grafana 核心组件

按顺序执行以下命令以应用修改后的官方组件：

```bash
# 1. 注入带有 [database] 指令的配置文件  
#    替换kube-prometheus的operator中的`manifests/grafana-config.yaml`
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-config-grafana-db.yaml


# 2. 部署经过 subPath 手术修改的 Deployment  
#    替换kube-prometheus的operator中的`manifests/grafana-deployment.yaml`
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/storage_for_grafana/grafana-deployment-db.yaml
```

---

## ✅ 结果验证
### 1. 在容器内查看环境变量是否切换  
```
kubectl exec -n monitoring deployment/grafana -- env | grep GF_DATABASE
```

### 2. 数据库连通性检查
查看 Grafana 启动日志：
```bash
kubectl logs -f deployment/grafana -n monitoring | grep -i "database"
```

**成功标志**：日志输出 `info="Database: Initializing tables"` 且无 Error。

### 3. 面板完整性检查
登录 Grafana (通常是 NodePort 或 Ingress 地址)，确认左侧 **Dashboards** 列表中：
* ✅ 存在 `Kubernetes / Compute Resources / Cluster` 等官方默认面板。
* ✅ 手动创建的仪表盘在重启 Pod 后依然存在。
* ✅ 切换数据库可能需要重置密码
```
# Grafana 的密码重置方法 admin reset-admin-password 新密码
kubectl exec -it grafana-64944b7f44-pkk76 -n monitoring -- grafana-cli admin reset-admin-password g123456
```

---

##  文件清单对照

| 文件名 | 对应官方原件 | 修改点 |
| :--- | :--- | :--- |
| `grafana-mysql.yaml` | 无 (新增) | 提供内部 MariaDB 运行环境 |
| `grafana-config-grafana-db.yaml` | `grafana-config.yaml` | 增加了 `[database]` 配置段 |
| `grafana-deployment.yaml` | `grafana-deployment.yaml` | 增加了 `envFrom` 与 `subPath` 挂载逻辑 |
| `grafana-db-secret.yaml` | 无 (新增) | 存储数据库敏感连接信息 |

---
**中建四局 K8s 运维团队**
