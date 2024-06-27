#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

IMG_NAME="ubuntu-24.04-minimal-cloudimg-amd64.img"
KVM_IMG_PATH="/var/lib/libvirt/images"

wget -P ${SCRIPT_DIR}/ https://cloud-images.ubuntu.com/minimal/releases/noble/release/${IMG_NAME}

sudo mv ${SCRIPT_DIR}/${IMG_NAME} ${KVM_IMG_PATH}/
sudo chown root ${KVM_IMG_PATH}/${IMG_NAME}
sudo chmod 0644 ${KVM_IMG_PATH}/${IMG_NAME}

exit 0
