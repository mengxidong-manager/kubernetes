# Kubernetes 存储配置详解

## 1. Volume 类型

### 1.1 emptyDir（临时存储）

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-data
spec:
  containers:
  - name: writer
    image: busybox
    command: ['sh', '-c', 'echo "Hello" > /data/hello.txt; sleep 3600']
    volumeMounts:
    - name: shared
      mountPath: /data
  - name: reader
    image: busybox
    command: ['sh', '-c', 'cat /data/hello.txt; sleep 3600']
    volumeMounts:
    - name: shared
      mountPath: /data
  volumes:
  - name: shared
    emptyDir: {}
    # 或使用内存
    # emptyDir:
    #   medium: Memory
    #   sizeLimit: 100Mi
```

### 1.2 hostPath（节点路径）

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
  volumes:
  - name: logs
    hostPath:
      path: /var/log/pods
      type: DirectoryOrCreate  # Directory, File, FileOrCreate, Socket, CharDevice, BlockDevice
```

### 1.3 ConfigMap 和 Secret 挂载

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    # 挂载整个 ConfigMap
    - name: config
      mountPath: /etc/config
    # 挂载特定 key
    - name: config-single
      mountPath: /etc/app/config.json
      subPath: config.json
    # 挂载 Secret
    - name: secret
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: config
    configMap:
      name: app-config
      # 可选：设置权限
      defaultMode: 0644
  - name: config-single
    configMap:
      name: app-config
      items:
      - key: config.json
        path: config.json
  - name: secret
    secret:
      secretName: app-secret
      defaultMode: 0400
```

---

## 2. PersistentVolume (PV) 和 PersistentVolumeClaim (PVC)

### 2.1 静态 PV

```yaml
# 创建 PV（管理员操作）
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs
  labels:
    type: nfs
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain  # Retain, Delete, Recycle
  storageClassName: nfs
  nfs:
    server: nfs-server.example.com
    path: /exports/data

---
# 创建 PVC（用户操作）
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-claim
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
  storageClassName: nfs
  selector:
    matchLabels:
      type: nfs
```

### 2.2 动态 PV（StorageClass）

```yaml
# StorageClass（管理员创建）
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs  # 或其他 provisioner
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  fsType: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer  # 延迟绑定

---
# 用户创建 PVC，自动创建 PV
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: fast-ssd  # 指定 StorageClass
```

### 2.3 常见 StorageClass Provisioner

```yaml
# 阿里云云盘
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: alicloud-disk-ssd
provisioner: diskplugin.csi.alibabacloud.com
parameters:
  type: cloud_ssd
reclaimPolicy: Delete

---
# AWS EBS
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  csi.storage.k8s.io/fstype: ext4

---
# 本地存储（local-path-provisioner）
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
```

### 2.4 访问模式说明

```
ReadWriteOnce (RWO) - 单节点读写
ReadOnlyMany (ROX)  - 多节点只读
ReadWriteMany (RWX) - 多节点读写
ReadWriteOncePod (RWOP) - 单 Pod 读写（K8s 1.22+）
```

---

## 3. 使用 PVC

### 3.1 Pod 中使用

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-pvc
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: dynamic-pvc
```

### 3.2 StatefulSet 中使用

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:  # 每个 Pod 独立 PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi
```

---

## 4. 卷扩容

```yaml
# 前提：StorageClass 需要 allowVolumeExpansion: true

# 编辑 PVC 增加容量
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi  # 从 20Gi 扩容到 50Gi
  storageClassName: fast-ssd
```

```bash
# 命令行扩容
kubectl patch pvc dynamic-pvc -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# 查看扩容状态
kubectl get pvc dynamic-pvc
kubectl describe pvc dynamic-pvc
```

---

## 5. 卷快照

```yaml
# VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-snapclass
driver: ebs.csi.aws.com
deletionPolicy: Delete

---
# 创建快照
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: pvc-snapshot
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: dynamic-pvc

---
# 从快照恢复
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 50Gi
  dataSource:
    name: pvc-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

---

## 6. 常用命令

```bash
# 查看 PV
kubectl get pv
kubectl describe pv <pv-name>

# 查看 PVC
kubectl get pvc
kubectl describe pvc <pvc-name>

# 查看 StorageClass
kubectl get sc
kubectl describe sc <sc-name>

# 设置默认 StorageClass
kubectl patch storageclass <sc-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 删除 PVC（注意：可能删除数据）
kubectl delete pvc <pvc-name>
```
