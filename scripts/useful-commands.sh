#!/bin/bash
# Kubernetes 常用命令速查

# ===== 基础操作 =====
# 查看集群信息
kubectl cluster-info
kubectl get nodes

# 查看所有资源
kubectl get all -A
kubectl get pods -A -o wide

# ===== Pod 调试 =====
# 进入Pod
kubectl exec -it <pod-name> -- /bin/bash

# 查看日志
kubectl logs <pod-name> -f
kubectl logs <pod-name> --previous  # 崩溃前的日志

# 端口转发
kubectl port-forward <pod-name> 8080:80

# ===== 资源管理 =====
# 查看资源使用
kubectl top nodes
kubectl top pods

# 扩缩容
kubectl scale deployment <name> --replicas=5

# 滚动更新
kubectl set image deployment/<name> <container>=<image>:<tag>
kubectl rollout status deployment/<name>
kubectl rollout undo deployment/<name>

# ===== 调试技巧 =====
# 运行临时调试Pod
kubectl run debug --image=busybox -it --rm -- /bin/sh
kubectl run debug --image=nicolaka/netshoot -it --rm -- /bin/bash

# 查看事件
kubectl get events --sort-by=.lastTimestamp

# 描述资源
kubectl describe pod <pod-name>

# ===== 导出YAML =====
kubectl get deployment <name> -o yaml > deployment.yaml

# 干跑测试
kubectl apply -f manifest.yaml --dry-run=client
