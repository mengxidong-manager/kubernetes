# Kubernetes 集群搭建指南

## 1. 本地开发环境

### 1.1 Minikube 安装配置

```bash
# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# macOS
brew install minikube

# 启动集群
minikube start --driver=docker --cpus=4 --memory=8192

# 常用命令
minikube status              # 查看状态
minikube dashboard           # 打开Web界面
minikube addons list         # 查看插件
minikube addons enable ingress   # 启用Ingress
minikube ssh                 # SSH进入节点
minikube stop                # 停止
minikube delete              # 删除集群
```

### 1.2 Kind (Kubernetes in Docker)

```bash
# 安装
# Linux/macOS
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# 创建单节点集群
kind create cluster --name dev

# 创建多节点集群
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# 删除集群
kind delete cluster --name dev
```

### 1.3 k3s 轻量级集群

```bash
# 单节点安装（Server）
curl -sfL https://get.k3s.io | sh -

# 查看 token（用于加入其他节点）
cat /var/lib/rancher/k3s/server/node-token

# Worker 节点加入
curl -sfL https://get.k3s.io | K3S_URL=https://<server-ip>:6443 K3S_TOKEN=<token> sh -

# kubeconfig 位置
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 卸载
/usr/local/bin/k3s-uninstall.sh
```

---

## 2. 生产环境搭建 (kubeadm)

### 2.1 系统准备（所有节点）

```bash
# 关闭 swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 加载内核模块
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 设置内核参数
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 2.2 安装容器运行时 (containerd)

```bash
# 安装 containerd
sudo apt-get update
sudo apt-get install -y containerd

# 配置 containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# 启用 SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 2.3 安装 kubeadm, kubelet, kubectl

```bash
# 添加 Kubernetes apt 仓库
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 安装
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### 2.4 初始化 Master 节点

```bash
# 初始化（记录输出的 join 命令）
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<master-ip>

# 配置 kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 安装网络插件 (Calico)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# 或使用 Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### 2.5 加入 Worker 节点

```bash
# 在 Worker 节点执行（使用 kubeadm init 输出的命令）
sudo kubeadm join <master-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# 如果 token 过期，在 Master 上重新生成
kubeadm token create --print-join-command
```

### 2.6 验证集群

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

---

## 3. 云服务托管 K8s

### 3.1 阿里云 ACK

```bash
# 安装 aliyun CLI
# 配置集群 kubeconfig
aliyun cs GET /k8s/<cluster-id>/user_config | jq -r '.config' > ~/.kube/config
```

### 3.2 AWS EKS

```bash
# 安装 eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 创建集群
eksctl create cluster \
  --name my-cluster \
  --region ap-northeast-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 3

# 更新 kubeconfig
aws eks update-kubeconfig --name my-cluster --region ap-northeast-1
```

### 3.3 GCP GKE

```bash
# 创建集群
gcloud container clusters create my-cluster \
  --zone asia-northeast1-a \
  --num-nodes 3

# 获取凭据
gcloud container clusters get-credentials my-cluster --zone asia-northeast1-a
```
