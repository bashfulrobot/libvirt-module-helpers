#!/bin/env bash

# Metallb Version
METALLB_VERSION="v0.13.12"
LONGHORN_VERSION="v1.5.3"

## Find the server IP
SERVER_IP=$(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep '.10$')

## Enable nginx compatibility with metallb on RKE2
# Set the file path
# file_path="/var/lib/rancher/rke2/server/manifests"

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

mkdir -p /var/lib/rancher/rke2/server/manifests

mkdir -p /etc/rancher/rke2/
# touch /etc/rancher/rke2/config.yaml

# Patch Ingress Nginx for metallb
cat <<EOF >"/var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx-config.yaml"
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |-
    controller:
      config:
        use-forwarded-headers: "true"
        enable-real-ip: "true"
      publishService:
        enabled: true
      service:
        enabled: true
        type: LoadBalancer
        external:
          enabled: true
        externalTrafficPolicy: Local
        annotations:
          metallb.universe.tf/loadBalancerIPs: $load_balancer_ip ## Configure static load balancer IP
EOF

# Get Metallb manifest
wget -O /var/lib/rancher/rke2/server/manifests/metallb-native.yaml https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml

# Configure Metallb
cat <<EOF >/var/lib/rancher/rke2/server/manifests/metallb-config.yaml
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

# Wget the Longhorn manifest
wget -O /var/lib/rancher/rke2/server/manifests/longhorn.yaml https://raw.githubusercontent.com/longhorn/longhorn/$LONGHORN_VERSION/deploy/longhorn.yaml

## Install rke2-server
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service

## Wait for the services to start and files to be created
sleep 60

## Tmp HTTP Server
chmod +x /tmp/miniserve
timeout 30m /tmp/miniserve /root/.

## Get the token
TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)

## Create worder config.yaml
# echo "server: https://$SERVER_IP:9345" >/root/config.yaml
# echo "token: $TOKEN" >>/root/config.yaml

cat <<EOF >/root/config.yaml
server: https://$SERVER_IP:9345
token: $TOKEN
EOF

## Copy kubeconfig and replace the server address
mkdir /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
sed -i "s/127.0.0.1/$SERVER_IP/g" /root/.kube/config
cp /root/.kube/config /root/kubeconfig

# It is expected that the worker script will be checking for the config file to be created
# it pollutes the server log file.
# remove the repeated errors.
sed -i '/\[ERROR\] Route \/config.yaml could not be found/d' /home/root/cloud-init-run.log
## Delete this script
## rm -- "$0"
