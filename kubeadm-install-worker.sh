#!/usr/bin/env bash

#https://computingforgeeks.com/install-kubernetes-cluster-ubuntu-jammy/

#https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
#

# Get the name of the primary Ethernet interface
INTERFACE=$(ip route get 1 | awk '{print $5}')

# Get the IP address of the primary Ethernet interface
IP_ADDRESS=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Change the last octet to .10
IP_ADDRESS=$(echo $IP_ADDRESS | awk -F. -v OFS=. '{$4="10"; print}')

# Wait for the join-worker.sh file to exist on controller
while ! curl --output /dev/null --silent --head --fail "http://$IP_ADDRESS:8080/join-worker.sh"; do
  # echo "Waiting for rke confile file to exist..."
  sleep 5
done

echo "File exists. Continuing with script..."

wget -O /tmp/join-worker.sh http://$IP_ADDRESS:8080/join-worker.sh

##### Needed Info

###### Install dependencies

apt-get update && apt-get install -y apt-transport-https ca-certificates curl

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
apt install linux-image-generic-hwe-22.04 -y

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
apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

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

# wait for cluster to be ready
sleep 30

# join the cluster

chmod +x /tmp/join-worker.sh
/tmp/./join-worker.sh
