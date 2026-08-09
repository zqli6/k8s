# K8s 网络学习手册 · 教学设计大纲
> 日期: 2026-08-09
> 主题: Kubernetes 网络从零到精通
> 复杂度: 复杂档（分布式、多组件协作、需深原理）
> 目标文件: F:\Claude\virtual-k8s\docs\k8s-network-guide.md

---

## 学习路径四层结构

### 零基础层（15%）——"这是什么"
- OSI 七层模型概念（L1-L7 每层一句话定义 + 通俗类比）
- K8s 网络要解决什么问题（Pod 间通信、Service 发现、外部暴露）
- 三个核心术语建立（Pod IP、Service ClusterIP、外部 VIP）
- 前置依赖：无

### 入门层（25%）——"怎么工作的"
- kube-proxy 是什么、干什么（四层代理的概念）
- Service 四种类型与各自的"可达范围"
- CNI 插件的角色（谁负责给 Pod 分 IP 和建网络）
- Pod 同主机通信 vs 跨主机通信的本质区别
- 前置依赖：需先讲解 OSI 模型 + Pod IP 概念

### 进阶层（35%）——"每种模式怎么走"
- kube-proxy 三种模式的数据面差异（iptables/IPVS/nftables）
- Service 四种类型的精确流量路径（mermaid 图）
- externalTrafficPolicy Local vs Cluster
- MetalLB L2 + Ingress 的完整链路
- Flannel/Calico/Cilium 每种模式的同主机+跨主机流量路径
- 虚拟网卡清单（cni0/flannel.1/caliXXX/tunl0/vxlan.calico/lxcXXX/kube-ipvs0）
- 前置依赖：需先讲解 kube-proxy 概念 + CNI 角色 + OSI L2-L4 区别

### 精通层（25%）——"怎么改、会出什么问题"
- 查看/修改 kube-proxy 模式（脚本方式 + 不依赖脚本直接改）
- 修改 Service DNS 域名（cluster.local → 自定义）
- 修改 Pod/Service/Calico 网段
- MetalLB L2 的限制与排障（为什么 ping 不通 VIP、ARP 泄漏）
- CNI 选型决策框架
- 前置依赖：需先讲解完整流量路径 + 各模式虚拟网卡

---

## 共享术语表

| 术语 | 通俗类比 | 首次讲解章节 | 适用层级 | 备注 |
|------|---------|------------|---------|------|
| OSI 七层模型 | 快递系统分 7 层：从包装到运输到签收 | 1.网络基础 | 全局 | 避免"协议栈"一词先出现 |
| L2(数据链路层) | 同一栋楼内送信——只认门牌号(MAC)，只在本楼(广播域)内有效 | 1.网络基础 | 全局 | MetalLB/ARP/交换机在此层 |
| L3(网络层) | 跨城寄信——认地址(IP)，需要路由器转发 | 1.网络基础 | 全局 | Pod IP/路由/IPIP封装 |
| L4(传输层) | 信送到后——认具体哪间房(端口号)，TCP/UDP | 1.网络基础 | 全局 | kube-proxy/IPVS/Service 端口 |
| L7(应用层) | 信打开后——读内容决定干什么(HTTP Host/Path) | 1.网络基础 | 全局 | Ingress Controller |
| Pod IP | 每个 Pod 的"身份证号"——集群内唯一、直接可达 | 2.K8s网络模型 | 全局 | |
| ClusterIP | Service 的"虚拟总机号"——只在集群内有效，背后转接到真正的 Pod | 3.Service | 全局 | |
| NodePort | 在每个节点开一个"窗口"(30000-32767)，外部通过节点 IP:窗口号访问 | 3.Service | 全局 | |
| LoadBalancer | 给 Service 分配一个"公网 VIP"——外部直接访问这个 IP | 3.Service | 全局 | MetalLB 提供 |
| kube-proxy | 每个节点上的"四层转发员"——把到 Service 的流量转到实际 Pod | 2.kube-proxy | 全局 | |
| IPVS | 内核级"高速路由表"——比 iptables 快，用哈希查找 O(1) | 4.kube-proxy模式 | 入门层起 | |
| kube-ipvs0 | IPVS 模式专属的"占位网卡"——不收发流量，只给 IPVS 规则挂 VIP 用 | 4.kube-proxy模式 | 进阶层 | dummy 类型 |
| CNI | 容器网络接口——给 Pod"接网线+分 IP"的插件标准 | 2.CNI 角色 | 全局 | |
| veth pair | 一对虚拟网线——一头在 Pod 里(eth0)，一头在宿主机(连桥或路由) | 5.Pod通信 | 入门层起 | |
| cni0 | Flannel 的虚拟交换机——同主机 Pod 在这里二层互通 | 6.Flannel | 进阶层 | Linux bridge |
| flannel.1 | Flannel VXLAN 的"隧道出口"——负责把包封装成 UDP 发到对端节点 | 6.Flannel | 进阶层 | VTEP |
| caliXXXXXXXX | Calico 给每个 Pod 的"专线接口"——配合 /32 路由实现隔离 | 6.Calico | 进阶层 | |
| tunl0 | Calico IPIP 模式的"隧道口"——负责 IP-in-IP 封装 | 6.Calico | 进阶层 | |
| eBPF | 内核里的"可编程快递员"——不走传统 iptables 规则链，直接在内核态转发 | 6.Cilium | 进阶层 | |
| externalTrafficPolicy | 外部流量的"转发策略"——Cluster(允许跨节点)还是 Local(只转本地) | 7.ETP | 进阶层 | |
| ARP | "喊话找人"——在 L2 广播域内问"谁是这个 IP"，对方回 MAC 地址 | 1.网络基础 | 全局 | MetalLB L2 靠它 |
| DNAT | 改目的地——kube-proxy 把"发给 Service VIP"的包改成"发给具体 Pod" | 4.kube-proxy模式 | 入门层起 | |
| SNAT | 改发件人——让回包能沿原路返回（隐藏真实源 IP） | 7.ETP | 进阶层 | |

---

## 文档章节与学习层级映射

| 章节编号 | 章节标题 | 学习层级 | Diátaxis 心智 | 对应术语表 |
|---------|---------|---------|-------------|-----------|
| 1 | 网络基础：OSI 七层与 K8s | 零基础 | Explanation | OSI/L2/L3/L4/L7/ARP |
| 2 | K8s 网络模型与核心组件 | 入门 | Explanation | Pod IP/kube-proxy/CNI |
| 3 | Service 四种类型 | 入门 | Explanation + Reference | ClusterIP/NodePort/LB/EN |
| 4 | kube-proxy 代理模式详解 | 进阶 | Explanation + How-to | IPVS/kube-ipvs0/DNAT |
| 5 | Pod 间通信：同主机 vs 跨主机 | 进阶 | Explanation | veth/cni0/路由 |
| 6 | CNI 插件对比与流量路径 | 进阶 | Explanation + Reference | Flannel/Calico/Cilium 全部 |
| 7 | 外部流量完整路径 | 进阶 | Explanation | MetalLB/Ingress/ETP/SNAT |
| 8 | 配置修改操作手册 | 精通 | How-to + Reference | 所有配置项 |
| 9 | 故障排查与典型问题 | 精通 | How-to | ARP泄漏/ping不通/VXLAN冲突 |
| 附录 | 虚拟网卡速查 + 官方链接 | Reference | Reference | 全部网卡 |

---

## 关键依赖关系（不可跳过）

- 讲 kube-proxy(§4) → 需先讲 OSI L4 概念(§1) + Service 概念(§3)
- 讲 IPVS 的 kube-ipvs0(§4) → 需先讲 L2 ARP 概念(§1)
- 讲 CNI 流量路径(§6) → 需先讲 Pod 通信基础(§5) + veth pair 概念
- 讲 MetalLB L2 为什么 ping 不通(§9) → 需先讲 L4 IPVS 只处理端口流量(§4) + L3 ICMP 概念(§1)
- 讲 externalTrafficPolicy(§7) → 需先讲 SNAT/DNAT 概念(§4)

---

## 已确认的调研来源（路3 已返回,路1/2 进行中）

- kube-proxy 官方: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/
- Service 官方: https://kubernetes.io/docs/concepts/services-networking/service/
- Source IP: https://kubernetes.io/docs/tutorials/services/source-ip/
- kubeadm config: https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/
- MetalLB: https://metallb.io/configuration/
- containerd hosts: https://github.com/containerd/containerd/blob/main/docs/hosts.md
- Container Runtimes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/

---

## 状态标注

- 路3(ops)调研完成:37/39 条已核实(1 条待核实:IPVS v1.35 deprecated 版本号)
- 路1(arch)进行中:OSI 七层、kube-proxy 原理、Service 类型精确流量路径
- 路2(cni)进行中:三种 CNI 每种模式精确流量路径+虚拟网卡
