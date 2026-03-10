# Kubernetes 学习资料汇总

> 最后更新: 2026-03-10

## 📚 官方资源

### 文档
- [Kubernetes 官方文档](https://kubernetes.io/docs/) - 最权威的参考
- [Kubernetes 中文文档](https://kubernetes.io/zh-cn/docs/) - 官方中文版
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- [kubectl 命令参考](https://kubernetes.io/docs/reference/kubectl/)

### 官方教程
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/) - 交互式入门教程
- [Hello Minikube](https://kubernetes.io/docs/tutorials/hello-minikube/) - 5分钟快速开始
- [Learn Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)

## 🎓 认证

### CKA (Certified Kubernetes Administrator)
- [CKA 官方页面](https://www.cncf.io/certification/cka/)
- [CKA 考试大纲](https://github.com/cncf/curriculum)
- 考试时长: 2小时，实操题

### CKAD (Certified Kubernetes Application Developer)
- [CKAD 官方页面](https://www.cncf.io/certification/ckad/)
- 侧重应用开发者视角

### CKS (Certified Kubernetes Security Specialist)
- [CKS 官方页面](https://www.cncf.io/certification/cks/)
- 安全专项认证

## 🛠️ 实践工具

### 本地集群
| 工具 | 说明 | 链接 |
|------|------|------|
| **minikube** | 单节点本地集群 | https://minikube.sigs.k8s.io/ |
| **kind** | Docker容器中的K8s | https://kind.sigs.k8s.io/ |
| **k3d** | k3s的Docker封装 | https://k3d.io/ |
| **k3s** | 轻量级K8s发行版 | https://k3s.io/ |

### 常用CLI工具
| 工具 | 说明 | 链接 |
|------|------|------|
| **kubectx/kubens** | 快速切换context/namespace | https://github.com/ahmetb/kubectx |
| **k9s** | 终端UI管理工具 | https://k9scli.io/ |
| **stern** | 多Pod日志聚合 | https://github.com/stern/stern |
| **lens** | K8s桌面IDE | https://k8slens.dev/ |
| **kubectl-neat** | 清理YAML输出 | https://github.com/itaysk/kubectl-neat |

### Helm
- [Helm 官网](https://helm.sh/)
- [Artifact Hub](https://artifacthub.io/) - Helm Chart 仓库

## 📖 推荐书籍

### 入门
- 《Kubernetes in Action》 - Manning
- 《Kubernetes权威指南》 - 龚正等著
- 《Kubernetes即学即用》 - O'Reilly

### 进阶
- 《Programming Kubernetes》 - O'Reilly
- 《Kubernetes Patterns》 - 设计模式
- 《Production Kubernetes》 - O'Reilly

## 🎬 视频课程

### 免费
- [KodeKloud - Kubernetes for Beginners](https://www.youtube.com/playlist?list=PL2We04F3Y_41jYdadX55fdJplDvgNGENo)
- [TechWorld with Nana](https://www.youtube.com/c/TechWorldwithNana) - K8s系列
- [CNCF YouTube](https://www.youtube.com/c/cloudnativefdn) - KubeCon演讲

### 付费
- [Udemy - CKA/CKAD by Mumshad](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/)
- [A Cloud Guru](https://acloudguru.com/)
- [Linux Foundation Training](https://training.linuxfoundation.org/)

## 🔧 实战项目

### 练习环境
- [Killercoda](https://killercoda.com/kubernetes) - 在线实验环境
- [Play with Kubernetes](https://labs.play-with-k8s.com/) - 免费4小时环境
- [Katacoda (已停)](https://www.katacoda.com/) - 被O'Reilly收购

### 练手项目
1. 部署一个多层应用 (Frontend + Backend + DB)
2. 配置 Ingress 和 TLS
3. 实现 HPA 自动扩缩
4. 配置 RBAC 权限控制
5. 部署 Prometheus + Grafana 监控

## 🌐 CNCF 生态

### 核心项目
| 项目 | 类型 | 链接 |
|------|------|------|
| **etcd** | 分布式KV存储 | https://etcd.io/ |
| **CoreDNS** | DNS服务 | https://coredns.io/ |
| **containerd** | 容器运行时 | https://containerd.io/ |
| **Prometheus** | 监控 | https://prometheus.io/ |
| **Envoy** | 服务代理 | https://www.envoyproxy.io/ |

### Service Mesh
- **Istio** - https://istio.io/
- **Linkerd** - https://linkerd.io/
- **Cilium** - https://cilium.io/

### GitOps
- **ArgoCD** - https://argo-cd.readthedocs.io/
- **Flux** - https://fluxcd.io/

## 📝 Kubernetes 1.29+ 新特性

### 1.29 (2023.12)
- Sidecar Containers (Beta)
- ReadWriteOncePod PV 稳定
- KMS v2 稳定

### 1.30 (2024.04)
- Pod Scheduling Readiness 稳定
- Min Domains in PodTopologySpread

### 1.31+ (2024-2025)
- Sidecar Containers GA
- 更多 Gateway API 特性
- 增强的 Pod 安全标准

## 💡 学习路径建议

### 入门 (1-2周)
1. 理解容器和Docker基础
2. 学习K8s核心概念 (Pod, Deployment, Service)
3. 用minikube搭建本地环境
4. 完成官方交互式教程

### 进阶 (1-2月)
1. 深入 StatefulSet, DaemonSet, Job
2. 存储: PV/PVC, StorageClass
3. 网络: Ingress, NetworkPolicy
4. 安全: RBAC, Pod Security
5. 监控: Prometheus + Grafana

### 高级 (持续)
1. Operator 开发
2. CRD 和 Controller
3. 集群运维和故障排查
4. 多集群管理
5. 云原生架构设计

## 🔗 社区资源

- [Kubernetes Slack](https://slack.k8s.io/) - 官方Slack
- [CNCF Slack](https://slack.cncf.io/)
- [r/kubernetes](https://www.reddit.com/r/kubernetes/) - Reddit
- [Kubernetes 中文社区](https://www.kubernetes.org.cn/)

---

## 📁 本仓库内容

```
├── README.md              # 本文件
├── manifests/             # 示例YAML文件
│   ├── basic/            # 基础资源示例
│   ├── advanced/         # 高级配置示例
│   └── production/       # 生产环境参考
├── scripts/              # 实用脚本
├── notes/                # 学习笔记
└── labs/                 # 实验练习
```

---

*持续更新中，欢迎贡献！*
