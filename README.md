# Kubernetes 学习与运维资料

> Kubernetes 学习资源、运维文档、示例 YAML、实用脚本
>
> 维护人：孟希東 · 最后更新: 2026-06-30

---

## 运维文档

| 文档 | 内容 |
|------|------|
| [Linux & K8s 运维命令速查手册](docs/Linux_K8s_运维命令速查手册.md) | Linux 系统管理 + K8s 集群运维 100+ 命令 |
| [K8s GPU 调度与部署指南](docs/K8s_GPU调度与部署指南.md) | GPU Operator / 调度规则 / MIG / Time-Slicing / DRA / DCGM 监控 |

## 仓库结构

```
├── docs/                    # 运维文档
├── manifests/basic/         # Deployment / Service / ConfigMap
├── manifests/advanced/      # HPA / Ingress
└── scripts/                 # 实用脚本
```

## 学习资源

[官方文档](https://kubernetes.io/docs/) · [中文文档](https://kubernetes.io/zh-cn/docs/) · [CKA](https://www.cncf.io/certification/cka/) · [CKAD](https://www.cncf.io/certification/ckad/) · [CKS](https://www.cncf.io/certification/cks/)

工具：minikube · kind · k3s · k9s · stern · Helm · kubectx

书籍：《Kubernetes in Action》 · 《Kubernetes权威指南》 · 《Programming Kubernetes》

CNCF：etcd · CoreDNS · Prometheus · Istio · ArgoCD · Cilium

关联仓库：[nvidia](https://github.com/mengxidong-manager/nvidia)
