# Prometheus + Grafana 生产监控部署指南

> 基于 kube-prometheus-stack，覆盖集群基础设施 → K8s 组件 → 外部 etcd → HAProxy → GPU → 业务应用全栈监控
>
> 撰写人：孟希東

---

## 监控架构

```
┌─ 数据采集层 ──────────────────────────────────────────────┐
│  node-exporter（每节点 DaemonSet）    → 主机 CPU/内存/磁盘/网络  │
│  kube-state-metrics                  → K8s 对象状态           │
│  kubelet / cAdvisor                  → 容器指标              │
│  API Server / Scheduler / Controller → 控制平面              │
│  External etcd（自定义 Endpoint）      → etcd 集群指标         │
│  HAProxy stats（自定义 scrape）        → LB 状态              │
│  DCGM Exporter（GPU Operator）        → GPU 指标             │
│  应用 /metrics（ServiceMonitor）       → 业务指标             │
└───────────┬───────────────────────────────────────────────┘
            ▼
┌─ Prometheus ──────────────────┐
│  采集 → 存储（50G PV, 30天保留）  │
│  PromQL 查询                   │
│  告警规则评估                    │
└───────────┬───────────────────┘
       ┌────┴────┐
       ▼         ▼
┌─ Grafana ─┐  ┌─ Alertmanager ─┐
│ 可视化面板  │  │  飞书/钉钉/邮件   │
│ 40+ Dashboard│  │  PagerDuty/Slack│
└────────────┘  └────────────────┘
```

### 组件清单

| 组件 | 说明 |
|------|------|
| **Prometheus Operator** | CRD 管理 Prometheus 实例、ServiceMonitor、PrometheusRule |
| **Prometheus** | 指标采集和存储（TSDB） |
| **Alertmanager** | 告警路由和通知 |
| **Grafana** | 可视化仪表盘（内置 40+ K8s Dashboard） |
| **node-exporter** | 主机级指标（DaemonSet 部署到每个节点） |
| **kube-state-metrics** | K8s 对象状态指标（Deployment/Pod/Node 等） |
| **DCGM Exporter** | GPU 指标（GPU Operator 部署，可选） |

---

## Phase 1 · 准备 values 文件

创建 `prometheus-values.yaml`，这是整个部署的核心配置：

```yaml
# prometheus-values.yaml
# 基于 kube-prometheus-stack Helm Chart

fullnameOverride: "prometheus"

# ============================================================
# Prometheus 配置
# ============================================================
prometheus:
  prometheusSpec:
    # 资源限制
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi

    # 持久化存储
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path    # 替换为你的 StorageClass
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

    # 数据保留
    retention: 30d
    retentionSize: 45GB

    # 采集间隔
    scrapeInterval: 30s
    evaluationInterval: 30s

    # 允许跨命名空间发现 ServiceMonitor 和 PodMonitor
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

    # 外部 etcd 监控（关键配置）
    additionalScrapeConfigs:
      # 外部 etcd 集群
      - job_name: 'external-etcd'
        scheme: https
        tls_config:
          ca_file: /etc/prometheus/secrets/etcd-certs/ca.pem
          cert_file: /etc/prometheus/secrets/etcd-certs/etcd.pem
          key_file: /etc/prometheus/secrets/etcd-certs/etcd-key.pem
          insecure_skip_verify: false
        static_configs:
          - targets:
            - '10.0.0.11:2379'
            - '10.0.0.12:2379'
            - '10.0.0.13:2379'

      # HAProxy stats
      - job_name: 'haproxy'
        static_configs:
          - targets:
            - '10.0.0.5:9090'
            - '10.0.0.6:9090'

      # 应用 Pod 自动发现（通过注解）
      - job_name: 'kubernetes-pods-auto'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

    # 挂载 etcd 证书 Secret
    secrets:
      - etcd-certs

# 禁用内置 etcd 监控（我们用外部 etcd）
kubeEtcd:
  enabled: false

# ============================================================
# Alertmanager 配置
# ============================================================
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  # 告警通知渠道
  config:
    global:
      resolve_timeout: 5m
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
          repeat_interval: 1h
    receivers:
      - name: 'default'
        webhook_configs:
          - url: 'http://your-webhook-url/alert'    # 替换为飞书/钉钉 Webhook
            send_resolved: true
      - name: 'critical'
        webhook_configs:
          - url: 'http://your-webhook-url/critical'
            send_resolved: true

# ============================================================
# Grafana 配置
# ============================================================
grafana:
  enabled: true

  adminUser: admin
  adminPassword: "YourStrongPassword@2026"    # 生产环境务必修改

  persistence:
    enabled: true
    storageClassName: local-path
    size: 10Gi

  # 通过 NodePort 暴露（或改为 LoadBalancer/Ingress）
  service:
    type: NodePort
    nodePort: 30080

  # 额外数据源（如 Loki）
  additionalDataSources: []

  # 自动导入社区 Dashboard
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'custom'
          folder: 'Custom'
          type: file
          options:
            path: /var/lib/grafana/dashboards/custom

  dashboards:
    custom:
      # etcd Dashboard
      etcd:
        gnetId: 3070
        datasource: Prometheus
      # Node Exporter Full
      node-exporter:
        gnetId: 1860
        datasource: Prometheus
      # NVIDIA GPU
      nvidia-gpu:
        gnetId: 12239
        datasource: Prometheus

# ============================================================
# node-exporter 配置
# ============================================================
prometheus-node-exporter:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

# ============================================================
# kube-state-metrics 配置
# ============================================================
kube-state-metrics:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

---

## Phase 2 · 创建 etcd 证书 Secret

Prometheus 需要 TLS 证书才能采集外部 etcd 指标：

```bash
# 在 Master 节点上执行，使用 Phase 2 生成的 etcd 证书
kubectl create namespace monitoring

kubectl create secret generic etcd-certs -n monitoring \
  --from-file=ca.pem=/etc/kubernetes/pki/etcd/ca.crt \
  --from-file=etcd.pem=/etc/kubernetes/pki/apiserver-etcd-client.crt \
  --from-file=etcd-key.pem=/etc/kubernetes/pki/apiserver-etcd-client.key

# 验证
kubectl get secret etcd-certs -n monitoring
```

---

## Phase 3 · 安装 kube-prometheus-stack

```bash
# 添加 Helm 仓库（如已添加可跳过）
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values prometheus-values.yaml \
  --wait --timeout 10m

# 查看安装结果
kubectl get pods -n monitoring
```

期望看到以下 Pod 全部 Running：

```
prometheus-operator-*                   1/1  Running
prometheus-prometheus-0                 2/2  Running
prometheus-alertmanager-0               2/2  Running
prometheus-grafana-*                    3/3  Running
prometheus-kube-state-metrics-*         1/1  Running
prometheus-prometheus-node-exporter-*   1/1  Running  (每节点一个)
```

---

## Phase 4 · 验证监控目标

### 4.1 访问 Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# 浏览器访问 http://localhost:9090/targets
```

确认以下 Target 全部 UP：

| Target | 说明 |
|--------|------|
| `serviceMonitor/monitoring/prometheus-apiserver` | API Server |
| `serviceMonitor/monitoring/prometheus-kubelet` | Kubelet / cAdvisor |
| `serviceMonitor/monitoring/prometheus-kube-controller-manager` | Controller Manager |
| `serviceMonitor/monitoring/prometheus-kube-scheduler` | Scheduler |
| `serviceMonitor/monitoring/prometheus-coredns` | CoreDNS |
| `serviceMonitor/monitoring/prometheus-node-exporter` | Node Exporter（每节点） |
| `serviceMonitor/monitoring/prometheus-kube-state-metrics` | Kube State Metrics |
| `scrapeConfig/external-etcd` | 外部 etcd 集群（3 个 endpoint） |
| `scrapeConfig/haproxy` | HAProxy（2 个 endpoint） |

### 4.2 访问 Grafana

```bash
# NodePort 方式（已在 values 中配置 30080）
# 浏览器访问 http://<任意节点IP>:30080
# 用户名: admin  密码: YourStrongPassword@2026
```

### 4.3 访问 Alertmanager

```bash
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093
# http://localhost:9093
```

---

## Phase 5 · 配置业务应用监控

### 5.1 ServiceMonitor（推荐方式）

为已暴露 `/metrics` 端口的应用创建 ServiceMonitor：

```yaml
# app-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: monitoring         # 或应用所在命名空间
  labels:
    release: prometheus         # 必须匹配 Helm release 名
spec:
  namespaceSelector:
    matchNames:
      - production              # 应用所在命名空间
  selector:
    matchLabels:
      app: my-app               # 匹配应用 Service 的 label
  endpoints:
    - port: metrics             # Service 中定义的端口名
      interval: 15s
      path: /metrics
```

```bash
kubectl apply -f app-servicemonitor.yaml
```

### 5.2 PodMonitor（无 Service 场景）

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-job-monitor
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
      - batch-jobs
  selector:
    matchLabels:
      app: training-job
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
```

### 5.3 注解方式（自动发现）

在 Pod spec 中添加注解，Prometheus 自动采集：

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

---

## Phase 6 · 配置告警规则

### 6.1 集群基础告警

```yaml
# cluster-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: node-alerts
      rules:
        - alert: NodeHighCpuUsage
          expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "节点 CPU 使用率过高 ({{ $labels.instance }})"
            description: "CPU 使用率 {{ printf \"%.1f\" $value }}%，持续 5 分钟"

        - alert: NodeHighMemoryUsage
          expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "节点内存使用率过高 ({{ $labels.instance }})"

        - alert: NodeDiskAlmostFull
          expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "节点磁盘即将满 ({{ $labels.instance }})"

    - name: pod-alerts
      rules:
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.2
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod 反复重启 {{ $labels.namespace }}/{{ $labels.pod }}"

        - alert: PodNotReady
          expr: kube_pod_status_ready{condition="true"} == 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Pod 长时间未就绪 {{ $labels.namespace }}/{{ $labels.pod }}"

    - name: etcd-alerts
      rules:
        - alert: EtcdMemberDown
          expr: up{job="external-etcd"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "etcd 节点不可达 ({{ $labels.instance }})"

        - alert: EtcdHighLatency
          expr: histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "etcd WAL fsync 延迟过高"

    - name: gpu-alerts
      rules:
        - alert: GpuHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GPU 温度过高 {{ $labels.gpu }}"

        - alert: GpuEccUncorrectable
          expr: DCGM_FI_DEV_ECC_DBE_VOL_TOTAL > 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "GPU ECC 不可纠正错误 {{ $labels.gpu }}"
```

```bash
kubectl apply -f cluster-alerts.yaml
```

---

## Phase 7 · Grafana Dashboard 配置

### 内置 Dashboard（kube-prometheus-stack 自带 40+）

安装后 Grafana 自动加载以下仪表盘：

| Dashboard | 内容 |
|-----------|------|
| Kubernetes / Compute Resources / Cluster | 集群总览（CPU/内存/网络） |
| Kubernetes / Compute Resources / Namespace | 按命名空间维度 |
| Kubernetes / Compute Resources / Node | 按节点维度 |
| Kubernetes / Compute Resources / Pod | 按 Pod 维度 |
| Kubernetes / Networking / Cluster | 集群网络流量 |
| Kubernetes / API Server | API Server 请求/延迟/错误 |
| Kubernetes / Scheduler | 调度器性能 |
| Kubernetes / Controller Manager | 控制器工作队列 |
| CoreDNS | DNS 查询/缓存/错误 |
| Node Exporter / Full | 主机详细指标 |
| Alertmanager Overview | 告警状态 |

### 手动导入推荐 Dashboard

在 Grafana UI → Dashboards → Import → 输入 ID：

| ID | Dashboard 名称 | 用途 |
|----|---------------|------|
| 1860 | Node Exporter Full | 主机指标详细版 |
| 3070 | etcd by Prometheus | etcd 集群监控 |
| 12239 | NVIDIA DCGM Exporter | GPU 监控 |
| 15760 | Kubernetes Views / Global | K8s 全局视图 |
| 15757 | Kubernetes Views / Pods | Pod 级详情 |
| 13770 | Kubernetes Cluster Monitoring | 集群概览 |

---

## Phase 8 · GPU 监控（可选，需 GPU Operator）

如果已安装 GPU Operator，DCGM Exporter 会自动暴露指标。只需创建 ServiceMonitor：

```yaml
# gpu-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - gpu-operator
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
    - port: metrics
      interval: 15s
```

```bash
kubectl apply -f gpu-servicemonitor.yaml
```

关键 GPU 指标：

| 指标 | 说明 |
|------|------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU 利用率 % |
| `DCGM_FI_DEV_FB_USED` / `FREE` | 显存使用/空闲 MB |
| `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 °C |
| `DCGM_FI_DEV_POWER_USAGE` | 实时功耗 W |
| `DCGM_FI_DEV_ECC_SBE/DBE_VOL_TOTAL` | ECC 单/双比特错误 |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NVLink 带宽 |

---

## Phase 9 · 运维操作

### 升级

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml
```

### 查看当前配置

```bash
helm get values prometheus -n monitoring
```

### 常用 PromQL 查询

```promql
# 集群 CPU 使用率
100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100

# 集群内存使用率
(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100

# Pod 重启次数 Top 10
topk(10, sum by(namespace, pod)(kube_pod_container_status_restarts_total))

# 节点磁盘使用率
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# API Server 请求延迟 P99
histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le, verb))

# etcd leader 变更次数
changes(etcd_server_is_leader[1h])
```

### 故障排查

```bash
# Prometheus 无法采集某 Target
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# 访问 /targets 查看错误信息

# Grafana 无数据
# 1. 检查数据源：Settings → Data Sources → Prometheus → Test
# 2. 检查时间范围是否正确
# 3. 在 Explore 中直接执行 PromQL 确认数据存在

# Alertmanager 不发通知
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager
# 检查 webhook URL 是否可达
```

---

## 监控覆盖范围总览

| 监控层 | 数据来源 | 关键指标 |
|--------|----------|----------|
| **主机层** | node-exporter | CPU / 内存 / 磁盘 / 网络 / 负载 |
| **容器层** | kubelet (cAdvisor) | 容器 CPU / 内存 / 网络 / IO |
| **K8s 对象** | kube-state-metrics | Pod 状态 / Deployment 副本 / Job 完成率 |
| **控制平面** | API Server / Scheduler / Controller | 请求延迟 / 队列深度 / 错误率 |
| **etcd** | 自定义 scrape（TLS） | leader 变更 / WAL fsync / 存储大小 |
| **LB** | HAProxy stats | 后端健康 / 连接数 / 请求率 |
| **GPU** | DCGM Exporter | 利用率 / 温度 / 显存 / ECC / NVLink |
| **网络** | Calico metrics | 策略命中 / 流量 / 丢包 |
| **业务应用** | ServiceMonitor / 注解 | 自定义指标（QPS / 延迟 / 错误率） |

---

## 部署检查清单

- [ ] etcd 证书 Secret 已创建
- [ ] prometheus-values.yaml 已定制（存储/密码/告警通道）
- [ ] kube-prometheus-stack Helm 安装成功
- [ ] 所有 monitoring Pod Running
- [ ] Prometheus Targets 全部 UP（含 etcd 和 HAProxy）
- [ ] Grafana 可访问，Dashboard 数据正常
- [ ] 告警规则已部署（PrometheusRule）
- [ ] Alertmanager 通知渠道已验证
- [ ] GPU ServiceMonitor 已配置（如有 GPU）
- [ ] 业务应用 ServiceMonitor 已配置
