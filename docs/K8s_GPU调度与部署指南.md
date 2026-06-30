# Kubernetes GPU 调度与部署完整指南

> 从原理到部署：NVIDIA GPU Operator 安装、GPU 资源调度、MIG 分区、Time-Slicing 共享、DRA 动态资源分配
>
> 撰写人：孟希东（测试）

---

## 1. 原理概述

### Kubernetes 为什么不能直接使用 GPU？

Kubernetes 原生只理解 CPU 和内存两种资源。GPU 是"扩展资源"（Extended Resource），需要通过 **Device Plugin 框架** 将 GPU 暴露为可调度资源 `nvidia.com/gpu`。

### 核心组件栈（从底到顶）

```
硬件层:  NVIDIA GPU 硬件（A100/H100/B300 等）
    ↓
驱动层:  NVIDIA GPU Driver（内核模块）
    ↓
运行时:  NVIDIA Container Toolkit（让容器访问 GPU）
    ↓
插件层:  NVIDIA Device Plugin（向 K8s 注册 GPU 资源）
    ↓
调度层:  kube-scheduler（根据 nvidia.com/gpu 请求分配 Pod 到节点）
```

### 两种部署方案

| 方案 | 说明 | 适用场景 |
|------|------|----------|
| **NVIDIA Device Plugin** | 仅部署设备插件 DaemonSet，需手动预装驱动和 Toolkit | 小集群、已有驱动管理方案 |
| **NVIDIA GPU Operator**（推荐） | 自动化部署整个 GPU 栈（驱动→Toolkit→Plugin→监控） | 生产环境、大规模集群 |

> 本文以 **GPU Operator** 方案为主，这是 2026 年的主流做法。

---

## 2. 前置条件

### 节点要求

- 节点安装了 NVIDIA GPU 硬件
- 操作系统：Ubuntu 22.04/24.04、RHEL 8/9、CentOS Stream 9 等
- 容器运行时：containerd（推荐）或 CRI-O
- 内核版本与 NVIDIA 驱动兼容
- **所有 GPU 节点使用相同的操作系统版本**（使用容器化驱动时）

### 集群要求

- Kubernetes 1.28+（推荐 1.30+）
- Helm 3.x 已安装
- 集群有默认的 StorageClass（GPU Operator 部分组件需要）
- 如果启用 Pod Security Admission，需给 Operator 命名空间设置 privileged 标签

### 检查 GPU 硬件

```bash
# 在 GPU 节点上执行
lspci | grep -i nvidia          # 确认 GPU 硬件存在
```

---

## 3. 部署 NVIDIA GPU Operator（推荐方案）

### 3.1 添加 Helm 仓库

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 3.2 创建命名空间

```bash
kubectl create namespace gpu-operator
```

### 3.3 如果启用了 Pod Security Admission

```bash
kubectl label namespace gpu-operator pod-security.kubernetes.io/enforce=privileged
```

### 3.4 安装 GPU Operator

```bash
# 基本安装（GPU Operator 自动安装驱动）
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --wait
```

**如果节点已预装 NVIDIA 驱动**（不需要 Operator 安装驱动）：

```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --wait
```

### 3.5 验证安装

```bash
# 查看 GPU Operator 所有 Pod 状态
kubectl get pods -n gpu-operator

# 期望看到以下组件全部 Running：
# - nvidia-driver-daemonset-*        （GPU 驱动，如未预装）
# - nvidia-container-toolkit-*       （容器工具包）
# - nvidia-device-plugin-*           （设备插件）
# - nvidia-dcgm-exporter-*           （GPU 监控指标导出）
# - gpu-feature-discovery-*          （GPU 特征发现，自动打标签）
# - nvidia-operator-validator-*      （验证器）
```

### 3.6 确认 GPU 资源已注册

```bash
# 查看节点上的 GPU 资源
kubectl get nodes -o json | jq '.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) | {name: .metadata.name, gpus: .status.allocatable["nvidia.com/gpu"]}'

# 简单方式
kubectl describe node <gpu-node> | grep -A5 "Allocatable"
# 应该能看到 nvidia.com/gpu: N
```

### 3.7 运行测试 Pod

```yaml
# cuda-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vectoradd
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-vectoradd
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0-ubuntu22.04
    resources:
      limits:
        nvidia.com/gpu: 1
```

```bash
kubectl apply -f cuda-test.yaml
kubectl logs cuda-vectoradd
# 看到 "Test PASSED" 表示 GPU 调度成功
```

---

## 4. GPU 资源调度规则

### 4.1 基本调度方式

Pod 通过 `resources.limits` 请求 GPU：

```yaml
resources:
  limits:
    nvidia.com/gpu: 2    # 请求 2 块 GPU
```

### 4.2 调度约束（重要）

- GPU **只能在 `limits` 中指定**（不能只写 requests 不写 limits）
- `requests` 和 `limits` 的值**必须相等**（不支持超售）
- GPU 数量必须是**整数**（默认不能请求 0.5 个 GPU）
- **不指定 GPU 的 Pod 不会被分配到 GPU**
- 一个容器可以请求多个 GPU，但不能跨节点

### 4.3 单 GPU Pod 示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ml-inference
  template:
    metadata:
      labels:
        app: ml-inference
    spec:
      containers:
      - name: inference
        image: my-registry/ml-model:v1
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "8Gi"
            cpu: "4"
          requests:
            memory: "8Gi"
            cpu: "4"
        # GPU 只写 limits，K8s 自动设 requests = limits
```

### 4.4 多 GPU Pod 示例（训练任务）

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-job
spec:
  restartPolicy: Never
  containers:
  - name: trainer
    image: my-registry/train:v1
    resources:
      limits:
        nvidia.com/gpu: 4    # 使用 4 块 GPU
        memory: "64Gi"
        cpu: "16"
```

### 4.5 使用 nodeSelector 指定 GPU 类型

GPU Feature Discovery 会自动给节点打标签：

```bash
kubectl describe node <gpu-node> | grep nvidia.com
# nvidia.com/gpu.product=NVIDIA-A100-SXM4-80GB
# nvidia.com/gpu.memory=81920
# nvidia.com/cuda.driver.major=535
# nvidia.com/gpu.count=8
```

在 Pod 中使用：

```yaml
spec:
  nodeSelector:
    nvidia.com/gpu.product: NVIDIA-A100-SXM4-80GB
  containers:
  - name: app
    resources:
      limits:
        nvidia.com/gpu: 1
```

---

## 5. GPU 共享策略

### 5.1 Time-Slicing（时间片共享）

多个 Pod 共享同一块 GPU 的计算时间，适合轻量级推理和开发。

**配置 ConfigMap：**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 4          # 每块物理 GPU 虚拟为 4 份
```

**更新 GPU Operator 配置：**

```bash
helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set devicePlugin.config.name=time-slicing-config \
  --set devicePlugin.config.default=any
```

配置后，一块物理 GPU 变成 4 个 `nvidia.com/gpu`，4 个 Pod 可以共享。

> ⚠️ Time-Slicing 没有显存隔离，多个 Pod 共享全部显存。如果一个 Pod 显存用满，其他 Pod 会 OOM。

### 5.2 MIG（Multi-Instance GPU）

将一块物理 GPU 切分为多个独立的硬件实例，每个实例有**独立的显存和计算核心**，完全隔离。

**支持的 GPU**：A100、A30、H100（不支持 V100、T4）

**MIG 配置示例（A100 80GB → 7 个 10GB 实例）：**

```yaml
# mig-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mig-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    mig-configs:
      all-1g.10gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "1g.10gb": 7       # 7 个 1g.10gb 实例
```

```bash
helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set migManager.config.name=mig-config \
  --set mig.strategy=mixed
```

**使用 MIG 实例的 Pod：**

```yaml
resources:
  limits:
    nvidia.com/mig-1g.10gb: 1   # 请求一个 MIG 实例
```

### 5.3 对比

| 特性 | 整卡分配 | Time-Slicing | MIG |
|------|----------|-------------|-----|
| 隔离性 | 完全隔离 | 无隔离 | 硬件隔离 |
| 显存隔离 | ✅ | ❌ | ✅ |
| 计算隔离 | ✅ | ❌ | ✅ |
| 支持 GPU | 所有 | 所有 | A100/A30/H100 |
| 最大共享数 | 1 | 自定义 | 最多 7 |
| 适用场景 | 训练 | 轻量推理/开发 | 多租户推理 |

---

## 6. DRA 动态资源分配（Kubernetes 1.34+, 2026 新特性）

### 6.1 什么是 DRA？

DRA（Dynamic Resource Allocation）在 Kubernetes 1.34 中 GA，用 ResourceClaim 替代了传统的 Device Plugin 模型。

**核心优势：**
- 不再是简单的 `nvidia.com/gpu: 1` 整数计数
- 可以指定 GPU 属性约束（显存大小、MIG 配置、NVLink 拓扑）
- 支持跨 Pod 共享 ResourceClaim
- 调度器感知 GPU 拓扑，避免跨 NUMA 调度

### 6.2 DRA 使用示例

```yaml
# 定义资源请求
apiVersion: resource.k8s.io/v1beta1
kind: ResourceClaim
metadata:
  name: gpu-claim
spec:
  devices:
    requests:
    - name: gpu
      deviceClassName: gpu.nvidia.com
      selectors:
      - cel:
          expression: "device.attributes['memory'].comparableInt >= quantity('40Gi')"
---
# Pod 引用 ResourceClaim
apiVersion: v1
kind: Pod
metadata:
  name: training
spec:
  resourceClaims:
  - name: gpu
    resourceClaimName: gpu-claim
  containers:
  - name: trainer
    image: my-training:v1
    resources:
      claims:
      - name: gpu
```

> DRA 是 2026 年的新方向，但 Device Plugin 仍然是目前最成熟的生产方案。

---

## 7. GPU 监控

### 7.1 DCGM Exporter

GPU Operator 自动部署 dcgm-exporter，暴露 GPU Prometheus 指标。

```bash
# 查看 dcgm-exporter 指标
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400
curl localhost:9400/metrics
```

### 7.2 关键监控指标

| Prometheus 指标 | 说明 |
|----------------|------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU 利用率 (%) |
| `DCGM_FI_DEV_FB_USED` | 已用显存 (MB) |
| `DCGM_FI_DEV_FB_FREE` | 空闲显存 (MB) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 (°C) |
| `DCGM_FI_DEV_POWER_USAGE` | 功耗 (W) |
| `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | ECC 单比特错误 |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | ECC 双比特错误 |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NVLink 带宽 |

### 7.3 Grafana Dashboard

导入 NVIDIA 官方 Grafana Dashboard ID: **12239**，可视化 GPU 集群状态。

---

## 8. 故障排查

### GPU 节点没有 nvidia.com/gpu 资源

```bash
# 1. 检查 GPU Operator Pod 状态
kubectl get pods -n gpu-operator

# 2. 检查驱动是否安装成功
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# 3. 检查 device plugin 日志
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset

# 4. 在节点上直接检查
ssh <node>
nvidia-smi          # 驱动是否正常
ls /dev/nvidia*      # 设备文件是否存在
```

### Pod 一直 Pending（GPU 不足）

```bash
# 查看 Pod 事件
kubectl describe pod <name>
# 常见原因：Insufficient nvidia.com/gpu

# 查看集群 GPU 总量和已分配
kubectl describe nodes | grep -A5 "Allocated resources" | grep nvidia
```

### Pod 运行但 GPU 不可用

```bash
# 进入 Pod 检查
kubectl exec -it <pod> -- nvidia-smi
# 如果报错 "Failed to initialize NVML"：
# - 检查 NVIDIA Container Toolkit 是否正常
# - 检查 containerd 配置中 nvidia runtime 是否注册
```

### 常见问题速查

| 问题 | 原因 | 解决 |
|------|------|------|
| nvidia-driver pod CrashLoop | 内核版本不兼容 | 升级内核或指定兼容的驱动版本 |
| gpu-feature-discovery 失败 | 驱动未就绪 | 等驱动 Pod Ready 后自动恢复 |
| Pod OOMKilled（GPU 上） | 显存不足 | 减少 batch size 或请求更多 GPU |
| Time-slicing Pod 互相影响 | 无显存隔离 | 改用 MIG 或整卡分配 |
| MIG 切分后 GPU 数量异常 | MIG 配置未生效 | 重启 mig-manager，检查配置 |

---

## 9. 生产最佳实践

1. **始终使用 `resources.limits`**：不设 GPU limits 的 Pod 不会分配 GPU
2. **使用 nodeSelector / tolerations**：将 GPU 节点和 CPU 节点分开，避免普通 Pod 占用 GPU 节点
3. **设置 GPU 节点污点**：`kubectl taint nodes <gpu-node> nvidia.com/gpu=present:NoSchedule`
4. **监控 GPU 利用率**：利用率持续低于 30% 考虑 Time-Slicing 或 MIG
5. **预留系统 GPU**：如果节点有 8 块 GPU，可保留 1 块给系统/监控
6. **定期检查 ECC 错误**：持续增长的 uncorrected ECC 需要更换 GPU
7. **使用 Priority / Preemption**：训练任务高优先级，开发任务低优先级可被抢占
8. **Checkpoint 机制**：训练任务必须支持定期保存 checkpoint，GPU 故障时可恢复
