#!/bin/env bash

## Find the server IP
SERVER_IP=$(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep '.10$')

## Enable nginx compatibility with metallb on RKE2
# Set the file path
file_path="/var/lib/rancher/rke2/server/manifests"

# Extract the first 3 octets from $SERVER_IP
first_three_octets=$(echo "$SERVER_IP" | cut -d. -f1-3)

# Build the complete metallb IP address - .5 is the load balancer IP
load_balancer_ip="${first_three_octets}.5"

mkdir -p "$file_path"
touch $file_path/rke2-ingress-nginx-config.yaml

# Create the file with the desired content
cat <<EOF >"$file_path/rke2-ingress-nginx-config.yaml"
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

=====

## Install rke2-server
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service

## Wait for the services to start and files to be created
sleep 60

## Get the token
TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)

## Create config.yaml
echo "server: https://$SERVER_IP:9345" >/root/config.yaml
echo "token: $TOKEN" >>/root/config.yaml

## Copy kubeconfig and replace the server address
mkdir /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
sed -i "s/127.0.0.1/$SERVER_IP/g" /root/.kube/config
cp /root/.kube/config /root/kubeconfig

## Setup metallb

# If you’re using kube-proxy in IPVS mode, since Kubernetes v1.14.2 you have to enable strict ARP mode.

# see what changes would be made, returns nonzero returncode if different
/var/lib/rancher/rke2/bin/kubectl get configmap kube-proxy -n kube-system -o yaml |
  sed -e "s/strictARP: false/strictARP: true/" |
  /var/lib/rancher/rke2/bin/kubectl diff -f - -n kube-system

# actually apply the changes, returns nonzero returncode on errors only
/var/lib/rancher/rke2/bin/kubectl get configmap kube-proxy -n kube-system -o yaml |
  sed -e "s/strictARP: false/strictARP: true/" |
  /var/lib/rancher/rke2/bin/kubectl apply -f - -n kube-system

/var/lib/rancher/rke2/bin/kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

cat <<EOF >/tmp/metallb-namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF

/var/lib/rancher/rke2/bin/kubectl apply -f /tmp/metallb-namespace.yaml

## Tmp HTTP Server
chmod +x /tmp/miniserve
/tmp/miniserve /root/.
## Delete this script
## rm -- "$0"
