#!/bin/env bash

# Get the name of the primary Ethernet interface
INTERFACE=$(ip route get 1 | awk '{print $5}')

# Get the IP address of the primary Ethernet interface
IP_ADDRESS=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Change the last octet to .10
IP_ADDRESS=$(echo $IP_ADDRESS | awk -F. -v OFS=. '{$4="10"; print}')

# Wait for the config.yaml file to exist on controller
while ! curl --output /dev/null --silent --head --fail "http://$IP_ADDRESS:8080/config.yaml"; do
    # echo "Waiting for rke confile file to exist..."
    sleep 5
done

echo "File exists. Continuing with script..."

# Install k3s-server
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" sh -
# systemctl enable k3s-server.service
mkdir -p /etc/rancher/k3s/
wget -O /etc/rancher/k3s/config.yaml http://$IP_ADDRESS:8080/config.yaml
# systemctl start k3s-server.service

# Delete this script
# rm -- "$0"
