# NFS Subdir External Provisioner 部署与使用指南

## 相关网址

- **GitHub 官方仓库**  
  [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)

---

## 整体流程概览

| 步骤 | 内容 |
|------|------|
| 01~04 | 部署 NFS Subdir External Provisioner 并创建 StorageClass |
| 05~06 | 创建 PVC 和 Pod（测试示例） |
| 实践 | 基于 `sc-nfs` 实现 MySQL 的动态置备 |

---

## 一、创建 NFS 共享（服务端与客户端准备）

### 1.1 NFS 服务端配置（以 master1 为例）

#### 安装 NFS 服务

**Debian / Ubuntu 系列**
```bash
    apt update && apt -y install nfs-kernel-server
    systemctl status nfs-server.service
```
**CentOS / RHEL 系列**
```bash
    yum makecache && yum install nfs-utils -y
    systemctl start rpcbind; systemctl enable rpcbind
    systemctl start nfs-server; systemctl enable nfs-server
```
#### 创建共享目录并配置 exports
```bash
    mkdir -pv /data/sc-nfs/
```
编辑 `/etc/exports`，添加以下内容（授权所有客户端挂载）：
```bash
    /data/sc-nfs *(rw,no_root_squash)
```
或使用追加命令：
```bash
    echo '/data/sc-nfs *(rw,no_root_squash)' >> /etc/exports
```
#### 使配置生效
```bash
    exportfs -rv
```
#### （可选）NFS 域名解析（每个节点执行）
```bash
    echo "10.0.0.100 nfs.lzq.org" >> /etc/hosts
```
---

### 1.2 NFS 客户端配置（所有工作节点）

**Debian / Ubuntu**
```bash
    apt update && apt -y install nfs-common   # 或 nfs-client
```
**CentOS / RHEL**
```bash
    yum makecache && yum install nfs-utils -y
    systemctl start rpcbind; systemctl enable rpcbind
    systemctl start nfs-server; systemctl enable nfs-server
```
> **注意**：客户端只需安装工具包，无需手动挂载 NFS 目录。

---

### 1.3 共享目录名称约定

- 共享目录名为：`/data/sc-nfs`
- 若实际目录不一致，需在后续 Deployment YAML 中修改两处：
  - `spec.template.spec.containers.env` 中的 NFS 共享目录路径
  - `spec.template.spec.volumes.path` 中的 NFS 共享目录路径

---

## 二、部署 NFS Subdir External Provisioner

### 2.1 创建 Service Account 并授权（RBAC）

执行以下命令创建命名空间和 RBAC 资源：
```bash
    kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/01-namespace.yaml
    kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/02-rbac.yaml
```
---

### 2.2 部署 Provisioner Deployment

#### 选项一：使用官方镜像（原版）
可参考官方仓库中的 `nfs-client-provisioner.yaml`

#### 选项二：使用 SWR 仓库镜像（lzq 定制版）
执行以下命令部署：
```bash
    kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/03-nfs-client-provisioner_lzq.yaml
```
> **前置要求**：使用 SWR 私有仓库镜像需提前创建镜像仓库 Secret，并为 ServiceAccount 绑定。详见 [SWR 私有仓库认证指南](https://gitee.com/zqli6/HA-cluster/blob/master/SWR-AUTH.md#%E5%9B%9B%E5%AE%9E%E4%BE%8B-1swr-%E7%A7%81%E6%9C%89%E4%BB%93%E5%BA%93%E8%AE%A4%E8%AF%81)

> **重要**：部署前请确保 NFS_SERVER 的域名解析已配置（可在节点 hosts 或 DNS 中设置）。

---

### 2.3 创建 StorageClass

执行以下命令创建 StorageClass，该 SC 会调用 NFS Provisioner 动态创建 PV：
```bash
    kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/nfs-subdir-external-provisioner/04-nfs-StorageClass.yaml
```
---

## 三、测试 PVC 与 Pod 使用

### 3.1 创建 PVC（自动调用 StorageClass 生成 PV）
```bash
    kubectl apply -f pvc.yaml   # 请准备对应的 pvc.yaml 文件
```
### 3.2 创建测试 Pod 挂载 PVC
```bash
    kubectl apply -f pod-test.yaml   # 请准备对应的 pod-test.yaml 文件
```
---

## 四、实践案例：基于 sc-nfs 实现 MySQL 动态置备

### 步骤说明

- 准备 MySQL 所需的 PVC、Service、Pod 组合资源文件。
- 示例文件名称：`storage-mysql-storage-class-pvc.yaml`

### 部署命令
```bash
    kubectl apply -f storage-mysql-storage-class-pvc.yaml
```
该资源将利用已创建的 StorageClass（`sc-nfs`）为 MySQL 动态分配持久化存储。

---

> **提示**：所有 YAML 文件均可从上述 Gitee 链接获取，请根据实际环境调整 NFS 服务器地址、共享路径及镜像仓库认证信息。