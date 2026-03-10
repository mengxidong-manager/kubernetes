# Kubernetes 工作负载配置详解

## 1. Pod 详细配置

### 1.1 完整 Pod 规范

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: complete-pod
  namespace: default
  labels:
    app: myapp
    version: v1
  annotations:
    description: "示例 Pod"
spec:
  # 调度相关
  nodeSelector:
    disktype: ssd
  tolerations:
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
  
  # 容器配置
  containers:
  - name: main
    image: nginx:1.25
    imagePullPolicy: IfNotPresent
    
    # 端口
    ports:
    - containerPort: 80
      name: http
      protocol: TCP
    
    # 资源限制
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    
    # 环境变量
    env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
    - name: CONFIG_VALUE
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: config_key
    
    # 挂载卷
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
    - name: secret-volume
      mountPath: /etc/secrets
      readOnly: true
    - name: data-volume
      mountPath: /data
    
    # 健康检查
    livenessProbe:
      httpGet:
        path: /healthz
        port: 80
      initialDelaySeconds: 15
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    readinessProbe:
      httpGet:
        path: /ready
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
    
    startupProbe:
      httpGet:
        path: /startup
        port: 80
      failureThreshold: 30
      periodSeconds: 10
    
    # 生命周期钩子
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo Hello > /tmp/started"]
      preStop:
        exec:
          command: ["/bin/sh", "-c", "nginx -s quit; sleep 10"]
    
    # 安全上下文
    securityContext:
      runAsUser: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
  
  # Init 容器
  initContainers:
  - name: init-db
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z db-service 3306; do echo waiting for db; sleep 2; done']
  
  # 卷定义
  volumes:
  - name: config-volume
    configMap:
      name: app-config
  - name: secret-volume
    secret:
      secretName: app-secret
  - name: data-volume
    emptyDir: {}
  
  # Pod 级别配置
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  serviceAccountName: app-service-account
  
  # DNS 配置
  dnsPolicy: ClusterFirst
  dnsConfig:
    nameservers:
    - 8.8.8.8
    searches:
    - default.svc.cluster.local
```

---

## 2. Deployment 配置

### 2.1 生产级 Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
  labels:
    app: web
spec:
  replicas: 3
  
  # 滚动更新策略
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 最多超出期望副本数
      maxUnavailable: 0  # 最多不可用数（确保零停机）
  
  selector:
    matchLabels:
      app: web
  
  # 最小就绪时间
  minReadySeconds: 10
  
  # 保留历史版本数
  revisionHistoryLimit: 10
  
  template:
    metadata:
      labels:
        app: web
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      containers:
      - name: web
        image: myapp:v1.2.3
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      
      # Pod 反亲和性（分散到不同节点）
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - web
              topologyKey: kubernetes.io/hostname
      
      # 拓扑分布约束
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: web
```

### 2.2 Deployment 操作命令

```bash
# 创建/更新
kubectl apply -f deployment.yaml

# 查看状态
kubectl rollout status deployment/web-app

# 查看历史
kubectl rollout history deployment/web-app

# 回滚到上一版本
kubectl rollout undo deployment/web-app

# 回滚到指定版本
kubectl rollout undo deployment/web-app --to-revision=2

# 暂停/恢复滚动更新
kubectl rollout pause deployment/web-app
kubectl rollout resume deployment/web-app

# 扩缩容
kubectl scale deployment/web-app --replicas=5

# 更新镜像
kubectl set image deployment/web-app web=myapp:v1.3.0
```

---

## 3. StatefulSet 配置

### 3.1 完整 StatefulSet 示例

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless  # 必须指定 headless service
  replicas: 3
  
  selector:
    matchLabels:
      app: mysql
  
  # 更新策略
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # 只更新序号 >= partition 的 Pod
  
  # Pod 管理策略
  podManagementPolicy: OrderedReady  # 或 Parallel
  
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
  
  # 卷声明模板（每个 Pod 独立 PVC）
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi

---
# Headless Service（必需）
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None  # Headless
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
```

### 3.2 StatefulSet 特性说明

```
Pod 命名规则: <statefulset-name>-<ordinal>
示例: mysql-0, mysql-1, mysql-2

DNS 记录:
- Pod: mysql-0.mysql-headless.default.svc.cluster.local
- Service: mysql-headless.default.svc.cluster.local

启动顺序: mysql-0 → mysql-1 → mysql-2
删除顺序: mysql-2 → mysql-1 → mysql-0
```

---

## 4. DaemonSet 配置

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: fluentd
  
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      # 容忍所有污点（包括 master）
      tolerations:
      - operator: Exists
      
      containers:
      - name: fluentd
        image: fluentd:v1.16
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: containers
          mountPath: /var/lib/docker/containers
          readOnly: true
      
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
```

---

## 5. Job 和 CronJob

### 5.1 Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-migration
spec:
  completions: 5      # 需要成功完成的 Pod 数
  parallelism: 2      # 并行运行的 Pod 数
  backoffLimit: 4     # 失败重试次数
  activeDeadlineSeconds: 600  # 超时时间
  ttlSecondsAfterFinished: 3600  # 完成后自动清理
  
  template:
    spec:
      restartPolicy: OnFailure  # Job 必须是 OnFailure 或 Never
      containers:
      - name: migration
        image: migrate-tool:v1
        command: ["./migrate.sh"]
```

### 5.2 CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点
  timeZone: "Asia/Tokyo"
  
  concurrencyPolicy: Forbid  # Allow, Forbid, Replace
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 600
  
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: backup-tool:v1
            command: ["./backup.sh"]
            env:
            - name: BACKUP_TARGET
              value: "s3://my-bucket/backups"
```

### 5.3 Cron 表达式说明

```
┌───────────── 分钟 (0 - 59)
│ ┌───────────── 小时 (0 - 23)
│ │ ┌───────────── 日 (1 - 31)
│ │ │ ┌───────────── 月 (1 - 12)
│ │ │ │ ┌───────────── 星期 (0 - 6，0=周日)
│ │ │ │ │
* * * * *

示例:
"0 * * * *"      # 每小时
"0 0 * * *"      # 每天午夜
"0 0 * * 0"      # 每周日午夜
"0 0 1 * *"      # 每月1日
"*/15 * * * *"   # 每15分钟
"0 9-17 * * 1-5" # 工作日 9-17 点每小时
```
