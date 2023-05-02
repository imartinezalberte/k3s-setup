#!/bin/bash

. ./utils.sh

MULTIPASS_VM_NAME=${1:-"docker-registry"}

# Multipass is used to install the VMs
which multipass &> /dev/null || { display $PURPLE "Installing multipass"; sudo snap install multipass; }
# We need jq to get the information needed from the json output of multipass
which jq > /dev/null 2>&1 || { display $PURPLE "Installing jq"; sudo apt-get install --yes jq; }

if [[ $(multipass ls --format=json | jq -r '.list[] | select(.state=="Running") | .name' | grep -c "$MULTIPASS_VM_NAME") -lt 1 ]]; then
  MULTIPASS_VM_CPUS=1
  MULTIPASS_VM_DISK='4G'
  MULTIPASS_VM_MEMORY='4G'
  MULTIPASS_CONFIG=${PWD}/multipass/docker_config.yaml

  SSH_KEY_NAME=docker_local

  display $GREEN "The instance $MULTIPASS_VM_NAME is not created. We are going to create one with the following attributes:\n\tcpus: ${MULTIPASS_VM_CPUS}\n\tdisk: ${MULTIPASS_VM_DISK}G\n\tmemory: ${MULTIPASS_VM_MEMORY}G"

  rm -rf ~/.ssh/${SSH_KEY_NAME}{,.pub}
  ssh-keygen -t rsa -C "`hostname`" -f ~/.ssh/${SSH_KEY_NAME} -P "${PASSPHRASE}"

  if ! [[ -f ~/.ssh/${SSH_KEY_NAME} ]]; then display $RED "The private/public key was not created successfully"; exit 1; fi

  mkdir -p $(dirname "${MULTIPASS_CONFIG}")
  cat <<EOF > ${MULTIPASS_CONFIG}
  ssh_authorized_keys:
    - $(cat ~/.ssh/${SSH_KEY_NAME}.pub)
EOF

  test -f ${MULTIPASS_CONFIG} && display $GREEN "The multipass config file exists. Well done!"

  multipass launch --disk ${MULTIPASS_VM_DISK} \
                   --memory ${MULTIPASS_VM_MEMORY} \
                   --cpus ${MULTIPASS_VM_CPUS} \
                   --cloud-init ${MULTIPASS_CONFIG} \
                   --name ${MULTIPASS_VM_NAME}
fi

display $GREEN "We are proceding to install docker on the Multipass VM instance ${MULTIPASS_VM_NAME}"

# It would be preferable to set-up docker in the VM using ansible, but for the sake of simplicity and trying to avoid adding "unnecessary" dependencies
multipass exec ${MULTIPASS_VM_NAME} /bin/bash <<EOF
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch="\$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "\$(. /etc/os-release && echo "\$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
newgrp docker
EOF

display $GREEN "If you have docker locally installed, you can add this ip to the context, you can connect directly to the machine using ssh and without opening an insecure port"
