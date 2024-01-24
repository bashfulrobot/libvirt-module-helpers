#!/bin/env bash

# Get the name of the primary Ethernet interface
INTERFACE=$(ip route get 1 | awk '{print $5}')

# Get the IP address of the primary Ethernet interface
IP_ADDRESS=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Change the last octet to .10
IP_ADDRESS=$(echo $IP_ADDRESS | awk -F. -v OFS=. '{$4="10"; print}')

# Install rke2-server
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
systemctl enable rke2-server.service
mkdir -p /etc/rancher/rke2/
wget -O /etc/rancher/rke2/config.yaml http://$IP_ADDRESS:8080/config.yaml
systemctl start rke2-server.service

# Delete this script
# rm -- "$0"
