# 各类 StorageClass PVC 扩容指南
- 重新声明更大容量pvc能否实现扩容？ 
- 重新声明的pvc需要从之前的pv迁移数据  
- 如果是自动删除pvc及pv甚至会导致数据丢失  

数据迁移问题：  
>新PVC是空的，旧数据不会自动跟过去
必须手动把数据从旧PV复制到新PV
复制期间pod必须停止，否则数据不一致  

## 前提条件（所有类型通用）

```bash
# 确认 storageClass 支持扩容
kubectl get sc <storageclass-name> -o jsonpath='{.allowVolumeExpansion}'
# 输出 true 才能扩容

# 扩容命令通用
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## 一、NFS（nfs-subdir-external-provisioner）

**假扩容，底层不限制大小，改数字即可。**

```bash
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## 二、TopoLVM

**真实 LVM 扩容，底层 LV 会真正扩大。**

```bash
# 确认 VG 有足够空间
vgs

# 扩容
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 确认 LV 扩大
lvs
```

---

## 三、Longhorn

**分布式块存储，支持在线扩容，底层 volume 真实扩大。**

```bash
# 扩容
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":"storage":"20Gi"}}}}'

# 观察状态（Longhorn 扩容比较慢，需要等待）
kubectl get pvc <pvc-name> -n <namespace> -w

# 也可以在 Longhorn UI 直接操作
# 进入 Volume 页面 → 找到对应 volume → Expand Volume
```

### Longhorn 扩容失败排查

```bash
# 看 Longhorn volume 状态
kubectl get volume -n longhorn-system | grep <pvc-volume-name>

# 看 Longhorn manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 确认副本节点磁盘空间足够
kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable}{"\n"}{end}'
```

---

## 四、OpenEBS

OpenEBS 有多个引擎，扩容方式不同：

### LocalPV-Hostpath / LocalPV-LVM

```bash
# LocalPV-Hostpath 假扩容（同 NFS）
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# LocalPV-LVM 真实扩容（同 TopoLVM）
vgs  # 确认 VG 空间
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
lvs  # 确认 LV 扩大
```

### cStor / Jiva（分布式引擎）

```bash
# 扩容前确认 cStor pool 有足够空间
kubectl get cstorpoolinstance -n openebs

# 扩容
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 观察
kubectl get pvc <pvc-name> -n <namespace> -w
kubectl describe pvc <pvc-name> -n <namespace>
```

### Mayastor（高性能引擎）

```bash
# 确认 diskpool 空间
kubectl get diskpool -n mayastor

# 扩容
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## 五、Rook-Ceph

**分布式对象/块存储，支持在线扩容。**

```bash
# 确认 Ceph 集群空间
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph df

# 扩容
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 观察
kubectl get pvc <pvc-name> -n <namespace> -w
```

---

## 六、local-path（k3s 默认）

**假扩容，hostpath 不限制大小。**

```bash
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
# 注意：local-path 默认 allowVolumeExpansion=false，需要先修改 SC
kubectl patch sc local-path -p '{"allowVolumeExpansion":true}'
```

---

## 七、对比总结

| StorageClass | 扩容类型 | 在线扩容 | 需要重启 Pod | 注意事项 |
|-------------|---------|---------|------------|---------|
| NFS | 假扩容 | ✅ | 不需要 | 底层不限制 |
| local-path | 假扩容 | ✅ | 不需要 | 需手动开启 allowVolumeExpansion |
| TopoLVM | 真实 LVM | ✅ | 不需要 | 需 VG 有剩余空间 |
| OpenEBS LocalPV-LVM | 真实 LVM | ✅ | 不需要 | 需 VG 有剩余空间 |
| Longhorn | 真实分布式 | ✅ | 不需要 | 速度较慢，需等待 |
| OpenEBS cStor/Jiva | 真实分布式 | ✅ | 不需要 | 需 pool 有空间 |
| Rook-Ceph | 真实分布式 | ✅ | 不需要 | 需 Ceph 集群有空间 |
| OpenEBS Mayastor | 真实分布式 | ✅ | 不需要 | 需 diskpool 有空间 |

> **缩容**：所有类型均不支持 PVC 缩容，只能扩不能缩。