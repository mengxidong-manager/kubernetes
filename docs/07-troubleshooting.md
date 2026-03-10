# Kubernetes 故障排查指南

## 1. Pod 问题排查

### 1.1 Pod 状态说明

```
Pending     - 等待调度或拉取镜像
Running     - 运行中
Succeeded   - 成功完成（Job）
Failed      - 失败
Unknown     - 无法获取状态
CrashLoopBackOff - 容器反复崩溃
ImagePullBackOff - 镜像拉取失败
ErrImagePull     - 镜像拉取错误
```

### 1.2 Pending 状态排查

```bash
# 查看详情
kubectl describe pod <pod-name>

# 常见原因：
# 1. 资源不足
kubectl describe nodes | grep -A 5 "Allocated resources"

# 2. 节点选择器/亲和性不匹配
kubectl get nodes --show-labels

# 3. PVC 未绑定
kubectl get pvc

# 4. 污点/容忍度问题
kubectl describe nodes | grep Taints
```

### 1.3 CrashLoopBackOff 排查

```bash
# 查看日志
kubectl logs <pod-name> --previous
kubectl logs <pod-name> -c <container> --previous

# 查看事件
kubectl describe pod <pod-name>

# 进入容器调试（如果能启动）
kubectl exec -it <pod-name> -- /bin/sh

# 运行调试容器
kubectl debug <pod-name> -it --image=busybox --target=<container>

# 常见原因：
# 1. 应用配置错误
# 2. 健康检查失败
# 3. 依赖服务不可用
# 4. 资源限制过低
```

### 1.4 ImagePullBackOff 排查

```bash
# 检查镜像名和标签
kubectl describe pod <pod-name> | grep Image

# 检查 imagePullSecrets
kubectl get pod <pod-name> -o jsonpath='{.spec.imagePullSecrets}'

# 手动测试拉取
docker pull <image>

# 检查 Secret
kubectl get secret regcred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

---

## 2. 网络问题排查

### 2.1 Service 连接问题

```bash
# 检查 Service
kubectl get svc <service-name>
kubectl describe svc <service-name>

# 检查 Endpoints
kubectl get endpoints <service-name>

# 如果 Endpoints 为空：
# 1. 检查 selector 是否匹配
kubectl get pods -l <selector>
# 2. 检查 Pod 是否 Ready
kubectl get pods -l <selector> -o wide
```

### 2.2 DNS 问题

```bash
# 在集群内测试 DNS
kubectl run dns-test --image=busybox:1.36 --rm -it -- nslookup kubernetes
kubectl run dns-test --image=busybox:1.36 --rm -it -- nslookup <service-name>

# 检查 CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# 检查 DNS 配置
kubectl get configmap coredns -n kube-system -o yaml
```

### 2.3 网络连通性测试

```bash
# 部署网络调试工具
kubectl run netshoot --image=nicolaka/netshoot -it --rm -- bash

# 在容器内测试
ping <pod-ip>
curl <service-name>:<port>
nc -zv <host> <port>
traceroute <host>

# 检查 NetworkPolicy
kubectl get networkpolicy -A
```

---

## 3. 存储问题排查

### 3.1 PVC Pending

```bash
# 查看 PVC 状态
kubectl describe pvc <pvc-name>

# 常见原因：
# 1. 没有可用的 PV
kubectl get pv

# 2. StorageClass 不存在
kubectl get sc

# 3. 容量不匹配
# 4. accessModes 不匹配
```

### 3.2 挂载问题

```bash
# 查看 Pod 事件
kubectl describe pod <pod-name>

# 检查节点上的挂载
kubectl debug node/<node-name> -it --image=busybox -- mount | grep <pv>

# 常见错误：
# - "mount: wrong fs type" - 文件系统类型不匹配
# - "permission denied" - 权限问题
# - "stale NFS handle" - NFS 问题
```

---

## 4. 节点问题排查

### 4.1 节点 NotReady

```bash
# 查看节点状态
kubectl describe node <node-name>

# 检查节点条件
kubectl get nodes -o wide
kubectl get node <node-name> -o jsonpath='{.status.conditions[*].type}'

# SSH 到节点检查
# 1. kubelet 状态
systemctl status kubelet
journalctl -u kubelet -f

# 2. 容器运行时
systemctl status containerd
crictl ps
crictl pods

# 3. 系统资源
df -h
free -m
top
```

### 4.2 节点资源压力

```bash
# 内存压力
kubectl describe node <node> | grep -A 5 Conditions

# 磁盘压力
df -h /var/lib/kubelet
df -h /var/lib/containerd

# 清理未使用的镜像
crictl rmi --prune

# 驱逐 Pod
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

---

## 5. 控制平面问题

### 5.1 API Server

```bash
# 健康检查
kubectl get --raw /healthz
kubectl get --raw /livez
kubectl get --raw /readyz

# 查看日志（kubeadm 集群）
kubectl logs -n kube-system kube-apiserver-<master-node>
```

### 5.2 etcd

```bash
# 检查 etcd 健康
kubectl exec -n kube-system etcd-<master> -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# 查看成员
etcdctl member list
```

### 5.3 Controller Manager / Scheduler

```bash
# 查看日志
kubectl logs -n kube-system kube-controller-manager-<master>
kubectl logs -n kube-system kube-scheduler-<master>

# 检查 leader
kubectl get endpoints kube-controller-manager -n kube-system -o yaml
kubectl get endpoints kube-scheduler -n kube-system -o yaml
```

---

## 6. 常用调试命令

### 6.1 快速诊断脚本

```bash
#!/bin/bash
echo "=== 节点状态 ==="
kubectl get nodes -o wide

echo -e "\n=== 问题 Pod ==="
kubectl get pods -A | grep -v Running | grep -v Completed

echo -e "\n=== 最近事件 ==="
kubectl get events -A --sort-by=.lastTimestamp | tail -20

echo -e "\n=== 资源使用 ==="
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -10

echo -e "\n=== 系统 Pod ==="
kubectl get pods -n kube-system
```

### 6.2 调试 Pod

```yaml
# 创建调试 Pod
apiVersion: v1
kind: Pod
metadata:
  name: debug
spec:
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
    securityContext:
      privileged: true
  hostNetwork: true
  hostPID: true
```

### 6.3 临时容器调试

```bash
# 添加临时调试容器到运行中的 Pod
kubectl debug <pod-name> -it --image=busybox --target=<container>

# 共享进程命名空间
kubectl debug <pod-name> -it --image=busybox --share-processes

# 调试节点
kubectl debug node/<node-name> -it --image=busybox
```

---

## 7. 常见问题速查

| 问题 | 可能原因 | 排查命令 |
|------|----------|----------|
| Pod Pending | 资源不足/PVC问题 | `kubectl describe pod` |
| CrashLoopBackOff | 应用错误/配置错误 | `kubectl logs --previous` |
| ImagePullBackOff | 镜像不存在/认证问题 | `kubectl describe pod` |
| Service 无法访问 | Selector不匹配/Pod未Ready | `kubectl get endpoints` |
| DNS 解析失败 | CoreDNS 问题 | `kubectl logs -n kube-system -l k8s-app=kube-dns` |
| PVC Pending | 无可用PV/SC问题 | `kubectl describe pvc` |
| 节点 NotReady | kubelet/网络问题 | `systemctl status kubelet` |
| 高延迟 | 资源不足/网络问题 | `kubectl top`, 网络测试 |

---

## 8. 有用资源

```bash
# kubectl 自动补全
source <(kubectl completion bash)

# 别名
alias k=kubectl
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kex='kubectl exec -it'

# 快速切换 context/namespace
# 安装 kubectx/kubens
kubectx <context>
kubens <namespace>
```
