# Ubuntu 系列 · 部署验证清单

> 用于在 `10.0.0.100~103`（Ubuntu 24.04 noble，root 免密）上手動部署时对照。
> 拓扑：master1/2/3 = 10.0.0.100/101/102，node1 = 10.0.0.103，VIP = 10.0.0.200。
> 全部软件源/镜像源均为国内可访问（阿里云 / DaoCloud / gitee / SWR）。

---

## 一、前置核对（先做，避免后面白跑）

| 项 | 检查命令 | 预期 |
|----|---------|------|
| 节点能互免密 | 在 100 上 `ssh root@10.0.0.101 echo ok` | 输出 ok（101/102/103 都试） |
| 能访问外网 | `curl -sI https://mirrors.aliyun.com | head -1` | HTTP/1.1 200 或 301 |
| VIP 空闲 | `ping -c1 10.0.0.200` | 不通（未占用） |
| codename | `cat /etc/os-release \| grep VERSION_CODENAME` | noble |

---

## 二、online 版部署（验证主流程）

```bash
# 在你本地：推脚本到 master1
scp -r ubuntu/online/ root@10.0.0.100:/opt/k8s-deploy/
ssh root@10.0.0.100
cd /opt/k8s-deploy/ubuntu/online/scripts && chmod +x *.sh

# 先干跑看计划（不执行）
./deploy-all.sh --dry-run
```

预期：打印 3 Master + 1 Worker 拓扑、VIP 10.0.0.200、按 phase 0~9 列出计划，不 ssh。

```bash
./deploy-all.sh
```

逐步预期：

| Phase | 脚本 | 预期结果 |
|-------|------|---------|
| 0 | 00-env-check | 全部节点「0 错误」，最多少量警告 |
| 1 | 01-system-init | 每节点 hostname 正确、swap 0、AppArmor enabled |
| 2 | 02-install-containerd | containerd 版本、SystemdCgroup=true、sandbox=pause:3.9 |
| 3 | 03-install-k8s | kubeadm v1.28.15、apt-mark hold 已锁定 |
| 4 | 04-init-master1 | kubeadm init 成功，master1 变 Ready |
| 5 | 05-join-master | master2/3 加入，etcd 健康（串行） |
| 6 | 06-join-worker | node1 加入 |
| 7 | 07-install-calico | calico-node 3/3 或 4/4 Ready，节点全 Ready |
| 8 | 08-renew-certs | 每 master apiserver 证书续到 ~10 年 |
| 9 | 09-verify | 全绿，PASS=N FAIL=0 |

部署后手动复核：

```bash
kubectl get nodes -o wide          # 4 节点全 Ready
kubectl get pods -n kube-system    # 控制面/kube-vip/calico/coredns/kube-proxy 全 Running
ipvsadm -Ln | head                 # IPVS 模式有规则
kubectl get --raw='/healthz/etcd'  # ok
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate   # 到期 ~2036
```

---

## 三、offline 版：制备 + 部署

### 制备（在能外网的 Ubuntu 上，如 10.0.0.100）

```bash
cd ubuntu/offline/scripts && chmod +x *.sh
./fetch-resources.sh
```

预期产物（`ubuntu/offline/` 下）：
- `packages/*.deb` + `Packages.gz`（几十个 deb）
- `images/k8s-core.tar`、`calico.tar`、`kube-vip.tar`
- `manifests/calico.yaml`（约 4900 行）

打包分发：

```bash
cd ubuntu/offline/..
tar czf k8s-offline-noble.tar.gz offline/
scp k8s-offline-noble.tar.gz root@10.0.0.100:/opt/k8s-deploy/
```

### 部署（离线节点）

```bash
ssh root@10.0.0.100
cd /opt/k8s-deploy && tar xzf k8s-offline-noble.tar.gz
cd offline/scripts && chmod +x *.sh
./deploy-all.sh --dry-run
./deploy-all.sh
```

关键差异（vs online）：
- Phase 2.5 会执行 `import-resources.sh`（配 deb 本地源 + 导入镜像 tar）
- `04-init-master1.sh` 检测本地已有镜像则跳过 `kubeadm config images pull`

---

## 四、swr 版部署

前置：`cluster.env` 填 `SWR_AK` / `SWR_LOGIN_KEY`；SWR 组织里已有 CentOS 版推送的镜像（**无需重推**）。

```bash
scp -r ubuntu/swr/ root@10.0.0.100:/opt/k8s-deploy/
ssh root@10.0.0.100
cd /opt/k8s-deploy/ubuntu/swr/scripts && chmod +x *.sh
./deploy-all.sh --dry-run
./deploy-all.sh
```

预期：`02-install-containerd.sh` 配置 SWR endpoint/TLS 和 sandbox。Ubuntu containerd 2.2 不得仅依赖旧式 `registry.configs` auth；必须用 `crictl pull` 验证，必要时显式凭据预拉 static Pod 镜像，普通 Pod 使用 `imagePullSecret`。详见 `../docs/容器运行时与Kubernetes镜像仓库配置指南.md`。

---

## 五、常见坑（对应已固化的修复）

| 现象 | 根因 | 排查/解决 |
|------|------|----------|
| `apt-get update` 卡住/超时 | 离线时在线源没禁用 | 确认 `import-resources.sh` 已跑，`/etc/apt/sources.list.d/` 只剩 k8s-local.list |
| `kubeadm init` 卡在拉镜像 | 离线镜像未导入 | `ctr -n k8s.io images ls` 应有 k8s 镜像 |
| calico 节点 NotReady | VXLAN/BGP 冲突或网卡选错 | 07 脚本已设 backend=vxlan + interface 精确网卡 |
| kube-vip 多节点抢 VIP | arp_ignore=0 | 01 脚本已设 arp_ignore=1/arp_announce=2 |
| `kubelet=1.28.15-*` 装不上 | deb 源版本号不匹配 | 确认阿里云 kubernetes-new deb 源可达，`apt-cache madison kubeadm` |
| SWR static pod ImagePullBackOff | private 未配认证 | 确认 SWR_AK/LOGIN_KEY 已填、02 已跑 |
