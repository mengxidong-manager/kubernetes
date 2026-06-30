# Kubernetes 学习与运维资料

> Kubernetes 学习资源、运维文档、示例 YAML、实用脚本
>
> 维护人：孟希東 · 最后更新: 2026-06-30

---

## 运维文档

| 文档 | 内容 |
|------|------|
| [K8s 1.34 生产环境 HA 集群部署指南](docs/K8s_1.34_生产环境HA集群部署指南.md) | **3Master + 3etcd + 2LB** · 外部 etcd TLS · HAProxy+Keepalived · 11 节点完整部署 |
| [K8s 1.34 集群部署指南（测试环境）](docs/K8s_1.34_集群部署指南.md) | 单 Master · kubeadm + containerd + Calico + Helm · GPU 就绪 |
| [Prometheus + Grafana 监控部署指南](docs/Prometheus_Grafana_监控部署指南.md) | kube-prometheus-stack · 外部 etcd/HAProxy 监控 · GPU DCGM · 告警规则 · 9 层全栈覆盖 |
| [K8s GPU 调度与部署指南](docs/K8s_GPU调度与部署指南.md) | GPU Operator · 调度规则 · Time-Slicing · MIG · DRA · DCGM 监控 |
| [Linux & K8s 运维命令速查手册](docs/Linux_K8s_运维命令速查手册.md) | Linux 系统管理 + K8s 集群运维 100+ 命令 · 双份速查表 |

## 仓库结构

```
├── docs/
│   ├── K8s_1.34_生产环境HA集群部署指南.md    # 生产 HA 集群（11 节点）
│   ├── K8s_1.34_集群部署指南.md              # 测试集群（单 Master）
│   ├── Prometheus_Grafana_监控部署指南.md     # 全栈监控
│   ├── K8s_GPU调度与部署指南.md              # GPU 调度
│   └── Linux_K8s_运维命令速查手册.md          # 命令速查
├── manifests/basic/                          # Deployment / Service / ConfigMap
├── manifests/advanced/                       # HPA / Ingress
└── scripts/useful-commands.sh                # 运维脚本
```

## 学习资源

[官方文档](https://kubernetes.io/docs/) · [中文文档](https://kubernetes.io/zh-cn/docs/) · [CKA](https://www.cncf.io/certification/cka/) · [CKAD](https://www.cncf.io/certification/ckad/) · [CKS](https://www.cncf.io/certification/cks/)

工具：minikube · kind · k3s · k9s · stern · Helm · kubectx

书籍：《Kubernetes in Action》 · 《Kubernetes权威指南》 · 《Programming Kubernetes》

CNCF：etcd · CoreDNS · Prometheus · Istio · ArgoCD · Cilium

关联仓库：[nvidia](https://github.com/mengxidong-manager/nvidia)
