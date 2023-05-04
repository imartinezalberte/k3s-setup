#!/bin/bash

absolute_path=$(readlink -f "$0")
script_path=$(dirname "$absolute_path")

. ${script_path}/../lib/utils.sh

MULTIPASS_VM_NAME=${1:-"docker-registry"}
DOCKER_CONTEXT_NAME=${2:-"docker-multipass"}

# Multipass is used to install the VMs
which multipass &> /dev/null || { display $PURPLE "Installing multipass"; sudo snap install multipass; }
# We need jq to get the information needed from the json output of multipass
which jq > /dev/null 2>&1 || { display $PURPLE "Installing jq"; sudo apt-get install --yes jq; }

if [[ $(multipass ls --format=json | jq -r '.list[] | select(.state=="Running") | .name' | grep -c "$MULTIPASS_VM_NAME") -lt 1 ]]; then
  MULTIPASS_VM_CPUS=1
  MULTIPASS_VM_DISK='8G'
  MULTIPASS_VM_MEMORY='4G'
  MULTIPASS_CONFIG=${script_path}/multipass/docker_config.yaml

  SSH_KEY_NAME=docker_local

  display $GREEN "The instance $MULTIPASS_VM_NAME is not created. We are going to create one with the following attributes:\n\tcpus: ${MULTIPASS_VM_CPUS}\n\tdisk: ${MULTIPASS_VM_DISK}B\n\tmemory: ${MULTIPASS_VM_MEMORY}B"

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
multipass exec ${MULTIPASS_VM_NAME} which docker || multipass exec ${MULTIPASS_VM_NAME} /bin/bash <<EOF
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

MULTIPASS_IP=$(multipass ls --format=json | jq -r --arg MULTIPASS_VM_NAME "${MULTIPASS_VM_NAME}" '.list[] | select(.state=="Running" and .name==$MULTIPASS_VM_NAME) | .ipv4[0]')

DOCKER_HOST="ssh://ubuntu@${MULTIPASS_IP}"

which docker &> /dev/null || {
  display $GREEN "Do you want to install docker client on your computer to connect to the Multipass VM?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes) display $GREEN "Installing docker client on host machine"
      . ${script_path}/docker-client.sh
      break
      ;;
      No ) display $RED "Skipping step of install docker client on host machine"
      break
      ;;
    esac
  done
}

which docker &> /dev/null && {
  docker context rm -f ${DOCKER_CONTEXT_NAME} &> /dev/null;
  docker context create ${DOCKER_CONTEXT_NAME} --docker "host=${DOCKER_HOST}" &> /dev/null;
  docker context use ${DOCKER_CONTEXT_NAME} &> /dev/null;
  test $(cat ~/.ssh/config | grep -c "Host ${MULTIPASS_IP}$") -eq 0 && cat <<EOF >> ~/.ssh/config
Host ${MULTIPASS_IP}
  StrictHostKeyChecking no
EOF
  docker version;
}

