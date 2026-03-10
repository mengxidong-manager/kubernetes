# Kubernetes 网络配置详解

## 1. Service 类型详解

### 1.1 ClusterIP（默认）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP  # 默认类型，可省略
  selector:
    app: backend
  ports:
  - name: http
    port: 80         # Service 端口
    targetPort: 8080 # Pod 端口
    protocol: TCP
  
  # 可选：指定 ClusterIP
  # clusterIP: 10.96.100.100
  
  # 或创建 Headless Service
  # clusterIP: None
```

### 1.2 NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080  # 范围: 30000-32767，不指定则自动分配
```

### 1.3 LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
  annotations:
    # AWS ELB
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
    # 阿里云 SLB
    service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: "intranet"
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
  # 可选：指定负载均衡器 IP
  # loadBalancerIP: 1.2.3.4
  # 限制访问源 IP
  # loadBalancerSourceRanges:
  # - 10.0.0.0/8
```

### 1.4 ExternalName

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  type: ExternalName
  externalName: db.example.com  # CNAME 解析
```

---

## 2. Ingress 配置

### 2.1 安装 Ingress Controller

```bash
# Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml

# 验证安装
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### 2.2 基础 Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### 2.3 多路径/多域名

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-path-ingress
spec:
  ingressClassName: nginx
  rules:
  # 第一个域名
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
  
  # 第二个域名
  - host: admin.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 80
```

### 2.4 HTTPS/TLS 配置

```yaml
# 创建 TLS Secret
kubectl create secret tls tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### 2.5 常用 Nginx Ingress 注解

```yaml
metadata:
  annotations:
    # 重写路径
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    
    # SSL 重定向
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # 限流
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-connections: "5"
    
    # 超时设置
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    
    # 请求体大小
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    
    # 后端协议
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    
    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
    
    # 认证
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
    
    # WebSocket
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

---

## 3. NetworkPolicy（网络策略）

### 3.1 默认拒绝所有入站

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}  # 选择所有 Pod
  policyTypes:
  - Ingress
```

### 3.2 允许特定来源

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    # 来自带有特定标签的 Pod
    - podSelector:
        matchLabels:
          app: frontend
    # 来自特定命名空间
    - namespaceSelector:
        matchLabels:
          name: monitoring
    # 来自特定 IP 段
    - ipBlock:
        cidr: 10.0.0.0/8
        except:
        - 10.0.1.0/24
    ports:
    - protocol: TCP
      port: 8080
```

### 3.3 限制出站流量

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress
spec:
  podSelector:
    matchLabels:
      app: restricted
  policyTypes:
  - Egress
  egress:
  # 允许 DNS
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
  # 允许访问特定服务
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 3306
```

---

## 4. DNS 配置

### 4.1 Pod DNS 策略

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-dns
spec:
  dnsPolicy: "None"  # Default, ClusterFirst, ClusterFirstWithHostNet, None
  dnsConfig:
    nameservers:
    - 8.8.8.8
    - 8.8.4.4
    searches:
    - default.svc.cluster.local
    - svc.cluster.local
    options:
    - name: ndots
      value: "5"
  containers:
  - name: app
    image: nginx
```

### 4.2 DNS 记录格式

```
# Service
<service-name>.<namespace>.svc.cluster.local

# Pod (需要 hostname 和 subdomain)
<hostname>.<subdomain>.<namespace>.svc.cluster.local

# Headless Service 的 Pod
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

---

## 5. 服务发现

### 5.1 环境变量方式

```bash
# 自动注入的环境变量
MY_SERVICE_SERVICE_HOST=10.96.100.1
MY_SERVICE_SERVICE_PORT=80
MY_SERVICE_PORT=tcp://10.96.100.1:80
```

### 5.2 DNS 方式（推荐）

```bash
# 同命名空间
curl http://my-service

# 跨命名空间
curl http://my-service.other-namespace

# 完整域名
curl http://my-service.other-namespace.svc.cluster.local
```
