# Kubernetes 安全配置详解

## 1. RBAC（基于角色的访问控制）

### 1.1 核心概念

```
ServiceAccount - 为 Pod 提供身份
Role - 命名空间级别权限
ClusterRole - 集群级别权限
RoleBinding - 将 Role 绑定到用户/组/ServiceAccount
ClusterRoleBinding - 将 ClusterRole 绑定到用户/组/ServiceAccount
```

### 1.2 ServiceAccount

```yaml
# 创建 ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production

---
# Pod 使用 ServiceAccount
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  serviceAccountName: app-service-account
  automountServiceAccountToken: true  # 默认为 true
  containers:
  - name: app
    image: myapp
```

### 1.3 Role 和 RoleBinding

```yaml
# Role - 命名空间级别
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]  # 核心 API 组
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]

---
# RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: production
# 或绑定到用户
# - kind: User
#   name: developer@example.com
#   apiGroup: rbac.authorization.k8s.io
# 或绑定到组
# - kind: Group
#   name: developers
#   apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 1.4 ClusterRole 和 ClusterRoleBinding

```yaml
# ClusterRole - 集群级别
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
# 非资源 URL
- nonResourceURLs: ["/healthz", "/metrics"]
  verbs: ["get"]

---
# ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-secrets-global
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

### 1.5 常用权限动词

```yaml
# verbs 可选值
verbs: ["get", "list", "watch", "create", "update", "patch", "delete", "deletecollection"]

# 通配符
verbs: ["*"]
resources: ["*"]
apiGroups: ["*"]
```

### 1.6 RBAC 检查命令

```bash
# 检查当前用户权限
kubectl auth can-i create pods
kubectl auth can-i get secrets --namespace production

# 检查特定用户/SA权限
kubectl auth can-i list pods --as system:serviceaccount:production:app-service-account

# 列出所有角色
kubectl get roles -A
kubectl get clusterroles

# 列出绑定
kubectl get rolebindings -A
kubectl get clusterrolebindings
```

---

## 2. Pod 安全

### 2.1 SecurityContext

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  # Pod 级别安全上下文
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    fsGroupChangePolicy: OnRootMismatch
    
  containers:
  - name: app
    image: myapp
    # 容器级别安全上下文
    securityContext:
      runAsUser: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      privileged: false
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE
      seccompProfile:
        type: RuntimeDefault
```

### 2.2 Pod Security Standards (PSS)

```yaml
# 命名空间级别强制执行
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # 强制执行级别
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.28
    # 警告级别
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.28
    # 审计级别
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.28
```

安全级别说明：
```
privileged - 不受限制（不安全）
baseline   - 基础限制，防止已知提权
restricted - 高度受限，最佳实践
```

### 2.3 符合 restricted 标准的 Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
```

---

## 3. Secret 管理

### 3.1 创建 Secret

```bash
# 从字面值创建
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# 从文件创建
kubectl create secret generic tls-secret \
  --from-file=tls.crt=path/to/cert \
  --from-file=tls.key=path/to/key

# 从 .env 文件创建
kubectl create secret generic env-secret --from-env-file=.env

# Docker registry secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com
```

### 3.2 Secret YAML

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
# stringData 不需要 base64 编码
stringData:
  username: admin
  password: secret123
# data 需要 base64 编码
data:
  api-key: c2VjcmV0LWtleS0xMjM=  # echo -n "secret-key-123" | base64
```

### 3.3 使用 Secret

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-pod
spec:
  containers:
  - name: app
    image: myapp
    env:
    # 单个 key
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
    # 所有 key
    envFrom:
    - secretRef:
        name: app-secret
    
    volumeMounts:
    - name: secret-vol
      mountPath: /etc/secrets
      readOnly: true
  
  volumes:
  - name: secret-vol
    secret:
      secretName: app-secret
      defaultMode: 0400
  
  # 拉取私有镜像
  imagePullSecrets:
  - name: regcred
```

---

## 4. 网络策略（已在 networking.md 详述）

---

## 5. 审计日志

### 5.1 审计策略

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# 不记录只读请求到某些资源
- level: None
  resources:
  - group: ""
    resources: ["events"]

# 记录 Secret 访问
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]

# 记录所有其他请求
- level: RequestResponse
  omitStages:
  - RequestReceived
```

### 5.2 审计级别

```
None           - 不记录
Metadata       - 记录请求元数据
Request        - 记录请求元数据和请求体
RequestResponse - 记录请求元数据、请求体和响应体
```

---

## 6. 安全最佳实践清单

```yaml
# ✅ 使用非 root 用户
securityContext:
  runAsNonRoot: true
  runAsUser: 1000

# ✅ 只读文件系统
securityContext:
  readOnlyRootFilesystem: true

# ✅ 禁止特权提升
securityContext:
  allowPrivilegeEscalation: false

# ✅ 删除所有 capabilities
securityContext:
  capabilities:
    drop:
    - ALL

# ✅ 使用 seccomp
securityContext:
  seccompProfile:
    type: RuntimeDefault

# ✅ 设置资源限制
resources:
  limits:
    cpu: "1"
    memory: "1Gi"
  requests:
    cpu: "100m"
    memory: "128Mi"

# ✅ 使用 NetworkPolicy
# ✅ 最小权限 RBAC
# ✅ 定期轮换 Secret
# ✅ 使用私有镜像仓库
# ✅ 扫描镜像漏洞
```

---

## 7. 有用命令

```bash
# 查看 ServiceAccount
kubectl get sa -A
kubectl describe sa <name>

# 查看 SA 的 token
kubectl create token <sa-name>

# 测试 RBAC
kubectl auth can-i --list --as system:serviceaccount:default:myapp

# 查看 PodSecurityPolicy（已废弃）
kubectl get psp

# 检查 Pod 安全违规
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].securityContext.privileged==true) | .metadata.name'
```
