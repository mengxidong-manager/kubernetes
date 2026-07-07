# Kubernetes 学习与运维资料

> Kubernetes 学习资源、运维文档、示例 YAML、实用脚本
>
> 维护人：孟希東 · 最后更新: 2026-07-07

---

## 运维文档

| 文档 | 内容 |
|------|------|
| [K8s 1.34 生产环境 HA 集群部署指南](docs/K8s_1.34_生产环境HA集群部署指南.md) | 3Master + 3etcd + 2LB · 外部 etcd TLS · HAProxy+Keepalived · 11 节点 |
| [K8s 1.34 集群部署指南（测试环境）](docs/K8s_1.34_集群部署指南.md) | 单 Master · kubeadm + containerd + Calico + Helm · GPU 就绪 |
| [K8s GPU 训练与推理全栈架构指南](docs/K8s_GPU训练与推理全栈架构指南.md) | 物理部署 · GPU 调用链 · 训练/推理工作流 · AI 平台栈 · 存储/网络/多租户 |
| [K8s GPU 调度与部署指南](docs/K8s_GPU调度与部署指南.md) | GPU Operator · 调度规则 · Time-Slicing · MIG · DRA |
| [Prometheus + Grafana 监控部署指南](docs/Prometheus_Grafana_监控部署指南.md) | kube-prometheus-stack · 外部 etcd/HAProxy · GPU DCGM · 告警 · 9 层全栈 |
| [K8s 常见问题与故障排查手册](docs/K8s_常见问题与故障排查手册.md) | Pod 异常 · 节点故障 · 网络不通 · 存储 · 控制平面 · RBAC · 性能 |
| [etcd 常见问题与故障排查手册](docs/etcd_常见问题与故障排查手册.md) | **空间超限 · 碎片整理 · 磁盘性能 · Leader 选举 · 成员管理 · 备份恢复 · 证书** |
| [Linux & K8s 运维命令速查手册](docs/Linux_K8s_运维命令速查手册.md) | Linux 系统管理 + K8s 集群运维 100+ 命令 · 双份速查表 |

## 文档体系

```
部署        → HA 集群部署指南 / 测试集群部署指南
GPU         → GPU 调度指南 → GPU 训练与推理全栈架构指南
监控        → Prometheus + Grafana 监控部署指南
故障排查     → K8s 故障排查手册 + etcd 故障排查手册
日常运维     → Linux & K8s 运维命令速查手册
```

## 仓库结构

```
├── docs/                                         # 运维文档（8 篇）
│   ├── K8s_1.34_生产环境HA集群部署指南.md
│   ├── K8s_1.34_集群部署指南.md
│   ├── K8s_GPU训练与推理全栈架构指南.md
│   ├── K8s_GPU调度与部署指南.md
│   ├── Prometheus_Grafana_监控部署指南.md
│   ├── K8s_常见问题与故障排查手册.md
│   ├── etcd_常见问题与故障排查手册.md                ← NEW
│   └── Linux_K8s_运维命令速查手册.md
├── manifests/basic/
├── manifests/advanced/
└── scripts/useful-commands.sh
```

## 学习资源

[官方文档](https://kubernetes.io/docs/) · [中文文档](https://kubernetes.io/zh-cn/docs/) · [CKA](https://www.cncf.io/certification/cka/) · [CKAD](https://www.cncf.io/certification/ckad/) · [CKS](https://www.cncf.io/certification/cks/)

工具：minikube · kind · k3s · k9s · stern · Helm · kubectx

CNCF：etcd · CoreDNS · Prometheus · Istio · ArgoCD · Cilium

关联仓库：[nvidia](https://github.com/mengxidong-manager/nvidia) · [network](https://github.com/mengxidong-manager/network)
