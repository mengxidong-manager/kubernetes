# 🐧 Linux & ☸️ Kubernetes 运维命令速查手册

> 覆盖 Linux 系统管理、网络诊断、磁盘存储、进程管理，以及 Kubernetes 集群管理、Pod 调试、资源运维等日常高频命令。
>
> 撰写人：孟希東

---

## 目录

### Linux
- [系统信息](#-系统信息)
- [文件与目录管理](#-文件与目录管理)
- [进程管理](#️-进程管理)
- [网络诊断](#-网络诊断)
- [磁盘与存储](#-磁盘与存储)
- [用户与权限](#-用户与权限)
- [系统服务](#-系统服务systemd)
- [日志排查](#-日志排查)

### Kubernetes
- [集群管理](#️-集群管理)
- [Pod 操作](#-pod-操作)
- [Deployment 与工作负载](#-deployment-与工作负载)
- [Service 与网络](#-service-与网络)
- [故障排查](#-故障排查)
- [资源管理](#-资源管理)
- [配置与密钥管理](#-配置与密钥管理)

### 速查表
- [Linux 速查表](#linux-速查表)
- [Kubernetes 速查表](#kubernetes-速查表)

---

# 🐧 Linux 常用命令

## 💻 系统信息

```bash
uname -a                   # 内核版本、主机名、架构
cat /etc/os-release        # 操作系统发行版详情
hostnamectl                # 主机名、OS、内核一览
uptime                     # 运行时间、负载均值
top / htop                 # 实时监控
free -h                    # 内存使用情况
lscpu                      # CPU 详细信息
vmstat 1 5                 # 虚拟内存统计
```

## 📁 文件与目录管理

```bash
ls -lah                    # 列出文件
cp -r src/ dst/            # 递归复制
mv old new                 # 移动/重命名
rm -rf dir/                # 强制递归删除（慎用）
find / -name "*.log" -mtime +30  # 查找30天前的log
find / -size +100M         # 查找大于100MB的文件
du -sh /var/*              # 各子目录大小
cat / head / tail -f       # 查看文件内容
grep -rn "error" /var/log/ # 递归搜索
awk '{print $1,$4}' file   # 提取列
sort | uniq -c | sort -rn  # 统计排序
tar -czvf a.tar.gz dir/    # 压缩
tar -xzvf a.tar.gz         # 解压
```

## ⚙️ 进程管理

```bash
ps aux                     # 查看所有进程
ps aux | grep nginx        # 过滤
kill PID / kill -9 PID     # 终止进程
killall nginx              # 按名终止
nohup command &            # 后台运行
lsof -i :8080              # 查端口占用
```

## 🌐 网络诊断

```bash
ip a / ip r                # 网络接口/路由
ping -c 4 8.8.8.8          # 连通性
traceroute / mtr           # 路由追踪
dig / nslookup             # DNS查询
curl -I https://example.com
ss -tlnp                   # TCP监听端口
ss -s                      # 连接统计
nc -zv host 80             # 端口测试
tcpdump -i eth0 port 80    # 抓包
iptables -L -n             # 防火墙规则
```

## 💾 磁盘与存储

```bash
df -h / df -ih             # 文件系统/inode
lsblk / fdisk -l           # 块设备/分区
iostat -xm 1 5             # I/O统计
smartctl -a /dev/sda       # SMART健康
```

## 🔑 用户与权限

```bash
whoami / id username        # 用户信息
useradd -m -s /bin/bash user
passwd user / usermod -aG group user
chmod 755 file / chown user:group file
```

## 🔄 系统服务（systemd）

```bash
systemctl status/start/stop/restart/reload nginx
systemctl enable/disable nginx
systemctl list-units --failed
journalctl -u nginx -f
journalctl -u nginx --since "1 hour ago"
```

## 📋 日志排查

```bash
dmesg -T | tail -50        # 内核日志
journalctl -xe             # 系统日志
tail -f /var/log/syslog    # 实时日志
last / lastb               # 登录记录
```

---

# ☸️ Kubernetes 常用命令

## 🏗️ 集群管理

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl top nodes
kubectl describe node <name>
kubectl config get-contexts / use-context <ctx>
kubectl cordon/uncordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl taint nodes <node> key=value:NoSchedule
kubectl label nodes <node> env=prod
```

## 📦 Pod 操作

```bash
kubectl get pods -A -o wide
kubectl get pods -l app=nginx
kubectl describe pod <name>
kubectl delete pod <name> [--force --grace-period=0]
kubectl exec -it <pod> -- /bin/bash
kubectl exec -it <pod> -c <container> -- /bin/bash
kubectl logs <pod> -f [--tail=100] [--since=1h] [--previous]
kubectl cp <pod>:/path/file ./local
```

## 🚀 Deployment

```bash
kubectl get deploy -A
kubectl apply -f deploy.yaml
kubectl scale deploy <name> --replicas=5
kubectl set image deploy/<name> nginx=nginx:1.25
kubectl rollout status/history/undo deploy/<name>
kubectl rollout restart deploy/<name>
```

## 🌐 Service 与网络

```bash
kubectl get svc -A -o wide
kubectl get endpoints <svc>
kubectl get ingress -A
kubectl run tmp --rm -it --image=busybox -- nslookup <svc>
kubectl port-forward svc/<name> 8080:80
```

## 🔍 故障排查

```bash
kubectl get pods | grep -v Running
kubectl describe pod <name>            # 看Events
kubectl logs <pod> --previous          # 崩溃前日志
kubectl get events --sort-by=.lastTimestamp
kubectl top pods --sort-by=cpu/memory
kubectl debug -it <pod> --image=busybox
```

> CrashLoopBackOff→logs --previous · ImagePullBackOff→检查镜像 · Pending→资源不足 · OOMKilled→增加memory

## 📊 资源管理

```bash
kubectl get ns / create ns staging
kubectl get pv / pvc -A / sc
kubectl get hpa -A
kubectl api-resources
```

## 🔐 配置管理

```bash
kubectl get cm/secret -n <ns>
kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d
kubectl get deploy <name> -o yaml > deploy.yaml
kubectl edit deploy <name>
kubectl diff -f deploy.yaml
kubectl apply -f deploy.yaml --dry-run=client
```

---

# ⚡ 速查表

## Linux

| 场景 | 命令 |
|------|------|
| 查系统 | `uname -a` / `hostnamectl` |
| 查内存 | `free -h` |
| 查磁盘 | `df -h` / `lsblk` |
| 查进程 | `ps aux` / `top` |
| 查端口 | `ss -tlnp` |
| 查日志 | `journalctl -u svc -f` |
| 服务管理 | `systemctl start/stop/status` |

## Kubernetes

| 场景 | 命令 |
|------|------|
| 查Pod | `kubectl get pods -o wide` |
| 查日志 | `kubectl logs <pod> -f` |
| 进入Pod | `kubectl exec -it <pod> -- bash` |
| 查事件 | `kubectl get events --sort-by=.lastTimestamp` |
| 扩缩容 | `kubectl scale deploy --replicas=N` |
| 回滚 | `kubectl rollout undo deploy` |
| 端口转发 | `kubectl port-forward svc/x 8080:80` |
| 节点维护 | `kubectl drain/cordon/uncordon` |
