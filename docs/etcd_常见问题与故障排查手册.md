# etcd 常见问题与故障排查手册

> 覆盖集群健康、磁盘空间、性能退化、Leader 选举、成员管理、备份恢复、证书过期、数据损坏等全场景
>
> 撰写人：孟希東

---

## 快速健康检查脚本

```bash
#!/bin/bash
# etcd-health-check.sh
# 适配独立部署的 etcd 集群（TLS 证书路径按实际修改）

CERTS="--cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem"
EP="--endpoints=https://10.0.0.11:2379,https://10.0.0.12:2379,https://10.0.0.13:2379"

echo "=== 1. 集群健康 ==="
ETCDCTL_API=3 etcdctl endpoint health --cluster $EP $CERTS

echo -e "\n=== 2. 成员状态 ==="
ETCDCTL_API=3 etcdctl endpoint status --write-out=table --cluster $EP $CERTS

echo -e "\n=== 3. 告警 ==="
ETCDCTL_API=3 etcdctl alarm list $EP $CERTS

echo -e "\n=== 4. 证书到期 ==="
openssl x509 -in /etc/etcd/ssl/etcd.pem -noout -enddate

echo -e "\n=== 5. 数据库大小与碎片率 ==="
ETCDCTL_API=3 etcdctl endpoint status --write-out=json $EP $CERTS | \
  python3 -c "
import sys,json
data=json.load(sys.stdin)
for ep in data:
  s=ep['Status']
  total=s['dbSize']/1048576
  inuse=s.get('dbSizeInUse',s['dbSize'])/1048576
  frag=((total-inuse)/total*100) if total>0 else 0
  leader='★Leader' if s['leader']==s['header']['member_id'] else ''
  print(f\"  {ep['Endpoint']}: {total:.0f}MB (使用:{inuse:.0f}MB, 碎片:{frag:.0f}%) {leader}\")
"
```

---

## 1. 数据库空间问题

### 1.1 数据库空间超限（mvcc: database space exceeded）

etcd 默认配额 2GB（可配置最大 8GB），超限后变为只读。

**症状：**
- K8s API 写操作失败：`rpc error: etcdserver: mvcc: database space exceeded`
- Pod 无法创建、ConfigMap 无法更新
- etcd 日志报 `quota-backend-bytes` 相关错误

**排查：**
```bash
# 查看数据库大小
ETCDCTL_API=3 etcdctl endpoint status --write-out=table $EP $CERTS
# 关注 DB SIZE 列，超过配额就会只读

# 查看是否有 NOSPACE 告警
ETCDCTL_API=3 etcdctl alarm list $EP $CERTS
# 输出 alarm:NOSPACE 表示已超限
```

**修复：**
```bash
# Step 1: 获取当前最新 revision
rev=$(ETCDCTL_API=3 etcdctl endpoint status --write-out=json $EP $CERTS | \
  python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")

# Step 2: 压缩历史数据（删除旧 revision）
ETCDCTL_API=3 etcdctl compact $rev $EP $CERTS

# Step 3: 碎片整理（逐节点执行，不要并行）
ETCDCTL_API=3 etcdctl defrag --endpoints=https://10.0.0.11:2379 $CERTS
ETCDCTL_API=3 etcdctl defrag --endpoints=https://10.0.0.12:2379 $CERTS
ETCDCTL_API=3 etcdctl defrag --endpoints=https://10.0.0.13:2379 $CERTS

# Step 4: 解除 NOSPACE 告警
ETCDCTL_API=3 etcdctl alarm disarm $EP $CERTS

# Step 5: 验证
ETCDCTL_API=3 etcdctl alarm list $EP $CERTS   # 应为空
ETCDCTL_API=3 etcdctl endpoint status --write-out=table $EP $CERTS  # DB SIZE 应缩小
```

**预防：**
```bash
# 增大配额（启动参数添加）
--quota-backend-bytes=8589934592   # 8GB

# 配置自动压缩
--auto-compaction-mode=periodic
--auto-compaction-retention=1h     # 每小时自动压缩
```

### 1.2 碎片率过高

压缩后数据库文件大小不变，实际可用空间不释放。

**诊断：**
```bash
# DB SIZE 远大于 DB SIZE IN USE → 碎片化
# 例如：DB SIZE = 4GB, DB SIZE IN USE = 800MB → 碎片率 80%
ETCDCTL_API=3 etcdctl endpoint status --write-out=table --cluster $EP $CERTS
```

**修复：** 执行碎片整理（defrag），**必须逐节点执行**，每个节点会暂停几秒到几十秒。先对 Follower 执行，最后对 Leader 执行。

```bash
# 查看谁是 Leader
ETCDCTL_API=3 etcdctl endpoint status --write-out=table --cluster $EP $CERTS
# IS LEADER 列为 true 的是 Leader

# 先 defrag Follower，最后 defrag Leader
ETCDCTL_API=3 etcdctl defrag --endpoints=https://<follower-1>:2379 $CERTS
ETCDCTL_API=3 etcdctl defrag --endpoints=https://<follower-2>:2379 $CERTS
ETCDCTL_API=3 etcdctl defrag --endpoints=https://<leader>:2379 $CERTS
```

---

## 2. 性能退化

### 2.1 磁盘 I/O 慢（最常见根因）

etcd 对磁盘延迟极其敏感。WAL fsync P99 应 < 10ms，backend commit P99 应 < 25ms。

**症状：**
- API Server 响应变慢
- etcd 日志频繁出现 `slow fdatasync`、`apply request took too long`
- Leader 频繁切换

**诊断：**
```bash
# 查看 WAL fsync 延迟（Prometheus）
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))
# > 10ms = 磁盘太慢

# 查看 backend commit 延迟
histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket[5m]))
# > 25ms = 磁盘太慢

# 节点上直接测磁盘
fio --rw=write --ioengine=sync --fdatasync=1 --directory=/var/lib/etcd \
    --size=22m --bs=2300 --name=etcd-test
# 99th percentile fsync 应 < 10ms
```

**解决：**

| 方案 | 说明 |
|------|------|
| 换 SSD | etcd 必须使用 SSD，HDD 不可接受 |
| 独立磁盘 | etcd 数据目录独立 SSD，不与系统盘共享 |
| 提高 I/O 优先级 | `ionice -c2 -n0 -p $(pgrep etcd)` |
| 减少 I/O 竞争 | etcd 节点不跑其他 I/O 密集应用 |
| 调整 etcd 参数 | `--snapshot-count=5000`（默认 10000） |

### 2.2 网络延迟高

etcd 节点间 RTT 应 < 10ms（同机房），跨机房 < 50ms。

**诊断：**
```bash
# Prometheus 指标
histogram_quantile(0.99, rate(etcd_network_peer_round_trip_time_seconds_bucket[5m]))

# 直接 ping 测试
ping -c 100 <other-etcd-node>
```

**解决：** etcd 节点应在同一局域网，不要跨机房部署。如必须跨机房，调大心跳和选举超时。

### 2.3 请求延迟高

**诊断：**
```bash
# gRPC 请求延迟
histogram_quantile(0.99, sum(rate(grpc_server_handling_seconds_bucket{job="etcd",grpc_type="unary"}[5m])) by (le))

# 性能测试
ETCDCTL_API=3 etcdctl check perf $EP $CERTS
```

---

## 3. Leader 选举问题

### 3.1 频繁 Leader 切换

**症状：** `etcd_server_leader_changes_seen_total` 快速增长，每小时 > 3 次。

**常见原因与解决：**

| 原因 | 诊断 | 解决 |
|------|------|------|
| 磁盘慢 | WAL fsync > 10ms | 换 SSD，独立磁盘 |
| 网络抖动 | peer RTT 不稳定 | 修复网络，检查交换机 |
| CPU 争抢 | etcd 节点 CPU 被占满 | 减少 etcd 节点上的其他负载 |
| 时钟偏差 | 节点间时间差 > 500ms | `chronyc tracking` 检查，修复 NTP |
| 心跳超时太短 | 默认 100ms | 高延迟环境调大心跳和选举超时 |

**调整超时参数：**
```bash
# etcd 启动参数
--heartbeat-interval=500        # 默认 100ms，高延迟调大
--election-timeout=5000         # 默认 1000ms，应为心跳的 5-10 倍
```

### 3.2 无 Leader（集群不可用）

**症状：** `etcd_server_has_leader == 0`，API Server 完全不可用。

**常见原因：**
- 多数节点（>= N/2 + 1）同时宕机，丧失 quorum
- 3 节点集群坏 2 个 = 无法选举

**紧急恢复：** 优先恢复任一宕机节点，使存活节点 >= 2（3 节点集群）。如果数据已损坏，需从备份恢复（见第 6 节）。

---

## 4. 成员管理问题

### 4.1 成员不健康

```bash
# 查看成员列表
ETCDCTL_API=3 etcdctl member list --write-out=table $EP $CERTS

# 某成员 unhealthy
ETCDCTL_API=3 etcdctl endpoint health --cluster $EP $CERTS
# https://10.0.0.13:2379 is unhealthy
```

**排查：** SSH 到不健康节点，检查 etcd 进程、磁盘、网络。

### 4.2 替换故障成员

```bash
# Step 1: 移除故障成员
ETCDCTL_API=3 etcdctl member remove <MEMBER_ID> $EP $CERTS

# Step 2: 在新节点上清理数据目录
rm -rf /var/lib/etcd/*

# Step 3: 添加新成员
ETCDCTL_API=3 etcdctl member add etcd-03 --peer-urls=https://10.0.0.13:2380 $EP $CERTS

# Step 4: 在新节点上启动 etcd（注意 --initial-cluster-state=existing）
# 修改 systemd 服务文件中的 --initial-cluster-state=existing（不是 new）
sudo systemctl restart etcd
```

> ⚠️ 替换顺序：先 remove 旧成员，再 add 新成员。不要直接清数据重启。

### 4.3 集群扩缩容

etcd 推荐 3 或 5 个节点（奇数），不建议超过 7 个。

| 集群大小 | 容忍故障数 | 适用场景 |
|----------|-----------|----------|
| 1 | 0 | 仅测试 |
| 3 | 1 | 生产标准 |
| 5 | 2 | 高可用要求 |
| 7 | 3 | 极高可用（性能下降） |

---

## 5. 证书问题

### 5.1 证书过期

**症状：**
- etcd 节点间通信失败
- API Server 连接 etcd 失败
- 日志报 `tls: certificate has expired`

**诊断：**
```bash
# 检查证书到期时间
openssl x509 -in /etc/etcd/ssl/etcd.pem -noout -dates
# notAfter=Jun 30 00:00:00 2036 GMT

# 检查 API Server 到 etcd 的客户端证书
openssl x509 -in /etc/kubernetes/pki/apiserver-etcd-client.crt -noout -dates
```

**解决：** 用 cfssl 重新签发证书（参考 HA 集群部署指南 Phase 2），分发到所有节点，重启 etcd 和 API Server。

### 5.2 证书不匹配

**症状：** `tls: bad certificate` 或 `certificate signed by unknown authority`

**排查：**
```bash
# 验证证书链
openssl verify -CAfile /etc/etcd/ssl/ca.pem /etc/etcd/ssl/etcd.pem

# 检查证书 SAN（必须包含节点 IP）
openssl x509 -in /etc/etcd/ssl/etcd.pem -noout -text | grep -A5 "Subject Alternative Name"
```

---

## 6. 备份与灾难恢复

### 6.1 创建备份

```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M).db \
  --endpoints=https://10.0.0.11:2379 $CERTS

# 验证备份
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-*.db --write-out=table
```

### 6.2 从备份恢复（灾难恢复）

```bash
# 在所有 etcd 节点上停止 etcd
sudo systemctl stop etcd

# 在每个节点上恢复（注意 --name 和 --initial-advertise-peer-urls 各不相同）
# 节点 1：
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-backup.db \
  --name=etcd-01 \
  --data-dir=/var/lib/etcd \
  --initial-cluster="etcd-01=https://10.0.0.11:2380,etcd-02=https://10.0.0.12:2380,etcd-03=https://10.0.0.13:2380" \
  --initial-advertise-peer-urls=https://10.0.0.11:2380

# 节点 2、3 同理（修改 --name 和 --initial-advertise-peer-urls）

# 启动所有 etcd
sudo systemctl start etcd

# 验证
ETCDCTL_API=3 etcdctl endpoint health --cluster $EP $CERTS
```

### 6.3 自动备份（crontab）

```bash
# /etc/cron.d/etcd-backup
0 * * * * root ETCDCTL_API=3 /usr/local/bin/etcdctl snapshot save /backup/etcd-$(date +\%Y\%m\%d-\%H).db --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints=https://127.0.0.1:2379 2>&1 | logger -t etcd-backup

# 保留 7 天
0 2 * * * root find /backup -name "etcd-*.db" -mtime +7 -delete
```

---

## 7. 监控告警阈值

| 指标 | 阈值 | 级别 | 含义 |
|------|------|------|------|
| `etcd_server_has_leader` | == 0 | 🔴 致命 | 无 Leader，集群不可用 |
| `etcd_server_leader_changes_seen_total` rate | > 3/hour | ⚠️ 警告 | 频繁选举，集群不稳定 |
| `etcd_mvcc_db_total_size_in_bytes` | > 6 GB | ⚠️ 警告 | 接近默认 8GB 限额 |
| `etcd_mvcc_db_total_size_in_bytes` | > 7.5 GB | 🔴 严重 | 即将超限变只读 |
| `etcd_disk_wal_fsync_duration_seconds` P99 | > 10 ms | ⚠️ 警告 | 磁盘慢 |
| `etcd_disk_wal_fsync_duration_seconds` P99 | > 100 ms | 🔴 严重 | 磁盘严重慢，会导致选举失败 |
| `etcd_disk_backend_commit_duration_seconds` P99 | > 25 ms | ⚠️ 警告 | 后端提交慢 |
| `etcd_network_peer_round_trip_time_seconds` P99 | > 50 ms | ⚠️ 警告 | 节点间网络延迟高 |
| `etcd_server_proposals_failed_total` rate | > 0 | ⚠️ 警告 | 提案失败 |
| `etcd_server_proposals_pending` | > 5 | ⚠️ 警告 | 提案堆积 |

### Prometheus 告警规则

```yaml
- alert: EtcdNoLeader
  expr: etcd_server_has_leader == 0
  for: 1m
  labels: { severity: critical }
  annotations:
    summary: "etcd 节点无 Leader ({{ $labels.instance }})"

- alert: EtcdFrequentLeaderChanges
  expr: increase(etcd_server_leader_changes_seen_total[1h]) > 3
  labels: { severity: warning }
  annotations:
    summary: "etcd Leader 频繁切换"

- alert: EtcdDatabaseSizeHigh
  expr: etcd_mvcc_db_total_size_in_bytes > 6442450944
  labels: { severity: warning }
  annotations:
    summary: "etcd 数据库 > 6GB ({{ $labels.instance }})"

- alert: EtcdHighFsyncDuration
  expr: histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.1
  for: 5m
  labels: { severity: warning }
  annotations:
    summary: "etcd WAL fsync P99 > 100ms"
```

---

## 排查命令速查表

| 场景 | 命令 |
|------|------|
| 集群健康 | `etcdctl endpoint health --cluster` |
| 成员状态 | `etcdctl endpoint status --write-out=table --cluster` |
| 成员列表 | `etcdctl member list --write-out=table` |
| 告警列表 | `etcdctl alarm list` |
| 解除告警 | `etcdctl alarm disarm` |
| 压缩历史 | `etcdctl compact <revision>` |
| 碎片整理 | `etcdctl defrag --endpoints=<single>` |
| 快照备份 | `etcdctl snapshot save <file>` |
| 快照恢复 | `etcdctl snapshot restore <file> --data-dir=...` |
| 快照状态 | `etcdctl snapshot status <file> --write-out=table` |
| 移除成员 | `etcdctl member remove <ID>` |
| 添加成员 | `etcdctl member add <name> --peer-urls=<url>` |
| 性能测试 | `etcdctl check perf` |
| Key 数量 | `etcdctl get / --prefix --keys-only \| wc -l` |
| 查看证书 | `openssl x509 -in <cert> -noout -dates -text` |
