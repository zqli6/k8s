好的，我为你准备了一份精简版的 README，内容清晰、直白，非常适合放在 Gitee 仓库中。

---

# Local Path Provisioner 本地存储配置

## 项目简介
本项目提供 Rancher Local Path Provisioner 的 Kubernetes 部署清单，用于利用节点本地磁盘目录动态提供持久化存储卷（PV），无需额外分布式存储系统。

## 核心功能
- **动态供应**：根据 PVC 请求自动创建本地存储 PV
- **延迟绑定**：Pod 调度到哪台节点，存储就创建在哪台节点（`WaitForFirstConsumer`）
- **轻量高效**：直接使用节点本地磁盘，适合开发测试环境

## 快速部署
```bash
kubectl apply -f apiVersion\ v1.txt
```

验证部署：
```bash
kubectl get pods -n local-path-storage
kubectl get storageclass local-path
```

## 默认存储路径
`/opt/local-path-provisioner`

如需修改，编辑 ConfigMap `local-path-config` 中的 `config.json`：
```json
"paths": ["/你的自定义路径"]
```

## 使用示例
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Mi
  storageClassName: local-path
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: test-pvc
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: storage
          mountPath: /data
```

## 注意事项
- 数据仅保存在 Pod 所在节点，迁移或节点故障会导致数据不可用
- StorageClass 回收策略为 `Delete`，删除 PVC 时会同时删除数据
- 可根据网络环境自行替换镜像地址（当前已使用华为云镜像）

## 卸载清理
```bash
kubectl delete -f apiVersion\ v1.txt
```
⚠️ 此操作会删除所有 PV 及本地数据，请提前备份

## 参考链接
- 官方 GitHub：[rancher/local-path-provisioner](https://github.com/rancher/local-path-provisioner)