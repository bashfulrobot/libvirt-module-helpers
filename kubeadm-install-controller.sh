#!/usr/bin/env bash

#https://computingforgeeks.com/install-kubernetes-cluster-ubuntu-jammy/

#https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
#

##### Needed Info

# Which CNI, sets pod CIDR in `kubeadm init`
# Valid Settings:
# - empty (used flannel pod CIDR - 10.244.0.0/16)
# - calico (uses calico pod CIDR - 192.168.0.0/16)
# - cilium (used cilium pod CIDR - 10.0.0.0/8, disbles `kube-proxy`)
# check if /root/cni (file existed), and if not run the default command,
# and if so, check the file for either "cilium" or "calico". Then run the command that matches.

# Metallb Version
METALLB_VERSION="v0.13.12"

## Find the server IP
SERVER_IP=$(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep '.10$')

# Extract the first 3 octets from $SERVER_IP
first_three_octets=$(echo "$SERVER_IP" | cut -d. -f1-3)

# Build the complete metallb IP address - .5 is the load balancer IP
load_balancer_ip="${first_three_octets}.5"
metallb_pool_ip1="${first_three_octets}.30"
metallb_pool_ip2="${first_three_octets}.31"
metallb_pool_ip3="${first_three_octets}.32"
metallb_pool_ip4="${first_three_octets}.33"
metallb_pool_ip5="${first_three_octets}.34"
metallb_pool_ip6="${first_three_octets}.35"

###### Install dependencies

apt-get update && apt-get install -y apt-transport-https ca-certificates curl gpg

##### Install kubeadm

# Add the repository

# Check version to be installed, if not set, defalt to below
K8S_VERSION=${K8S_VERSION:-"1.29"}
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

apt update

# Install the specified version
apt-get install -qy kubelet kubectl kubeadm

apt-mark hold kubelet kubeadm kubectl

# Update kernel to support cilium
#apt install linux-image-generic-hwe-22.04 -y

##### Host Configuration

# Disable swap
swapoff -a
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab
mount -a

# Enable kernel modules
modprobe overlay
modprobe br_netfilter

# Add some settings to sysctl
tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.proxy_arp = 1
net.ipv4.conf.ens2.proxy_arp = 1
EOF

# Reload sysctl
sysctl --system

##### Installing Containerd

# Configure persistent loading of modules
tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# Load at runtime
modprobe overlay
modprobe br_netfilter

# Ensure sysctl params are set
tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload configs
sysctl --system

# Install required packages
apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates gpg

# Add Docker repo

# Unused as I am using the version from the ubuntu repo
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-archive-keyring.gpg
# echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
# apt update
# apt install -y containerd # docker repo version. Disables CRI intetration

# Install containerd
apt update
# apt install -y containerd # docker repo version. Disables CRI intetration

apt install -y containerd

# Configure containerd and start service
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable Systemd cgroup integration as per https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
sed -i '/SystemdCgroup =/s/false/true/' /etc/containerd/config.toml

# restart containerd
systemctl restart containerd
systemctl enable containerd
systemctl status containerd

##### Kubernetes Cluster Setup

# enable kubelet
systemctl enable kubelet

# Pull images
kubeadm config images pull

# Initialize Kubernetes Cluster
# --control-plane-endpoint :  set the shared endpoint for all control-plane nodes. Can be DNS/IP (IE loadbalancer IP/DNS)
# --pod-network-cidr : Used to set a Pod network add-on CIDR
# --cri-socket : Use if have more than one container runtime to set runtime socket path
# --apiserver-advertise-address : Set advertise address for this particular control-plane node's API server (IE Single CP Node Cluster)

# Check if /root/cni file exists
if [[ -f "/tmp/cni" ]]; then
    # Read the content of /root/cni file
    CNI=$(<"/tmp/cni")

    if [[ "${CNI}" == "cilium" ]]; then
        # CNI variable is set to "cilium", run specific command
        kubeadm init --upload-certs --pod-network-cidr=10.0.0.0/8 --apiserver-advertise-address=${SERVER_IP} --skip-phases=addon/kube-proxy
    elif [[ "${CNI}" == "calico" ]]; then
        # CNI variable is set to "calico", run specific command
        kubeadm init --upload-certs --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=${SERVER_IP}
    else
        # CNI variable is set to an unexpected value, handle the error
        echo "Invalid CNI value in /root/cni: ${CNI}"
        exit 1  # Terminate the script with an error code
    fi
else
    # /root/cni file does not exist, run default command
    kubeadm init --upload-certs --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${SERVER_IP}
fi

# wait for cluster to be ready
sleep 30

# Copy kube config
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

# rename users and cluster
sed -i 's/kubernetes-admin@kubernetes/overlord@darkstar/g' /root/.kube/config
sed -i 's/kubernetes-admin/overlord/g' /root/.kube/config
sed -i 's/kubernetes/darkstar/g' /root/.kube/config

# Used for retreival from the desktop
cp /root/.kube/config /root/kubeconfig

# create join command script for later reference
echo '#!/usr/bin/env bash' >/root/join-worker.sh
echo $(kubeadm token create --print-join-command) >>/root/join-worker.sh
chmod +x /root/join-worker.sh

# Get Metallb manifest
wget -O /etc/kubernetes/manifests/metallb-native.yaml https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml

# Configure Metallb
cat <<EOF >/etc/kubernetes/manifests/metallb-config.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - $load_balancer_ip/32
  - $metallb_pool_ip1/32
  - $metallb_pool_ip2/32
  - $metallb_pool_ip3/32
  - $metallb_pool_ip4/32
  - $metallb_pool_ip5/32
  - $metallb_pool_ip6/32
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF

##### Tmp HTTP Server
chmod +x /tmp/serve
timeout 30m /tmp/serve -d /root &
