#!/bin/env bash

# Metallb Version
METALLB_VERSION="v0.13.12"
LONGHORN_VERSION="v1.5.3"
FLUX_VERSION="2.2.2"

## Find the server IP
SERVER_IP=$(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep '.10$')

## Enable nginx compatibility with metallb on k3s
# Set the file path
# file_path="/var/lib/rancher/k3s/server/manifests"

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

# Install flux cli

#curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=$FLUX_VERSION bash

mkdir -p /var/lib/rancher/k3s/server/manifests

mkdir -p /etc/rancher/k3s/
# touch /etc/rancher/k3s/config.yaml

# Patch Ingress Nginx for metallb
# cat <<EOF >"/var/lib/rancher/k3s/server/manifests/k3s-ingress-nginx-config.yaml"
# ---
# apiVersion: helm.cattle.io/v1
# kind: HelmChartConfig
# metadata:
#   name: k3s-ingress-nginx
#   namespace: kube-system
# spec:
#   valuesContent: |-
#     controller:
#       config:
#         use-forwarded-headers: "true"
#         enable-real-ip: "true"
#       publishService:
#         enabled: true
#       service:
#         enabled: true
#         type: LoadBalancer
#         external:
#           enabled: true
#         externalTrafficPolicy: Local
#         annotations:
#           metallb.universe.tf/loadBalancerIPs: $load_balancer_ip ## Configure static load balancer IP
# EOF

# Install Cilium as the CNI

mkdir -p /etc/rancher/k3s/

# cat <<EOF >"/etc/rancher/k3s/config.yaml"
# cni: none
# EOF
# cat <<EOF >"/etc/rancher/k3s/config.yaml"
# cni: "cilium"
# disable-kube-proxy: true
# EOF

# cat <<EOF >"/var/lib/rancher/k3s/server/manifests/k3s-cilium-config.yaml"
# apiVersion: helm.cattle.io/v1
# kind: HelmChartConfig
# metadata:
#   name: k3s-cilium
#   namespace: kube-system
# spec:
#   valuesContent: |-
#     kubeProxyReplacement: true
#     k8sServiceHost: "$SERVER_IP"
#     k8sServicePort: "6443"
#     # ingressController:
#     #   enabled: false
#     # gatewayAPI:
#     #   enabled: true
# EOF

# Get Metallb manifest
# wget -O /var/lib/rancher/k3s/server/manifests/metallb-native.yaml https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml

# Configure Metallb
# cat <<EOF >/var/lib/rancher/k3s/server/manifests/metallb-config.yaml
# ---
# apiVersion: v1
# kind: Namespace
# metadata:
#   name: metallb-system
#   labels:
#     pod-security.kubernetes.io/enforce: privileged
#     pod-security.kubernetes.io/audit: privileged
#     pod-security.kubernetes.io/warn: privileged
# ---
# apiVersion: metallb.io/v1beta1
# kind: IPAddressPool
# metadata:
#   name: default
#   namespace: metallb-system
# spec:
#   addresses:
#   - $load_balancer_ip/32
#   - $metallb_pool_ip1/32
#   - $metallb_pool_ip2/32
#   - $metallb_pool_ip3/32
#   - $metallb_pool_ip4/32
#   - $metallb_pool_ip5/32
#   - $metallb_pool_ip6/32
#   autoAssign: true
# ---
# apiVersion: metallb.io/v1beta1
# kind: L2Advertisement
# metadata:
#   name: default
#   namespace: metallb-system
# spec:
#   ipAddressPools:
#   - default
# EOF

# Wget the Longhorn manifest
# wget -O /var/lib/rancher/k3s/server/manifests/longhorn.yaml https://raw.githubusercontent.com/longhorn/longhorn/$LONGHORN_VERSION/deploy/longhorn.yaml

## Install k3s-server
curl -sfL https://get.k3s.io | sh -
# systemctl enable k3s-server.service
# systemctl start k3s-server.service

## Wait for the services to start and files to be created
sleep 60

## Tmp HTTP Server
chmod +x /tmp/serve
timeout 30m /tmp/serve -d /root &

## Get the token
TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

## Create worder config.yaml
# echo "server: https://$SERVER_IP:9345" >/root/config.yaml
# echo "token: $TOKEN" >>/root/config.yaml

cat <<EOF >/root/join-agent.sh
#!/bin/env bash
curl -sfL https://get.k3s.io | K3S_URL=https://$SERVER_IP:6443 K3S_TOKEN=$TOKEN sh -
EOF

## Copy kubeconfig and replace the server address
mkdir /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
sed -i "s/127.0.0.1/$SERVER_IP/g" /root/.kube/config
cp /root/.kube/config /root/kubeconfig

# It is expected that the worker script will be checking for the config file to be created
# it pollutes the server log file.
# remove the repeated errors.
# sed -i '/\[ERROR\] Route \/config.yaml could not be found/d' /root/cloud-init-run.log
## Delete this script
## rm -- "$0"
