# Kubernetes 常见问题与故障排查手册

> 覆盖 Pod 异常、节点故障、网络不通、存储问题、控制平面故障、安全权限、性能问题等全场景排查与解决方案
>
> 撰写人：孟希東

---

## 快速排查流程

```
问题发生
  ├── Pod 层面 → kubectl get pods / describe / logs
  ├── 节点层面 → kubectl get nodes / describe node / systemctl status kubelet
  ├── 网络层面 → kubectl get svc/ep/ingress / DNS 测试 / 端口转发
  ├── 存储层面 → kubectl get pv/pvc / describe pvc
  ├── 控制平面 → kubectl get cs / API Server 日志 / etcd 健康
  └── 安全层面 → kubectl auth can-i / RBAC 检查
```

---

## 1. Pod 异常状态

### 1.1 CrashLoopBackOff（反复崩溃重启）

Pod 启动后立即崩溃，K8s 不断重启，间隔越来越长（10s→20s→40s→...→5min）。

**排查步骤：**

```bash
# 1. 查看 Pod 状态和重启次数
kubectl get pods

# 2. 查看上一次崩溃的日志（最关键）
kubectl logs <pod> --previous

# 3. 查看 Pod 事件
kubectl describe pod <pod> | tail -20

# 4. 查看容器退出码
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
```

**常见原因与解决：**

| 退出码 | 原因 | 解决 |
|--------|------|------|
| 1 | 应用代码错误 | 查 logs --previous，修复代码 |
| 137 | OOMKilled（内存超限被杀） | 增加 memory limits，或优化应用内存 |
| 139 | Segfault（段错误） | 应用 bug，检查代码或基础镜像 |
| 143 | SIGTERM（被优雅终止） | 正常终止，检查 preStop hook |
| 0 | 正常退出但 restartPolicy=Always | 容器不应退出，检查启动命令 |

```bash
# OOMKilled 确认
kubectl describe pod <pod> | grep -i oom
# 看到 Reason: OOMKilled → 增加 memory limits

# 启动命令错误（容器秒退）
kubectl get pod <pod> -o jsonpath='{.spec.containers[0].command}'
# 检查 command 和 args 是否正确
```

### 1.2 ImagePullBackOff（拉镜像失败）

```bash
kubectl describe pod <pod> | grep -A5 Events
# Failed to pull image "xxx": rpc error
```

| 原因 | 解决 |
|------|------|
| 镜像名或 tag 拼写错误 | 检查 image 字段 |
| 私有仓库未配置认证 | 创建 imagePullSecret 并在 Pod 中引用 |
| 仓库不可达 | 节点上 `curl` 测试仓库连通性 |
| 镜像不存在 | 确认镜像已推送到仓库 |

```bash
# 创建私有仓库 Secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass

# Pod 中引用
spec:
  imagePullSecrets:
  - name: regcred
```

### 1.3 Pending（无法调度）

Pod 被 API Server 接受但无法分配到节点。

```bash
kubectl describe pod <pod> | grep -A10 Events
```

| 事件信息 | 原因 | 解决 |
|----------|------|------|
| Insufficient cpu/memory | 集群资源不足 | 扩容节点或释放资源 |
| Insufficient nvidia.com/gpu | GPU 不足 | 等待 GPU 释放或扩容 |
| node(s) had taint | 节点有污点，Pod 无容忍 | 添加 tolerations 或移除 taint |
| node(s) didn't match selector | nodeSelector 不匹配 | 检查节点标签 |
| no persistentvolumeclaim | PVC 未绑定 | 检查 PVC 状态和 StorageClass |
| pod topology spread constraints | 拓扑约束无法满足 | 放宽 maxSkew 或添加节点 |

```bash
# 查看集群资源使用情况
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"

# 查看节点污点
kubectl describe node <node> | grep Taints
```

### 1.4 CreateContainerConfigError

```bash
kubectl describe pod <pod>
# Error: configmap "xxx" not found
# Error: secret "xxx" not found
```

| 原因 | 解决 |
|------|------|
| 引用的 ConfigMap 不存在 | `kubectl get cm -n <ns>` 确认 |
| 引用的 Secret 不存在 | `kubectl get secret -n <ns>` 确认 |
| ConfigMap/Secret 中缺少指定的 key | `kubectl describe cm <name>` 检查 key |
| 不同命名空间 | ConfigMap/Secret 必须和 Pod 在同一 namespace |

### 1.5 OOMKilled（内存溢出被杀）

```bash
kubectl describe pod <pod> | grep -i "oom\|memory"
# Reason: OOMKilled
# Last State: Terminated with exit code 137
```

**解决方案：**
- 增加 `resources.limits.memory`
- 检查应用是否有内存泄漏
- Java 应用设置 `-Xmx` 与 container limits 匹配
- 启用 Vertical Pod Autoscaler（VPA）自动调整

### 1.6 Terminating 卡住（删不掉）

```bash
# Pod 一直处于 Terminating 状态
kubectl get pods
# NAME    STATUS        AGE
# my-pod  Terminating   30m

# 原因 1：Finalizer 阻塞
kubectl get pod <pod> -o jsonpath='{.metadata.finalizers}'
# 清除 finalizer
kubectl patch pod <pod> -p '{"metadata":{"finalizers":null}}'

# 原因 2：进程不响应 SIGTERM
# 强制删除
kubectl delete pod <pod> --force --grace-period=0

# 原因 3：节点不可达
# Pod 在 NotReady 节点上，kubelet 无法执行删除
# 等节点恢复，或强制删除
```

---

## 2. 节点问题

### 2.1 Node NotReady

```bash
kubectl get nodes
# NAME       STATUS     ROLES
# worker-01  NotReady   worker

# 排查步骤
kubectl describe node worker-01 | grep -A10 Conditions
```

| Condition | 原因 | 解决 |
|-----------|------|------|
| Ready=False | kubelet 停止上报状态 | SSH 到节点：`systemctl status kubelet` |
| MemoryPressure=True | 内存不足 | 清理内存，驱逐 Pod |
| DiskPressure=True | 磁盘不足 | 清理磁盘：`crictl rmi --prune`，清理日志 |
| PIDPressure=True | 进程数过多 | 检查是否有进程泄漏 |
| NetworkUnavailable=True | CNI 插件异常 | 检查 Calico/Flannel Pod 状态 |

```bash
# SSH 到 NotReady 节点
systemctl status kubelet
journalctl -u kubelet --since "10 min ago" | tail -50
systemctl status containerd

# 常见修复
sudo systemctl restart kubelet
# 如果 containerd 也异常
sudo systemctl restart containerd && sudo systemctl restart kubelet
```

### 2.2 节点资源耗尽

```bash
# 节点 CPU/内存使用情况
kubectl top nodes

# 找出资源消耗最大的 Pod
kubectl top pods -A --sort-by=cpu | head -10
kubectl top pods -A --sort-by=memory | head -10

# 驱逐节点上的 Pod（维护前）
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

### 2.3 kubelet 频繁重启

```bash
journalctl -u kubelet -f
# 常见原因：
# - swap 未关闭
# - containerd 异常
# - 证书过期
# - 配置文件错误

# 检查 swap
free -h  # Swap 不为 0 → swapoff -a

# 检查证书
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates
```

---

## 3. 网络问题

### 3.1 Service 无法访问

```bash
# 1. 确认 Service 和 Endpoints
kubectl get svc <name>
kubectl get endpoints <name>
# Endpoints 为空 → Service selector 与 Pod labels 不匹配

# 2. 确认 Pod 标签匹配
kubectl get pods -l <selector-key>=<selector-value>

# 3. 确认 Pod 内端口正确
kubectl exec -it <pod> -- curl localhost:<targetPort>

# 4. 集群内测试 Service
kubectl run tmp --rm -it --image=curlimages/curl -- curl http://<svc>.<ns>.svc.cluster.local:<port>
```

| 问题 | 原因 | 解决 |
|------|------|------|
| Endpoints 为空 | Selector 不匹配 | 对比 svc selector 和 pod labels |
| ClusterIP 不通 | kube-proxy 异常 | `kubectl get pods -n kube-system -l k8s-app=kube-proxy` |
| NodePort 不通 | 防火墙阻断 | 开放 30000-32767 端口范围 |
| ExternalIP 不通 | 云环境需用 LoadBalancer | 改用 type: LoadBalancer |

### 3.2 DNS 解析失败

```bash
# 测试集群 DNS
kubectl run dns-test --rm -it --image=busybox -- nslookup kubernetes.default
# 失败 → CoreDNS 有问题

# 检查 CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# 检查 Pod 内 DNS 配置
kubectl exec -it <pod> -- cat /etc/resolv.conf
# nameserver 应为 10.96.0.10（kube-dns ClusterIP）
```

### 3.3 Pod 间网络不通

```bash
# 1. 同节点 Pod 互 ping
kubectl exec -it <pod-A> -- ping <pod-B-IP>

# 2. 跨节点 Pod 互 ping
# 不通 → CNI 插件问题

# 3. 检查 CNI 插件
kubectl get pods -n calico-system      # Calico
kubectl get pods -n kube-flannel       # Flannel

# 4. 检查 NetworkPolicy 是否阻断
kubectl get networkpolicy -A
```

### 3.4 Ingress 不生效

```bash
# 检查 Ingress Controller 是否运行
kubectl get pods -n ingress-nginx

# 检查 Ingress 规则
kubectl describe ingress <name>

# 检查 Ingress class
kubectl get ingressclass

# 常见问题：
# - 未指定 ingressClassName
# - 后端 Service 不存在
# - TLS Secret 不存在
```

---

## 4. 存储问题

### 4.1 PVC 一直 Pending

```bash
kubectl get pvc
kubectl describe pvc <name>
```

| 事件 | 原因 | 解决 |
|------|------|------|
| no persistent volumes available | 没有匹配的 PV | 创建 PV 或配置动态 provisioner |
| storageclass "xxx" not found | StorageClass 不存在 | `kubectl get sc` 检查可用 StorageClass |
| waiting for first consumer | WaitForFirstConsumer 模式 | 正常，Pod 调度后自动绑定 |
| provision failed | Provisioner 异常 | 检查 CSI 驱动 Pod 状态 |

### 4.2 挂载失败

```bash
kubectl describe pod <pod>
# Warning  FailedMount  Unable to attach or mount volumes

# NFS 挂载失败 → 节点上安装 nfs-common
sudo apt-get install -y nfs-common

# 权限问题 → 检查 securityContext
spec:
  securityContext:
    fsGroup: 1000
```

---

## 5. 控制平面故障

### 5.1 API Server 不可用

```bash
# kubectl 无法连接
kubectl get nodes
# The connection to the server was refused

# 排查
ssh <master-node>
sudo crictl ps | grep kube-apiserver
sudo crictl logs <api-server-container-id> | tail -50

# 常见原因：
# - etcd 不可用
# - 证书过期
# - 内存不足（API Server OOM）
```

### 5.2 etcd 故障

```bash
# 检查 etcd 健康
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://10.0.0.11:2379,https://10.0.0.12:2379,https://10.0.0.13:2379 \
  --cacert=/etc/etcd/ssl/ca.pem \
  --cert=/etc/etcd/ssl/etcd.pem \
  --key=/etc/etcd/ssl/etcd-key.pem

# etcd 磁盘空间满
ETCDCTL_API=3 etcdctl alarm list ...
# 压缩和碎片整理
ETCDCTL_API=3 etcdctl compact <revision> ...
ETCDCTL_API=3 etcdctl defrag ...
ETCDCTL_API=3 etcdctl alarm disarm ...
```

### 5.3 证书过期

```bash
# 检查证书到期时间
kubeadm certs check-expiration

# 续期所有证书
sudo kubeadm certs renew all
# 重启控制平面组件
sudo crictl ps | grep kube | awk '{print $1}' | xargs sudo crictl stop
```

### 5.4 Scheduler / Controller Manager 异常

```bash
kubectl get pods -n kube-system | grep -E "scheduler|controller"
kubectl logs -n kube-system kube-scheduler-<master>
kubectl logs -n kube-system kube-controller-manager-<master>
```

---

## 6. 安全与权限问题

### 6.1 RBAC Forbidden

```bash
kubectl get pods
# Error: forbidden: User "xxx" cannot list pods in namespace "default"

# 检查权限
kubectl auth can-i list pods --as=<user> -n <namespace>
kubectl auth can-i '*' '*' --as=<user>  # 是否有全部权限

# 创建 RoleBinding
kubectl create rolebinding dev-view \
  --clusterrole=view \
  --user=dev-user \
  -n default
```

### 6.2 ServiceAccount 权限不足

```bash
# Pod 内调用 API 报 403
# 检查 Pod 使用的 ServiceAccount
kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'

# 给 ServiceAccount 绑定角色
kubectl create rolebinding sa-binding \
  --clusterrole=edit \
  --serviceaccount=<ns>:<sa-name> \
  -n <ns>
```

### 6.3 Pod Security 违规

```bash
kubectl describe pod <pod>
# Warning: would violate PodSecurity "restricted"

# 检查命名空间 PSA 标签
kubectl get ns <ns> --show-labels | grep pod-security

# 修改 Pod spec 满足 restricted 要求：
# - runAsNonRoot: true
# - allowPrivilegeEscalation: false
# - capabilities: drop: ["ALL"]
```

---

## 7. 性能问题

### 7.1 Pod 响应慢

```bash
# 检查 Pod 资源使用
kubectl top pod <pod>
# CPU 接近 limits → CPU 节流（throttling）
# 解决：增加 CPU limits 或 requests

# 检查节点负载
kubectl top nodes
# 节点过载 → 扩容或迁移 Pod
```

### 7.2 HPA 不生效

```bash
kubectl get hpa
# TARGETS: <unknown>/80% → metrics-server 未安装或异常

kubectl get pods -n kube-system | grep metrics-server
# 未安装 → helm install metrics-server

kubectl top pods  # 确认 metrics 可用
```

### 7.3 探针失败导致重启

```bash
kubectl describe pod <pod> | grep -A5 "Liveness\|Readiness"
# Liveness probe failed → 容器被杀重启
# Readiness probe failed → 从 Service 移除（不重启）

# 常见修复：
# - 增加 initialDelaySeconds（应用启动慢）
# - 增加 timeoutSeconds
# - 检查探针 path/port 是否正确
# - 检查应用健康检查端点是否正常
```

---

## 8. 部署与更新问题

### 8.1 滚动更新卡住

```bash
kubectl rollout status deploy/<name>
# Waiting for deployment "xxx" rollout to finish: 1 old replicas are pending termination

# 原因：新 Pod 未通过 readiness probe
kubectl get pods | grep <deploy-name>
kubectl describe pod <new-pod>  # 查看为什么新 Pod 不 Ready

# 回滚
kubectl rollout undo deploy/<name>
```

### 8.2 回滚操作

```bash
# 查看历史版本
kubectl rollout history deploy/<name>

# 回滚到上一版本
kubectl rollout undo deploy/<name>

# 回滚到指定版本
kubectl rollout undo deploy/<name> --to-revision=3
```

---

## 排查命令速查表

| 场景 | 命令 |
|------|------|
| Pod 状态总览 | `kubectl get pods -A -o wide` |
| Pod 崩溃日志 | `kubectl logs <pod> --previous` |
| Pod 详情和事件 | `kubectl describe pod <pod>` |
| 节点状态 | `kubectl get nodes -o wide` |
| 节点资源 | `kubectl top nodes` |
| 非 Running Pod | `kubectl get pods -A \| grep -v Running` |
| 事件按时间排序 | `kubectl get events --sort-by=.lastTimestamp` |
| 仅告警事件 | `kubectl get events --field-selector type=Warning` |
| Service 后端 | `kubectl get endpoints <svc>` |
| DNS 测试 | `kubectl run tmp --rm -it --image=busybox -- nslookup <svc>` |
| 端口转发调试 | `kubectl port-forward svc/<name> 8080:80` |
| PVC 状态 | `kubectl get pvc -A` |
| 证书到期 | `kubeadm certs check-expiration` |
| RBAC 检查 | `kubectl auth can-i <verb> <resource> --as=<user>` |
| 临时调试容器 | `kubectl debug -it <pod> --image=busybox` |
