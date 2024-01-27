#!/usr/bin/env bash

# Reference https://akyriako.medium.com/install-kubernetes-1-27-with-cilium-on-ubuntu-16193c7c2ac6
export VERSION = "1.28.0-00"

export CONTROL_NODE_IP = "192.168.1.210"
export K8S_POD_NETWORK_CIDR = "10.244.0.0/16"

export CILIUM_VERSION = "1.14.0"

# Create /etc/hosts file
# Disable swap & Add kernel Parameters
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

sysctl --system

# Install Containerd Runtime
apt install -y curl gpg software-properties-common apt-transport-https ca-certificates

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

apt update
apt install -y containerd.io

# if you configure systemd as the cgroup driver for the kubelet, you must also configure systemd as the cgroup driver for the container runtime. containerd is using /etc/containerd/config.toml to configure its daemon.

containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
# sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

cat <<EOF | tee -a /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
SystemdCgroup = true
EOF

# enable CRI plugins
sed -i 's/^disabled_plugins \=/\#disabled_plugins \=/g' /etc/containerd/config.toml

# install the CNI plugins
mkdir -p /opt/cni/bin/
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz

systemctl restart containerd
systemctl enable containerd

# Add Apt Repository for Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubectl, Kubeadm and Kubelet
apt update
apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION kubernetes-cni
apt-mark hold kubelet kubeadm kubectl

# Install Kubernetes Cluster on Ubuntu 22.04
# TODO: Change the IP address to your master node IP address
# kubeadm init --control-plane-endpoint=k8smaster.example.net 2>&1 | tee /root/kubeadm.log

systemctl enable kubelet

kubeadm init \
    --apiserver-advertise-address=$CONTROL_NODE_IP \
    --pod-network-cidr=$K8S_POD_NETWORK_CIDR \
    --ignore-preflight-errors=NumCPU \
    --skip-phases=addon/kube-proxy \
    --control-plane-endpoint $CONTROL_NODE_IP \
    --upload-certs 2>&1 | tee /root/kubeadm.log

# Copy Kube Config
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
cp -i /etc/kubernetes/admin.conf $HOME/kubeconfig
chown $(id -u):$(id -g) $HOME/.kube/config

echo "Environment=\"KUBELET_EXTRA_ARGS=--node-ip=$MASTER_NODE_IP\"" | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

kubeadm token create --print-join-command >/root/join-command.sh

# Install Cilium
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

sudo cilium install --version $CILIUM_VERSION
