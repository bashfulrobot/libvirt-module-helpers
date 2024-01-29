#/usr/bin/env bash

# https://blog.devgenius.io/cilium-installation-tips-17a870fdc4f2

helm repo add cilium https://helm.cilium.io/

helm install cilium cilium/cilium --version 1.13.2 -n kube-system \
    --set ipam.operator.clusterPoolIPv4PodCIDR=10.244.0.0/16 \
    --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
    --set ipv4.enabled=true \
    --set loadBalancer.mode=dsr \
    --set kubeProxyReplacement=strict \
    --set tunnel=disabled \
    --set autoDirectNodeRoutes=true
