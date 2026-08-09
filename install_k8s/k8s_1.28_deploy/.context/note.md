# K8s 网络学习手册 · 调研资料库
> 日期: 2026-08-09
> 主题: Kubernetes 网络从零到精通（OSI 模型 + kube-proxy + Service + CNI + 流量路径 + 配置操作）

---

## 路 3：配置操作类（research-ops 已返回,37/39 条已核实）

### 1. kube-proxy 模式修改（不依赖脚本）
- [ops-1.1] 查看模式: `kubectl get cm kube-proxy -n kube-system -o yaml | grep mode` 或 `curl http://localhost:10249/proxyMode` | https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/ | 已核实 | 3源
- [ops-1.2] 修改: `kubectl edit cm kube-proxy -n kube-system` 改 mode 字段 | 同上 | 已核实
- [ops-1.3] 生效: `kubectl rollout restart ds kube-proxy -n kube-system` | 多源 | 已核实
- [ops-1.4] 验证 ipvs: `ipvsadm -Ln`；验证 iptables: `iptables -t nat -L KUBE-SERVICES` | 多源 | 已核实
- [ops-1.5] 切 ipvs 需模块: ip_vs/ip_vs_rr/ip_vs_wrr/ip_vs_sh/nf_conntrack + ipset 包；未满足自动回退 iptables | 官方 | 已核实
- [ops-1.6] 切回 iptables 需 `ipvsadm --clear` 清残留规则 | 腾讯云 | 已核实
- [ops-1.7] IPVS 调度算法: rr(默认)/wrr/lc/wlc/lblc/lblcr/sh/dh/sed/nq/mh (共11种) | 官方 | 已核实
- [ops-1.8] K8s v1.35 起 IPVS 模式标记 deprecated,推荐 nftables | 搜索结果 | 待核实（需确认版本号）

### 2. Service DNS 域名修改（cluster.local）
- [ops-2.1] 查看: `kubectl get cm kubeadm-config -n kube-system -o yaml | grep dnsDomain` | 官方 v1beta3 | 已核实
- [ops-2.2] 新集群: kubeadm-config `networking.dnsDomain` 或 `kubeadm init --service-dns-domain` | 官方 | 已核实
- [ops-2.3] 已有集群: 需同步改 kubelet(clusterDomain) + CoreDNS Corefile + 重启。**极难,生产不建议** | SO | 已核实
- [ops-2.4] 影响: FQDN 变为 `svc.ns.svc.<新域名>` | 官方 | 已核实
- [ops-2.5] 默认值 "cluster.local"(string) | 官方 v1beta3 | 已核实

### 3. Pod/Service 网段修改
- [ops-3.1] Pod CIDR: `--pod-network-cidr` 或 `networking.podSubnet`。**建好后不可安全修改,需重建** | 官方+SO | 已核实
- [ops-3.2] Service CIDR: `--service-cidr` 或 `networking.serviceSubnet`。默认 10.96.0.0/12。**建好后极难改** | 官方 | 已核实
- [ops-3.3] Calico IPPool CIDR **不可原地改**(cidr/blockSize 不可变)。正确:新建→禁旧→滚动重启→删旧 | Calico 3.28 官方 | 已核实
- [ops-3.4] 新 IPPool 的 CIDR 必须落在 cluster CIDR 内 | OneUptime | 已核实

### 4. MetalLB L2 配置
- [ops-4.1] 编辑 IPAddressPool: `kubectl edit ipaddresspool -n metallb-system`(v1beta1) | metallb.io | 已核实
- [ops-4.2] 编辑 L2Advertisement: `kubectl edit l2advertisement -n metallb-system` | metallb.io | 已核实
- [ops-4.3] nodeSelector 限制通告节点(matchLabels/matchExpressions) | metallb.io | 已核实
- [ops-4.4] interfaces 限制网卡(精确名,不支持正则) | metallb.io | 已核实
- [ops-4.5] nodeSelectors + interfaces 是 AND 逻辑 | 同上 | 已核实

### 5. externalTrafficPolicy 修改
- [ops-5.1] 命令: `kubectl patch svc <name> -p '{"spec":{"externalTrafficPolicy":"Local"}}'` | 官方 tutorials/source-ip | 已核实
- [ops-5.2] Local: 保留源 IP,只转本地 Pod,无本地 Pod 则丢包 | 官方 | 已核实
- [ops-5.3] Cluster(默认): 丢源 IP(SNAT),可跨节点转发 | 官方 | 已核实
- [ops-5.4] Local 建议配合 DaemonSet 或 nodeSelector 保证每节点有 Pod | ionos | 已核实
- [ops-5.5] 替代: Proxy Protocol 可在 Cluster 模式传源 IP | ionos | 已核实

### 6. containerd registry 配置
- [ops-6.1] 配置文件: /etc/containerd/config.toml | 官方 | 已核实
- [ops-6.2] sandbox_image: `[plugins."io.containerd.grpc.v1.cri"]` 下 | 官方 | 已核实
- [ops-6.3] SystemdCgroup: `...runtimes.runc.options` 下(顶层已废弃) | 官方+GitHub | 已核实
- [ops-6.4] 新式 registry mirror: config_path="/etc/containerd/certs.d" | containerd hosts.md | 已核实
- [ops-6.5] hosts.toml 字段: server/capabilities/skip_verify/ca | containerd hosts.md | 已核实
- [ops-6.6] 生效: systemctl restart containerd | 已核实
- [ops-6.7] 旧式 registry.mirrors/registry.configs 已废弃 | containerd hosts.md | 已核实

### 官方文档链接汇总
- kube-proxy: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/
- Service: https://kubernetes.io/docs/concepts/services-networking/service/
- Source IP: https://kubernetes.io/docs/tutorials/services/source-ip/
- kubeadm config v1beta3: https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/
- MetalLB: https://metallb.io/configuration/
- containerd: https://github.com/containerd/containerd/blob/main/docs/hosts.md
- Container Runtimes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/

---

## 路 1：原理架构类（research-arch,进行中）
> 等待中...

## 路 2：数据面流量类（research-cni,进行中）
> 等待中...
