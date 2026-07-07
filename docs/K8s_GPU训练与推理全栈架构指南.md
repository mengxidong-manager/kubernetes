# K8s GPU 训练与推理全栈架构指南

> 从物理部署到 AI 平台：集群在哪里、GPU 如何被调用、训练和推理工作流、AI 平台组件栈、存储与网络设计、多租户管理
>
> 撰写人：孟希東

---

## 目录

- [1. 物理部署架构](#1-物理部署架构)
- [2. GPU 在容器中如何工作](#2-gpu-在容器中如何工作)
- [3. 训练工作流](#3-训练工作流)
- [4. 推理工作流](#4-推理工作流)
- [5. AI 平台组件栈](#5-ai-平台组件栈2026)
- [6. 存储架构](#6-存储架构)
- [7. 网络架构](#7-网络架构)
- [8. 多租户与资源管理](#8-多租户与资源管理)
- [9. AI 工作负载监控](#9-ai-工作负载监控)
- [10. 完整部署路线图](#10-完整部署路线图)

---

## 1. 物理部署架构

### K8s 集群部署在哪里？

K8s 集群直接部署在数据中心的物理服务器上。GPU 服务器装上 Ubuntu + containerd + kubelet，join 到集群成为 Worker 节点。

```
数据中心机房
│
├── 管理区（可以是虚拟机或轻量物理机）
│   ├── etcd-01/02/03          ← 独立 etcd 集群
│   ├── lb-01/02               ← HAProxy + Keepalived
│   └── k8s-master-01/02/03   ← Control Plane
│
├── GPU 计算区（必须是物理服务器 + GPU 卡）
│   ├── k8s-gpu-01  (8× A100 80GB)   ← K8s Worker 节点
│   ├── k8s-gpu-02  (8× A100 80GB)   ← K8s Worker 节点
│   ├── k8s-gpu-03  (8× H100 SXM5)   ← K8s Worker 节点
│   └── ...                           ← 按需扩展
│
├── 存储区
│   ├── Ceph / Lustre / VAST 集群     ← 分布式存储
│   └── NFS Server（小规模场景）
│
└── 网络区
    ├── Spine-Leaf 以太网交换机        ← 管理/Service 网络
    └── InfiniBand / Spectrum-X       ← GPU 训练高速网络（可选）
```

### 为什么用 K8s 管理 GPU？

| 没有 K8s | 有 K8s |
|----------|--------|
| SSH 到服务器手动跑训练 | 提交 YAML 自动调度 |
| 人工分配 GPU 卡号 | 自动发现空闲 GPU 并分配 |
| 脚本崩了没人知道 | 自动健康检查、失败重启 |
| 多人抢同一台机器 | 多租户隔离、配额管理 |
| 扩容需要人工配置 | kubectl scale / HPA 自动扩缩 |
| 无统一监控 | Prometheus + Grafana 全栈监控 |

---

## 2. GPU 在容器中如何工作

### 完整调用链

```
应用代码 (PyTorch / vLLM / TensorRT)
    ↓  调用 torch.cuda / CUDA API
CUDA Runtime (libcudart.so，容器镜像自带)
    ↓
NVIDIA Container Toolkit (将 /dev/nvidia* 设备挂载到容器中)
    ↓
NVIDIA GPU Driver (宿主机内核模块 nvidia.ko)
    ↓
GPU 硬件 (A100 / H100 / B300)
```

### 关键点

- **应用代码不知道自己在容器里**。`torch.cuda.is_available()` 返回 True，`nvidia-smi` 正常显示，和裸机运行完全一样
- **驱动在宿主机，CUDA 在容器镜像**。NVIDIA Container Toolkit 负责在运行时把宿主机的 GPU 设备和驱动库映射到容器内部
- **K8s 通过 Device Plugin 管理分配**。Pod 声明 `nvidia.com/gpu: N`，K8s 调度到有 N 块空闲 GPU 的节点，kubelet 通过 Device Plugin 将具体的 GPU 设备分配给容器

### 容器内实际发生了什么

```bash
# Pod 请求 nvidia.com/gpu: 2 后，容器内可以看到：

$ nvidia-smi
+-------+-------+-----+----+
| GPU 0 | A100  | 80G | OK |   ← 只看到被分配的 2 块
| GPU 1 | A100  | 80G | OK |   ← 其他 GPU 对容器不可见
+-------+-------+-----+----+

$ ls /dev/nvidia*
/dev/nvidia0  /dev/nvidia1  /dev/nvidiactl  /dev/nvidia-uvm

$ python -c "import torch; print(torch.cuda.device_count())"
2
```

---

## 3. 训练工作流

### 3.1 单机多卡训练

最简单的场景，一个 Pod 使用一台机器上的多块 GPU：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: single-node-training
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: trainer
        image: nvcr.io/nvidia/pytorch:24.07-py3
        command:
        - torchrun
        - --standalone
        - --nproc_per_node=8        # 使用 8 块 GPU
        - train.py
        - --model=llama-7b
        - --batch-size=32
        - --epochs=10
        resources:
          limits:
            nvidia.com/gpu: 8        # 请求 8 块 GPU
            memory: 256Gi
            cpu: "64"
        volumeMounts:
        - name: dataset
          mountPath: /data
        - name: checkpoints
          mountPath: /checkpoints
      volumes:
      - name: dataset
        persistentVolumeClaim:
          claimName: training-dataset
      - name: checkpoints
        persistentVolumeClaim:
          claimName: checkpoint-pvc
```

### 3.2 分布式多机多卡训练（Kubeflow Training Operator）

跨多台 GPU 服务器训练大模型，需要 Gang Scheduling（所有 Pod 同时启动）：

```yaml
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: llm-distributed-training
spec:
  nprocPerNode: "8"                  # 每节点 8 卡
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      template:
        spec:
          containers:
          - name: trainer
            image: my-registry/llm-train:v1
            command:
            - torchrun
            - train.py
            - --model=llama-70b
            resources:
              limits:
                nvidia.com/gpu: 8
                memory: 512Gi
                rdma/rdma_shared_device_a: 1   # InfiniBand RDMA（可选）
            volumeMounts:
            - name: shared-data
              mountPath: /data
          volumes:
          - name: shared-data
            persistentVolumeClaim:
              claimName: training-data
    Worker:
      replicas: 3                    # 3 个 Worker = 共 4 台 × 8 卡 = 32 GPU
      template:
        spec:
          containers:
          - name: trainer
            image: my-registry/llm-train:v1
            command:
            - torchrun
            - train.py
            - --model=llama-70b
            resources:
              limits:
                nvidia.com/gpu: 8
                memory: 512Gi
            volumeMounts:
            - name: shared-data
              mountPath: /data
          volumes:
          - name: shared-data
            persistentVolumeClaim:
              claimName: training-data
```

Training Operator 自动处理：节点发现（`MASTER_ADDR`/`MASTER_PORT`/`WORLD_SIZE`/`RANK`）、所有 Pod 同时启动（Gang Scheduling，配合 Volcano/Kueue）、失败重启和 checkpoint 恢复。

### 3.3 训练流程全景

```
数据科学家编写训练代码 + Dockerfile
    ↓ 推送到镜像仓库（Harbor / DockerHub）
提交 PyTorchJob YAML
    ↓
Kueue 检查命名空间 GPU 配额
    ↓ 配额充足，放行
Volcano Gang Scheduler 等待所有 GPU 节点可用
    ↓ 32 块 GPU 同时就绪
kubelet 在 4 台节点启动 Pod
    ↓ NVIDIA Container Toolkit 挂载 GPU 到容器
Training Operator 注入分布式环境变量
    ↓
torchrun 启动 DDP 训练
    ↓ NCCL 通过 NVLink(机内) + InfiniBand(跨机) 通信
定期保存 Checkpoint 到分布式存储
    ↓
训练完成 → 模型文件写入共享存储
    ↓
注册到 MLflow Model Registry
```

---

## 4. 推理工作流

### 4.1 vLLM 直接部署（简单场景）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen-72b
spec:
  replicas: 2                        # 2 个推理实例
  selector:
    matchLabels:
      app: vllm-qwen
  template:
    metadata:
      labels:
        app: vllm-qwen
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        args:
        - --model=/models/Qwen2.5-72B-Instruct
        - --tensor-parallel-size=4    # 4 卡张量并行
        - --max-model-len=32768
        - --gpu-memory-utilization=0.9
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 4         # 每实例 4 卡
            memory: 128Gi
        volumeMounts:
        - name: models
          mountPath: /models
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: model-storage
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-api
spec:
  selector:
    app: vllm-qwen
  ports:
  - port: 8000
    targetPort: 8000
```

业务调用方式（OpenAI 兼容 API）：

```bash
# 集群内部
curl http://vllm-api:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen2.5-72B-Instruct",
    "messages": [{"role": "user", "content": "什么是 K8s？"}],
    "max_tokens": 512
  }'

# 集群外部（通过 Ingress 或 NodePort）
curl https://llm-api.company.com/v1/chat/completions ...
```

### 4.2 KServe 部署（生产级，2026 标准）

KServe 是 CNCF 孵化项目，提供自动扩缩、金丝雀发布、流量切分：

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen-72b
spec:
  predictor:
    model:
      modelFormat:
        name: huggingface
      storageUri: "pvc://model-storage/Qwen2.5-72B-Instruct"
      resources:
        limits:
          nvidia.com/gpu: "4"
          memory: 128Gi
      runtimeVersion: latest
    minReplicas: 1
    maxReplicas: 10                  # 自动扩缩到 10 实例
    scaleTarget: 5                   # 每实例并发 5 请求时扩容
    scaleMetric: concurrency
```

KServe 自动处理：模型加载和预热、基于并发/QPS 的自动扩缩（可缩至 0）、金丝雀发布（新旧模型流量切分）、A/B 测试、健康检查和滚动更新。

### 4.3 推理流程全景

```
用户/业务应用
    ↓ HTTPS 请求
Ingress / Gateway（Nginx / Istio）
    ↓
K8s Service（ClusterIP / NodePort）
    ↓ 负载均衡到多个 Pod
vLLM / Triton / KServe Pod
    ↓ 模型已加载在 GPU 显存中
CUDA → GPU Driver → GPU 硬件
    ↓ 推理计算
返回结果（JSON）
    ↓
用户/业务应用
```

---

## 5. AI 平台组件栈（2026）

### 分层架构

```
┌─────────────────────────────────────────────────────┐
│  用户层                                               │
│  Jupyter Notebook · Kubeflow UI · MLflow UI · API    │
├─────────────────────────────────────────────────────┤
│  AI 平台层                                            │
│  ┌──────────┐ ┌────────┐ ┌────────┐ ┌─────────────┐ │
│  │ Kubeflow │ │ KServe │ │ MLflow │ │ Jupyter Hub │ │
│  │ Training │ │        │ │        │ │             │ │
│  │ Operator │ │ 推理服务 │ │ 实验追踪 │ │ Notebook   │ │
│  └──────────┘ └────────┘ └────────┘ └─────────────┘ │
├─────────────────────────────────────────────────────┤
│  调度层                                               │
│  ┌────────────┐ ┌──────────┐ ┌────────────────────┐ │
│  │ Volcano    │ │ Kueue    │ │ GPU Operator       │ │
│  │ Gang调度    │ │ 配额管理  │ │ Device Plugin/DCGM │ │
│  └────────────┘ └──────────┘ └────────────────────┘ │
├─────────────────────────────────────────────────────┤
│  K8s 层                                              │
│  API Server · Scheduler · kubelet · containerd       │
├─────────────────────────────────────────────────────┤
│  基础设施层                                            │
│  GPU 服务器 · NVLink · InfiniBand · 分布式存储 · 液冷    │
└─────────────────────────────────────────────────────┘
```

### 各组件说明

| 组件 | 用途 | 部署方式 |
|------|------|----------|
| **Kubeflow Training Operator** | 分布式训练（PyTorchJob/TFJob/MPIJob），自动注入分布式环境变量，处理故障恢复 | `kubectl apply` |
| **Kubeflow Pipelines** | ML 工作流编排（DAG），数据预处理→训练→评估→部署的自动化流水线 | Helm |
| **Katib** | 超参数自动调优，支持网格/随机/贝叶斯搜索 | Kubeflow 子组件 |
| **Volcano** | GPU 批调度器，Gang Scheduling（多卡同时分配），公平共享 | Helm |
| **Kueue** | 工作负载队列管理，命名空间级 GPU 配额，准入控制 | Helm |
| **KServe** | 模型推理服务化，自动扩缩（可缩至 0），金丝雀发布，多框架支持 | Helm |
| **vLLM** | LLM 推理引擎，PagedAttention，连续批处理，OpenAI 兼容 API | Deployment |
| **Triton Inference Server** | 多框架推理（TF/PyTorch/ONNX/TensorRT），动态批处理 | Deployment |
| **MLflow** | 实验追踪，模型注册中心，版本管理，模型血缘 | Helm |
| **JupyterHub** | 多用户 Notebook，每人独立 GPU 环境 | Helm |
| **NVIDIA GPU Operator** | 自动化 GPU 栈（驱动→Toolkit→Plugin→DCGM） | Helm |
| **llm-d** | 超大模型分布式推理（跨节点张量并行），KV Cache 卸载（2025-2026 新兴） | Deployment |

### 部署命令汇总

```bash
# GPU Operator
helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace

# Volcano（Gang Scheduling）
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace

# Kueue（配额管理）
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.10.0/manifests.yaml

# Kubeflow Training Operator
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone"

# KServe
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.14.0/kserve.yaml

# MLflow
helm install mlflow community-charts/mlflow -n mlflow --create-namespace

# JupyterHub
helm install jupyterhub jupyterhub/jupyterhub -n jupyter --create-namespace -f jupyter-values.yaml
```

---

## 6. 存储架构

### 存储分层

```
┌──────────────────────────────────────────────┐
│  GPU 显存（HBM）                               │
│  模型权重 + KV Cache + 中间激活值                 │
│  ← 最快，最贵，容量有限（80-288GB/卡）             │
├──────────────────────────────────────────────┤
│  本地 NVMe SSD                                │
│  模型缓存、数据集预取                             │
│  ← 快，延迟低，节点级                             │
├──────────────────────────────────────────────┤
│  分布式存储（Ceph / Lustre / VAST）              │
│  训练数据集、Checkpoint、模型文件                   │
│  ← 大容量，所有节点共享访问                        │
├──────────────────────────────────────────────┤
│  对象存储（S3 / MinIO / SeaweedFS）              │
│  模型归档、日志、管道产物                           │
│  ← 最便宜，无限扩展                              │
└──────────────────────────────────────────────┘
```

### K8s 存储配置

```yaml
# 1. 训练数据集 PVC（ReadOnlyMany，多 Pod 同时读取）
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: training-dataset
spec:
  accessModes: [ReadOnlyMany]
  storageClassName: ceph-fs
  resources:
    requests:
      storage: 10Ti

# 2. Checkpoint PVC（ReadWriteMany，训练 Pod 写入）
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: checkpoint-storage
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ceph-fs
  resources:
    requests:
      storage: 2Ti

# 3. 模型仓库 PVC（推理 Pod 挂载）
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage
spec:
  accessModes: [ReadOnlyMany]
  storageClassName: ceph-fs
  resources:
    requests:
      storage: 5Ti
```

---

## 7. 网络架构

### 双网络设计

| 网络 | 用途 | 带宽 | 协议 |
|------|------|------|------|
| **管理/Service 网络** | K8s API、Pod 通信、用户访问 | 10-25 Gbps 以太网 | TCP/IP |
| **GPU 训练网络** | 分布式训练的 AllReduce 通信 | 100-400 Gbps | InfiniBand / RoCE |

```
                    管理网络（10G 以太网）
        ┌──────────┬──────────┬──────────┐
     Master     GPU-01     GPU-02     GPU-03
        └──────────┴──────────┴──────────┘
                    训练网络（InfiniBand 400G）
                 GPU-01 ⇄ GPU-02 ⇄ GPU-03
```

### 机内 vs 跨机通信

| 通信范围 | 技术 | 带宽 |
|----------|------|------|
| 同卡内 | GPU 内部互联 | — |
| 同机内多卡 | NVLink / NVSwitch | 900 GB/s - 3.6 TB/s |
| 跨机多卡 | InfiniBand / RoCE | 100-400 Gbps |
| 跨机多卡（Calico） | 以太网 | 10-25 Gbps（训练慢） |

> 小规模（<16 GPU）跨机训练用 RoCE/以太网可以接受。大规模（>64 GPU）分布式训练强烈建议 InfiniBand。

### NCCL 配置

```yaml
# Pod 环境变量配置 NCCL 使用 InfiniBand
env:
- name: NCCL_IB_DISABLE
  value: "0"              # 启用 IB
- name: NCCL_NET_GDR_LEVEL
  value: "5"              # GPUDirect RDMA
- name: NCCL_SOCKET_IFNAME
  value: "eth0"           # 管理网络网卡
- name: NCCL_IB_HCA
  value: "mlx5_0"         # IB 网卡
```

---

## 8. 多租户与资源管理

### 命名空间隔离

```bash
# 按团队划分命名空间
kubectl create ns team-nlp
kubectl create ns team-cv
kubectl create ns team-infra
```

### GPU 配额（ResourceQuota）

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: team-nlp
spec:
  hard:
    requests.nvidia.com/gpu: "16"    # NLP 团队最多使用 16 块 GPU
    limits.nvidia.com/gpu: "16"
    persistentvolumeclaims: "20"
```

### Kueue 队列管理

```yaml
# 集群级 GPU 资源池
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: gpu-cluster-queue
spec:
  resourceGroups:
  - coveredResources: ["nvidia.com/gpu"]
    flavors:
    - name: a100-80gb
      resources:
      - name: nvidia.com/gpu
        nominalQuota: 64             # 集群共 64 块 GPU
---
# 团队级配额分配
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: nlp-queue
  namespace: team-nlp
spec:
  clusterQueue: gpu-cluster-queue
```

### Priority 优先级（训练 vs 开发）

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: training-high
value: 1000000
preemptionPolicy: PreemptLowerPriority   # 可抢占低优先级
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: dev-low
value: 100
preemptionPolicy: Never
```

---

## 9. AI 工作负载监控

### 在 Prometheus + Grafana 基础上增加 AI 指标

| 指标来源 | 关键指标 | 用途 |
|----------|----------|------|
| DCGM Exporter | GPU 利用率 / 温度 / 显存 / ECC / NVLink | GPU 健康 |
| vLLM /metrics | 请求延迟 / 吞吐(tokens/s) / 队列深度 / KV Cache 使用率 | 推理性能 |
| Training Job | 训练 loss / 学习率 / 吞吐(samples/s) / GPU 利用率 | 训练进度 |
| Kueue | 队列等待时间 / 准入率 / 配额使用率 | 调度效率 |

### 关键 PromQL

```promql
# GPU 集群平均利用率
avg(DCGM_FI_DEV_GPU_UTIL)

# 推理吞吐（tokens/秒，vLLM）
rate(vllm:num_generation_tokens_total[5m])

# 推理请求 P99 延迟
histogram_quantile(0.99, rate(vllm:request_duration_seconds_bucket[5m]))

# 各团队 GPU 使用量
sum by (namespace)(kube_pod_resource_limit{resource="nvidia_com_gpu"})

# Kueue 队列等待任务数
kueue_pending_workloads
```

---

## 10. 完整部署路线图

### 从零到生产的部署顺序

```
Phase 1 · 基础集群
    K8s HA 集群（3Master + 3etcd + 2LB + N Worker）
    ↓
Phase 2 · GPU 就绪
    GPU Operator → Device Plugin → GPU 资源注册
    ↓
Phase 3 · 监控体系
    Prometheus + Grafana + DCGM Exporter
    ↓
Phase 4 · 存储
    分布式存储（Ceph/NFS）→ StorageClass → PVC
    ↓
Phase 5 · AI 调度
    Volcano（Gang Scheduling）+ Kueue（配额管理）
    ↓
Phase 6 · 训练平台
    Kubeflow Training Operator → PyTorchJob/MPIJob
    ↓
Phase 7 · 推理平台
    KServe 或 vLLM Deployment → Ingress 暴露 API
    ↓
Phase 8 · 实验管理
    MLflow → 实验追踪 + 模型注册中心
    ↓
Phase 9 · 开发环境
    JupyterHub → 多用户 Notebook + GPU
    ↓
Phase 10 · 多租户
    Namespace + ResourceQuota + Kueue + RBAC
```

### 对应文档索引

| 阶段 | 文档 |
|------|------|
| Phase 1 | [K8s 1.34 生产环境 HA 集群部署指南](K8s_1.34_生产环境HA集群部署指南.md) |
| Phase 2 | [K8s GPU 调度与部署指南](K8s_GPU调度与部署指南.md) |
| Phase 3 | [Prometheus + Grafana 监控部署指南](Prometheus_Grafana_监控部署指南.md) |
| Phase 4-10 | 本文档 |
