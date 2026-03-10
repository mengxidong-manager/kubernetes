# Kubernetes 监控与日志配置

## 1. Metrics Server

### 1.1 安装

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 如果是自签名证书环境，添加参数
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'
```

### 1.2 使用

```bash
# 查看节点资源使用
kubectl top nodes

# 查看 Pod 资源使用
kubectl top pods -A
kubectl top pods -n production --sort-by=memory
```

---

## 2. Prometheus + Grafana

### 2.1 使用 kube-prometheus-stack (推荐)

```bash
# 添加 Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123

# 访问 Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

# 访问 Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```

### 2.2 自定义 values.yaml

```yaml
# values.yaml
grafana:
  adminPassword: your-password
  ingress:
    enabled: true
    hosts:
    - grafana.example.com
  
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
```

### 2.3 应用监控配置

```yaml
# ServiceMonitor - 监控应用
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: myapp
  namespaceSelector:
    matchNames:
    - production
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

```yaml
# PodMonitor - 直接监控 Pod
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: app-pods
spec:
  selector:
    matchLabels:
      app: myapp
  podMetricsEndpoints:
  - port: metrics
    interval: 30s
```

---

## 3. 日志收集

### 3.1 EFK Stack (Elasticsearch + Fluentd + Kibana)

```yaml
# Fluentd DaemonSet
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: logging
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: "elasticsearch.logging.svc"
        - name: FLUENT_ELASTICSEARCH_PORT
          value: "9200"
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

### 3.2 Loki + Promtail (轻量级)

```bash
# 安装 Loki Stack
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace logging \
  --create-namespace \
  --set promtail.enabled=true \
  --set grafana.enabled=true
```

### 3.3 日志查看命令

```bash
# 查看 Pod 日志
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>  # 指定容器
kubectl logs <pod-name> --previous           # 上一个容器
kubectl logs <pod-name> -f                   # 实时跟踪
kubectl logs <pod-name> --tail=100           # 最后100行
kubectl logs <pod-name> --since=1h           # 最近1小时

# 查看多个 Pod 日志
kubectl logs -l app=myapp --all-containers

# 使用 stern (推荐)
stern <pod-name-pattern>
stern -n production app-
stern --tail 50 -s 1h myapp
```

---

## 4. 告警配置

### 4.1 AlertManager 配置

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp.example.com:587'
      smtp_from: 'alertmanager@example.com'
      smtp_auth_username: 'alertmanager@example.com'
      smtp_auth_password: 'password'
    
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'critical'
    
    receivers:
    - name: 'default'
      email_configs:
      - to: 'team@example.com'
    
    - name: 'critical'
      email_configs:
      - to: 'oncall@example.com'
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/xxx'
        channel: '#alerts'
```

### 4.2 PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
spec:
  groups:
  - name: app.rules
    rules:
    # Pod 重启告警
    - alert: PodRestartingTooMuch
      expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} 频繁重启"
        description: "命名空间 {{ $labels.namespace }} 中的 Pod {{ $labels.pod }} 在过去15分钟内重启"
    
    # 高内存使用
    - alert: HighMemoryUsage
      expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "容器内存使用超过90%"
    
    # Pod 未就绪
    - alert: PodNotReady
      expr: kube_pod_status_ready{condition="false"} == 1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.pod }} 未就绪"
```

---

## 5. 常用 PromQL 查询

```promql
# CPU 使用率
sum(rate(container_cpu_usage_seconds_total{namespace="production"}[5m])) by (pod)

# 内存使用
container_memory_usage_bytes{namespace="production"} / 1024 / 1024

# 网络流量
sum(rate(container_network_receive_bytes_total[5m])) by (pod)

# Pod 重启次数
kube_pod_container_status_restarts_total

# 请求延迟 (需要应用暴露)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# 错误率
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

---

## 6. 健康检查仪表盘

### 6.1 重要指标

```
集群级别：
- 节点状态和资源使用
- etcd 健康状态
- API Server 延迟
- 控制器队列深度

应用级别：
- Pod 就绪状态
- 容器重启次数
- 资源使用 vs 限制
- 请求成功率/延迟
```

### 6.2 kubectl 快速检查

```bash
# 集群健康
kubectl get componentstatuses
kubectl get nodes
kubectl cluster-info

# 查看事件
kubectl get events --sort-by=.lastTimestamp
kubectl get events -A --field-selector type=Warning

# 资源使用
kubectl top nodes
kubectl top pods -A --sort-by=cpu

# Pod 状态
kubectl get pods -A | grep -v Running
kubectl get pods -A -o wide | grep -E "0/|CrashLoop|Error|Pending"
```
