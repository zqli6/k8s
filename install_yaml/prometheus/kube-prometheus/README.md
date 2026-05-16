# 相关网址
1. 官方GitHub  
<https://github.com/prometheus-operator>  
2. lzq文档  
[lzq的Prometheus_operator部署文档](https://www.yuque.com/jianglai-iayzx/sa1zul/dx8a87iezrmbz6yu#Reegb)  

# 部署
使用lzq的自定义tar.gz  
1.下载  
  1.swr镜像加速0.17.0  
```
wget https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-prometheus/kube-prometheus-0.17.0-lzq.tar.gz
```
  2.官方下载  
```
VERSION=0.17  # 修改为对应版本
wget https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v${VERSION}.0.tar.gz
```
2. 启动项目
```
cd /usr/local/kube-prometheus-0.17.0
kubectl apply -f manifests/setup/

#如果提示Too long出错,使用下面解决继续执行下面步骤
kubectl create -f manifests/setup/
kubectl apply -f manifests/
```
3. 创建ingress  
**需先安装[ingress controller](https://gitee.com/zqli6/k8s/tree/main/ingress)管理ingress**  
**安装[metalLB](https://gitee.com/zqli6/k8s/tree/main/metalLB)分配地址池**  
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-prometheus/kube-prometheus-ingress.yaml
```
```
[root@master1 ~ ]# kubectl describe ingress -n monitoring 
         ···
Address:          10.0.0.10,10.0.0.99
         ··· 
Rules:
  Host                   Path  Backends
  ----                   ----  --------
  prometheus.lzq.org        prometheus-k8s:9090 (10.244.3.51:9090,10.244.2.42:9090)
  grafana.lzq.org           grafana:3000 (10.244.3.36:3000)
  alertmanager.lzq.org      alertmanager-main:9093 (10.244.3.39:9093,10.244.2.33:9093,10.244.1.25:9093)
  blackbox.lzq.org          blackbox-exporter:19115 (10.244.3.35:19115)
         ...
```
登录web端访问`prometheus.lzq.org`,`grafana.lzq.org`,`alertmanager.lzq.org`,`blackbox.lzq.org`

注意：Grafana 默认使用 SQLite 数据库存储所有配置数据（用户、密码、仪表盘等），数据库文件位于容器内的 /var/lib/grafana/grafana.db。若未配置持久化存储，Pod 重启后该文件丢失，导致数据重置
```
# Grafana 的密码重置方法 admin reset-admin-password 新密码
kubectl exec -it grafana-64944b7f44-pkk76 -n monitoring -- grafana-cli admin reset-admin-password g123456
```

4. 测试文件的创建
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-prometheus/probe-example.yaml
```
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/install_yaml/prometheus/kube-prometheus/servicemonitor-example.yaml
```

5. 开发相关端口及权限  
```
┌─────────────────────────────────────────────────────────┐
│                    生产环境架构                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Prometheus (monitoring namespace)                      │
│      ↓ 需要抓取                                          │
│  Controller-Manager (kube-system namespace)             │
│      ↑ 需要修改 --bind-address=0.0.0.0                   │
│                                                         │
│  用户浏览器                                              │
│      ↓ 需要访问                                          │
│  Ingress (ingress-nginx namespace)                      │
│      ↓ 转发到                                            │
│  Prometheus Service (monitoring namespace)              │
│      ↑ 需要 NetworkPolicy 允许 Ingress 访问              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```
   1. 开放相关地址  
   ```
   #修改kube-controller-manager的监听地址
   vim /etc/kubernetes/manifests/kube-controller-manager.yaml
   grep bind /etc/kubernetes/manifests/kube-controller-manager.yaml
       - --bind-address=0.0.0.0
   #修改kube-scheduler的监听地址
   vim /etc/kubernetes/manifests/kube-scheduler.yaml
   grep bind /etc/kubernetes/manifests/kube-scheduler.yaml
       - --bind-address=0.0.0.0
   ```
   2. networkpolicy白名单  
   [lzq的文档可以查看](https://www.yuque.com/jianglai-iayzx/sa1zul/dx8a87iezrmbz6yu#hYxbH)  
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
   ```

