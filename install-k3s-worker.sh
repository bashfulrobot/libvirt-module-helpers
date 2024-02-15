#!/bin/env bash

# Get the name of the primary Ethernet interface
INTERFACE=$(ip route get 1 | awk '{print $5}')

# Get the IP address of the primary Ethernet interface
IP_ADDRESS=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Change the last octet to .10
IP_ADDRESS=$(echo $IP_ADDRESS | awk -F. -v OFS=. '{$4="10"; print}')

# Wait for the join-agent.sh file to exist on controller
while ! curl --output /dev/null --silent --head --fail "http://$IP_ADDRESS:8080/join-agent.sh"; do
    # echo "Waiting for rke confile file to exist..."
    sleep 5
done

echo "File exists. Continuing with script..."

wget -O /tmp/join-agent.sh http://$IP_ADDRESS:8080/join-agent.sh

# Install k3s-server
chmod +x /tmp/join-agent.sh
/tmp/join-agent.sh
# systemctl enable k3s-server.service

# systemctl start k3s-server.service

# Delete this script
# rm -- "$0"
