#!/bin/env bash

# Install rke2-server
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service

# Wait for the services to start and files to be created
sleep 60

# Find the server IP
SERVER_IP=$(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep '.10$')

# Get the token
TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)

# Create config.yaml
echo "server: https://$SERVER_IP:9345" >/root/config.yaml
echo "token: $TOKEN" >>/root/config.yaml

# Copy kubeconfig and replace the server address
mkdir /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
sed -i "s/127.0.0.1/$SERVER_IP/g" /root/.kube/config
cp /root/.kube/config /root/kubeconfig
chmod +x /tmp/miniserve
/tmp/miniserve /root/.
# Delete this script
# rm -- "$0"
