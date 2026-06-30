# Kubernetes 学习与运维资料

> Kubernetes 学习资源、运维文档、示例 YAML、实用脚本
>
> 维护人：孟希东（测试） · 最后更新: 2026-06-30

---

## 📁 仓库结构

```
├── README.md                                    # 本文件
├── docs/                                        # 运维文档
│   ├── Linux_K8s_运维命令速查手册.md              # Linux + K8s 100+ 条常用命令
│   └── K8s_GPU调度与部署指南.md                   # GPU Operator / 调度 / MIG / DRA
├── manifests/                                   # 示例 YAML
│   ├── basic/                                   # 基础资源
│   │   ├── deployment.yaml                      # Deployment 示例
│   │   ├── service.yaml                         # Service 示例
│   │   └── configmap-secret.yaml                # ConfigMap & Secret 示例
│   └── advanced/                                # 高级配置
│       ├── hpa.yaml                             # HPA 自动扩缩示例
│       └── ingress.yaml                         # Ingress 示例
└── scripts/                                     # 实用脚本
    └── useful-commands.sh                       # 常用运维命令脚本
```

---

## 📖 运维文档

| 文档 | 内容 |
|------|------|
| [Linux & K8s 运维命令速查手册](docs/Linux_K8s_运维命令速查手册.md) | 系统信息、文件管理、进程管理、网络诊断、磁盘存储、用户权限、systemd、日志排查、集群管理、Pod 操作、Deployment、Service、故障排查、资源管理、配置管理 + 速查表 |
| [K8s GPU 调度与部署指南](docs/K8s_GPU调度与部署指南.md) | GPU 调度原理、GPU Operator 部署、资源请求规则、Time-Slicing 共享、MIG 分区、DRA 动态分配、DCGM 监控、故障排查、生产最佳实践 |

---

## 📚 学习资源

### 官方文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Kubernetes 中文文档](https://kubernetes.io/zh-cn/docs/)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- [kubectl 命令参考](https://kubernetes.io/docs/reference/kubectl/)

### 认证

| 认证 | 说明 | 链接 |
|------|------|------|
| **CKA** | Kubernetes 管理员 · 2 小时实操 | [官方页面](https://www.cncf.io/certification/cka/) |
| **CKAD** | 应用开发者视角 | [官方页面](https://www.cncf.io/certification/ckad/) |
| **CKS** | 安全专项 | [官方页面](https://www.cncf.io/certification/cks/) |

### 本地集群工具

| 工具 | 说明 | 链接 |
|------|------|------|
| minikube | 单节点本地集群 | https://minikube.sigs.k8s.io/ |
| kind | Docker 容器中的 K8s | https://kind.sigs.k8s.io/ |
| k3d | k3s 的 Docker 封装 | https://k3d.io/ |
| k3s | 轻量级 K8s 发行版 | https://k3s.io/ |

### 常用 CLI 工具

| 工具 | 说明 | 链接 |
|------|------|------|
| kubectx/kubens | 快速切换 context/namespace | https://github.com/ahmetb/kubectx |
| k9s | 终端 UI 管理工具 | https://k9scli.io/ |
| stern | 多 Pod 日志聚合 | https://github.com/stern/stern |
| lens | K8s 桌面 IDE | https://k8slens.dev/ |
| Helm | 包管理工具 | https://helm.sh/ |

### 推荐书籍

**入门**：《Kubernetes in Action》(Manning) · 《Kubernetes 权威指南》(龚正等) · 《Kubernetes 即学即用》(O'Reilly)

**进阶**：《Programming Kubernetes》(O'Reilly) · 《Kubernetes Patterns》 · 《Production Kubernetes》(O'Reilly)

### 视频课程

- [KodeKloud - Kubernetes for Beginners](https://www.youtube.com/playlist?list=PL2We04F3Y_41jYdadX55fdJplDvgNGENo)（免费）
- [TechWorld with Nana](https://www.youtube.com/c/TechWorldwithNana)（免费）
- [Udemy - CKA/CKAD by Mumshad](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/)（付费）
- [Linux Foundation Training](https://training.linuxfoundation.org/)（付费）

### 练习环境

- [Killercoda](https://killercoda.com/kubernetes) — 在线实验环境
- [Play with Kubernetes](https://labs.play-with-k8s.com/) — 免费 4 小时环境

---

## 🌐 CNCF 生态

### 核心项目

| 项目 | 类型 | 链接 |
|------|------|------|
| etcd | 分布式 KV 存储 | https://etcd.io/ |
| CoreDNS | DNS 服务 | https://coredns.io/ |
| containerd | 容器运行时 | https://containerd.io/ |
| Prometheus | 监控 | https://prometheus.io/ |
| Envoy | 服务代理 | https://www.envoyproxy.io/ |

### Service Mesh

Istio (https://istio.io/) · Linkerd (https://linkerd.io/) · Cilium (https://cilium.io/)

### GitOps

ArgoCD (https://argo-cd.readthedocs.io/) · Flux (https://fluxcd.io/)

---

## 💡 学习路径

### 入门（1-2 周）

1. 理解容器和 Docker 基础
2. 学习核心概念（Pod、Deployment、Service）
3. 用 minikube 搭建本地环境
4. 完成官方交互式教程

### 进阶（1-2 月）

1. StatefulSet、DaemonSet、Job/CronJob
2. 存储：PV/PVC、StorageClass
3. 网络：Ingress、NetworkPolicy
4. 安全：RBAC、Pod Security
5. 监控：Prometheus + Grafana

### 高级（持续）

1. Operator 开发、CRD 和 Controller
2. GPU 资源调度与管理
3. 集群运维和故障排查
4. 多集群管理
5. 云原生架构设计

---

## 🔗 关联仓库

| 仓库 | 内容 |
|------|------|
| [nvidia](https://github.com/mengxidong-manager/nvidia) | NVIDIA GPU 技术文档（Vera Rubin / B300 / nvidia-smi / AIDC 运维 / RAID / VPN） |

---

*持续更新中*
