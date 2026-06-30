# 🐧 Linux & ☸️ Kubernetes 运维命令速查手册

> 覆盖 Linux 系统管理、网络诊断、磁盘存储、进程管理，以及 Kubernetes 集群管理、Pod 调试、资源运维等日常高频命令。
>
> 撰写人：孟希东（测试）

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

### 查看系统/内核信息

```bash
uname -a                   # 内核版本、主机名、架构
cat /etc/os-release        # 操作系统发行版详情
hostnamectl                # 主机名、OS、内核一览
uptime                     # 运行时间、负载均值
```

### CPU / 内存 / 负载

```bash
top                        # 实时进程和资源监控
htop                       # 增强版 top（需安装）
free -h                    # 内存使用情况（人类可读）
lscpu                      # CPU 详细信息
cat /proc/meminfo          # 内存详细信息
vmstat 1 5                 # 每秒刷新，共 5 次虚拟内存统计
sar -u 1 5                 # CPU 使用率历史采样
```

## 📁 文件与目录管理

### 文件操作

```bash
ls -lah                    # 列出文件（含隐藏文件、权限、大小）
cp -r src/ dst/            # 递归复制目录
mv old new                 # 移动/重命名
rm -rf dir/                # 强制递归删除（慎用）
find / -name "*.log" -mtime +30  # 查找 30 天前的 log 文件
find / -size +100M         # 查找大于 100MB 的文件
du -sh /var/*              # 各子目录大小
```

### 文本查看与处理

```bash
cat file                   # 查看文件全部内容
head -n 50 file            # 查看前 50 行
tail -f /var/log/syslog    # 实时追踪日志
grep -rn "error" /var/log/ # 递归搜索含 error 的行（显示行号）
grep -i "oom" /var/log/messages  # 忽略大小写搜索 OOM
awk '{print $1,$4}' file   # 提取第 1 和第 4 列
sort file | uniq -c | sort -rn  # 统计并排序重复行
wc -l file                 # 统计行数
```

### 压缩与解压

```bash
tar -czvf archive.tar.gz dir/   # 压缩为 tar.gz
tar -xzvf archive.tar.gz        # 解压 tar.gz
tar -xjvf archive.tar.bz2       # 解压 tar.bz2
unzip file.zip -d /target/      # 解压 zip 到指定目录
```

## ⚙️ 进程管理

```bash
ps aux                     # 查看所有进程
ps aux | grep nginx        # 过滤指定进程
ps -eo pid,ppid,%cpu,%mem,cmd --sort=-%cpu | head  # 按 CPU 排序
pstree -p                  # 进程树
kill PID                   # 优雅终止
kill -9 PID                # 强制终止
killall nginx              # 按进程名终止所有实例
nohup command &            # 后台运行，不受终端关闭影响
lsof -i :8080              # 查看占用 8080 端口的进程
lsof -p PID                # 查看进程打开的文件
```

## 🌐 网络诊断

### 网络配置与连通性

```bash
ip a                       # 查看所有网络接口和 IP
ip r                       # 查看路由表
ping -c 4 8.8.8.8          # 测试网络连通性
traceroute google.com      # 追踪路由路径
mtr google.com             # 增强版 traceroute（实时）
dig example.com            # DNS 查询
nslookup example.com       # DNS 解析
curl -I https://example.com  # 查看 HTTP 响应头
```

### 端口与连接

```bash
ss -tlnp                   # 查看所有监听的 TCP 端口和进程
ss -s                      # 连接统计摘要
netstat -tlnp              # 同上（老版本）
nc -zv host 80             # 测试端口是否开放
tcpdump -i eth0 port 80    # 抓包指定端口
tcpdump -i any -w cap.pcap # 全接口抓包保存文件
iptables -L -n             # 查看防火墙规则
firewall-cmd --list-all    # firewalld 规则（CentOS/RHEL）
```

## 💾 磁盘与存储

### 磁盘空间与挂载

```bash
df -h                      # 各文件系统使用情况
df -ih                     # inode 使用情况
du -sh /var/* | sort -rh | head  # 找出最大的目录
lsblk                      # 查看块设备（磁盘/分区）树
fdisk -l                   # 查看磁盘分区详情
mount | column -t           # 查看当前挂载
```

### 磁盘性能与健康

```bash
iostat -xm 1 5             # 磁盘 I/O 统计（每秒刷新，5 次）
iotop                      # 按进程查看 I/O 使用
smartctl -a /dev/sda       # SMART 磁盘健康信息
hdparm -Tt /dev/sda        # 磁盘读取速度测试
```

## 🔑 用户与权限

```bash
whoami                     # 当前用户
id username                # 用户 UID/GID/所属组
useradd -m -s /bin/bash user  # 创建用户
passwd user                # 设置/修改密码
usermod -aG docker user    # 将用户加入 docker 组
chmod 755 file             # 修改权限（rwxr-xr-x）
chmod -R 644 dir/          # 递归修改
chown user:group file      # 修改所有者
chown -R user:group dir/   # 递归修改所有者
```

## 🔄 系统服务（systemd）

```bash
systemctl status nginx     # 查看服务状态
systemctl start nginx      # 启动服务
systemctl stop nginx       # 停止服务
systemctl restart nginx    # 重启服务
systemctl reload nginx     # 重载配置（不中断服务）
systemctl enable nginx     # 设置开机自启
systemctl disable nginx    # 取消开机自启
systemctl list-units --type=service --state=running  # 所有运行中的服务
systemctl list-units --failed  # 查看失败的服务
journalctl -u nginx -f     # 实时查看 nginx 日志
journalctl -u nginx --since "1 hour ago"  # 最近 1 小时日志
```

## 📋 日志排查

```bash
dmesg -T | tail -50        # 内核日志（最近 50 条，带时间戳）
dmesg | grep -i error      # 内核错误
journalctl -xe             # 最近的系统日志（带解释）
journalctl --since "2026-06-19 00:00"  # 指定时间段
journalctl -k              # 仅内核日志
tail -f /var/log/syslog    # 实时查看系统日志（Debian/Ubuntu）
tail -f /var/log/messages  # 实时查看系统日志（CentOS/RHEL）
last                       # 最近登录记录
lastb                      # 登录失败记录
cat /var/log/auth.log      # 认证日志（SSH 等）
```

---

# ☸️ Kubernetes 常用命令

## 🏗️ 集群管理

### 集群信息与上下文

```bash
kubectl cluster-info               # 集群信息
kubectl get nodes -o wide          # 节点列表（IP、OS、内核、容器运行时）
kubectl top nodes                  # 节点 CPU/内存使用率
kubectl describe node <name>       # 节点详情（资源/条件/事件）
kubectl get cs                     # 组件状态（scheduler/controller/etcd）
kubectl config get-contexts        # 查看所有上下文
kubectl config use-context <ctx>   # 切换集群上下文
kubectl config set-context --current --namespace=prod  # 设置默认命名空间
```

### 节点管理

```bash
kubectl cordon <node>              # 标记节点不可调度
kubectl uncordon <node>            # 恢复节点可调度
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data  # 驱逐 Pod（维护前）
kubectl taint nodes <node> key=value:NoSchedule   # 添加污点
kubectl taint nodes <node> key=value:NoSchedule-  # 移除污点
kubectl label nodes <node> env=prod  # 添加标签
```

## 📦 Pod 操作

### 查看与管理 Pod

```bash
kubectl get pods                   # 当前命名空间 Pod 列表
kubectl get pods -A                # 所有命名空间 Pod
kubectl get pods -o wide           # 显示 IP、节点等
kubectl get pods --field-selector=status.phase=Failed  # 过滤失败 Pod
kubectl get pods -l app=nginx      # 按标签筛选
kubectl get pods --sort-by=.status.startTime  # 按启动时间排序
kubectl describe pod <name>        # Pod 详情（事件/条件/容器状态）
kubectl delete pod <name>          # 删除 Pod
kubectl delete pod <name> --force --grace-period=0  # 强制删除
```

### 进入 Pod / 执行命令

```bash
kubectl exec -it <pod> -- /bin/bash      # 进入 Pod shell
kubectl exec -it <pod> -- /bin/sh        # 无 bash 时用 sh
kubectl exec -it <pod> -c <container> -- /bin/bash  # 多容器指定
kubectl exec <pod> -- env                # 查看 Pod 环境变量
kubectl exec <pod> -- cat /etc/resolv.conf  # 查看 Pod DNS
```

### 日志查看

```bash
kubectl logs <pod>                 # 查看日志
kubectl logs <pod> -f              # 实时追踪日志
kubectl logs <pod> --tail=100      # 最近 100 行
kubectl logs <pod> --since=1h      # 最近 1 小时
kubectl logs <pod> -c <container>  # 多容器指定
kubectl logs <pod> --previous      # 上一个崩溃容器的日志
kubectl logs -l app=nginx --all-containers  # 按标签批量查看
```

### 文件复制

```bash
kubectl cp <pod>:/path/file ./local  # 从 Pod 复制到本地
kubectl cp ./local <pod>:/path/      # 从本地复制到 Pod
```

## 🚀 Deployment 与工作负载

### 部署管理

```bash
kubectl get deploy -A              # 所有命名空间部署列表
kubectl describe deploy <name>     # 部署详情
kubectl apply -f deploy.yaml       # 应用/更新配置
kubectl delete -f deploy.yaml      # 删除
kubectl create deploy nginx --image=nginx:latest --replicas=3  # 快速创建
```

### 扩缩容与更新

```bash
kubectl scale deploy <name> --replicas=5          # 扩容到 5 副本
kubectl autoscale deploy <name> --min=2 --max=10 --cpu-percent=80  # HPA
kubectl set image deploy/<name> nginx=nginx:1.25  # 更新镜像
kubectl rollout status deploy/<name>              # 查看滚动更新状态
kubectl rollout history deploy/<name>             # 查看更新历史
kubectl rollout undo deploy/<name>                # 回滚到上一版本
kubectl rollout undo deploy/<name> --to-revision=2  # 回滚到指定版本
kubectl rollout restart deploy/<name>             # 滚动重启
```

## 🌐 Service 与网络

### Service 管理

```bash
kubectl get svc -A                 # 所有服务
kubectl get svc -o wide            # 显示 Selector、端口映射
kubectl describe svc <name>        # 服务详情（Endpoints 等）
kubectl get endpoints <svc>        # 服务后端 Pod IP 列表
kubectl expose deploy <name> --port=80 --target-port=8080 --type=ClusterIP
```

### 网络调试

```bash
kubectl get ingress -A             # 查看所有 Ingress
kubectl get networkpolicy -A       # 查看网络策略
# 集群内 DNS 测试
kubectl run tmp --rm -it --image=busybox -- nslookup <svc>.<ns>.svc.cluster.local
# 集群内 HTTP 测试
kubectl run tmp --rm -it --image=curlimages/curl -- curl -s http://<svc>:80
# 端口转发
kubectl port-forward svc/<name> 8080:80
kubectl port-forward pod/<name> 8080:8080
```

## 🔍 故障排查

```bash
# Pod 状态排查
kubectl get pods | grep -v Running           # 找出非 Running 的 Pod
kubectl describe pod <name>                  # 查看 Events 定位原因
kubectl logs <pod> --previous                # 崩溃前日志

# 事件排查
kubectl get events --sort-by=.lastTimestamp  # 按时间排序事件
kubectl get events -n <ns> --field-selector type=Warning  # 仅告警事件

# 资源问题排查
kubectl top pods --sort-by=cpu               # 按 CPU 排序 Pod
kubectl top pods --sort-by=memory            # 按内存排序 Pod

# 节点问题排查
kubectl describe node <name> | grep -A5 Conditions
kubectl describe node <name> | grep -A10 "Allocated resources"

# 临时调试容器（K8s 1.25+）
kubectl debug -it <pod> --image=busybox --target=<container>
```

> **常见 Pod 异常状态：**
> - `CrashLoopBackOff`（反复崩溃）→ 查 `logs --previous`
> - `ImagePullBackOff`（拉镜像失败）→ 检查镜像名和仓库权限
> - `Pending`（调度不上）→ `describe` 看 Events，通常是资源不足或节点选择器不匹配
> - `OOMKilled` → 增加 memory limits

## 📊 资源管理

### Namespace 与资源配额

```bash
kubectl get ns                     # 查看所有命名空间
kubectl create ns staging          # 创建命名空间
kubectl get quota -n <ns>          # 查看资源配额
kubectl get limitrange -n <ns>     # 查看限制范围
kubectl api-resources              # 查看所有支持的资源类型
```

### PV / PVC 存储管理

```bash
kubectl get pv                     # 查看持久卷
kubectl get pvc -A                 # 查看持久卷声明
kubectl describe pvc <name>        # PVC 详情（绑定状态、StorageClass）
kubectl get sc                     # 查看 StorageClass
```

### HPA 自动扩缩

```bash
kubectl get hpa -A                 # 查看所有 HPA
kubectl describe hpa <name>        # HPA 详情（当前指标/目标/副本数）
```

## 🔐 配置与密钥管理

### ConfigMap 与 Secret

```bash
kubectl get cm -n <ns>             # 查看 ConfigMap 列表
kubectl describe cm <name>         # 查看 ConfigMap 内容
kubectl create cm myconfig --from-file=config.yaml    # 从文件创建
kubectl create cm myconfig --from-literal=key=value   # 从键值创建

kubectl get secret -n <ns>         # 查看 Secret 列表
kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d  # 解码
kubectl create secret generic mysecret --from-literal=password=abc123
```

### YAML 导出与编辑

```bash
kubectl get deploy <name> -o yaml > deploy.yaml  # 导出 YAML
kubectl edit deploy <name>         # 在线编辑（vi）
kubectl diff -f deploy.yaml        # 对比本地文件与线上差异
kubectl apply -f deploy.yaml --dry-run=client  # 干跑模式（不实际执行）
kubectl apply -f https://url/manifest.yaml     # 从 URL 直接应用
```

---

# ⚡ 速查表

## Linux 速查表

| 场景 | 命令 | 说明 |
|------|------|------|
| 查系统信息 | `uname -a` / `hostnamectl` | 内核、OS、主机名 |
| 查内存 | `free -h` | 人类可读格式 |
| 查磁盘 | `df -h` / `lsblk` | 文件系统/块设备 |
| 查进程 | `ps aux` / `top` / `htop` | 静态/动态进程列表 |
| 查端口 | `ss -tlnp` / `lsof -i :PORT` | 监听端口和进程 |
| 查日志 | `journalctl -u svc -f` | 实时追踪服务日志 |
| 查大文件 | `du -sh /* \| sort -rh` | 按大小排序 |
| 网络测试 | `ping` / `traceroute` / `curl` | 连通性/路由/HTTP |
| 服务管理 | `systemctl start/stop/status` | systemd 服务控制 |

## Kubernetes 速查表

| 场景 | 命令 | 说明 |
|------|------|------|
| 查 Pod | `kubectl get pods -o wide` | IP、节点、状态 |
| 查日志 | `kubectl logs <pod> -f` | 实时追踪 |
| 进入 Pod | `kubectl exec -it <pod> -- bash` | 交互式 shell |
| 查事件 | `kubectl get events --sort-by=.lastTimestamp` | 排障首选 |
| 扩缩容 | `kubectl scale deploy --replicas=N` | 调整副本数 |
| 回滚 | `kubectl rollout undo deploy` | 回到上一版本 |
| 端口转发 | `kubectl port-forward svc/x 8080:80` | 本地调试 |
| 节点维护 | `kubectl drain` / `cordon` / `uncordon` | 驱逐/禁调度/恢复 |
| 查资源用量 | `kubectl top pods/nodes` | CPU/内存实时用量 |
