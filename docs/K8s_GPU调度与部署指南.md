# Kubernetes GPU 调度与部署完整指南

> 从原理到部署：NVIDIA GPU Operator 安装、GPU 资源调度、MIG 分区、Time-Slicing 共享、DRA 动态资源分配
>
> 撰写人：孟希東

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
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --wait
```

**如果节点已预装 NVIDIA 驱动**：

```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --wait
```

### 3.5 验证安装

```bash
kubectl get pods -n gpu-operator
```

### 3.6 确认 GPU 资源已注册

```bash
kubectl get nodes -o json | jq '.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) | {name: .metadata.name, gpus: .status.allocatable["nvidia.com/gpu"]}'
```

### 3.7 运行测试 Pod

```yaml
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

---

## 4. GPU 资源调度规则

- GPU **只能在 `limits` 中指定**
- `requests` 和 `limits` 必须相等（不支持超售）
- GPU 数量必须是整数
- 不指定 GPU 的 Pod 不会被分配到 GPU

```yaml
resources:
  limits:
    nvidia.com/gpu: 2    # 请求 2 块 GPU
```

### 使用 nodeSelector 指定 GPU 类型

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
          replicas: 4
```

> ⚠️ Time-Slicing 没有显存隔离。

### 5.2 MIG（Multi-Instance GPU）

支持 A100/A30/H100。硬件级隔离。

```yaml
resources:
  limits:
    nvidia.com/mig-1g.10gb: 1
```

### 5.3 对比

| 特性 | 整卡 | Time-Slicing | MIG |
|------|------|-------------|-----|
| 隔离性 | 完全 | 无 | 硬件级 |
| 显存隔离 | ✅ | ❌ | ✅ |
| 适用 | 训练 | 轻量推理/开发 | 多租户推理 |

---

## 6. DRA 动态资源分配（Kubernetes 1.34+）

```yaml
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
```

---

## 7. GPU 监控

DCGM Exporter 关键指标：`DCGM_FI_DEV_GPU_UTIL`(利用率) · `DCGM_FI_DEV_FB_USED`(显存) · `DCGM_FI_DEV_GPU_TEMP`(温度) · `DCGM_FI_DEV_POWER_USAGE`(功耗) · `DCGM_FI_DEV_ECC_*`(ECC错误)

Grafana Dashboard ID: **12239**

---

## 8. 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| nvidia-driver CrashLoop | 内核不兼容 | 升级内核或指定驱动版本 |
| Pod Pending | GPU 不足 | `kubectl describe nodes \| grep nvidia` |
| NVML 初始化失败 | Toolkit 异常 | 检查 containerd nvidia runtime |
| OOMKilled | 显存不足 | 减少 batch size 或加 GPU |
| Time-slicing 互相影响 | 无隔离 | 改用 MIG |

---

## 9. 生产最佳实践

1. 始终使用 `resources.limits` 请求 GPU
2. 使用 nodeSelector / tolerations 分离 GPU 和 CPU 节点
3. 设置 GPU 节点污点：`kubectl taint nodes <node> nvidia.com/gpu=present:NoSchedule`
4. 利用率 <30% 考虑 Time-Slicing 或 MIG
5. 定期检查 ECC 错误
6. 训练任务必须支持 checkpoint
