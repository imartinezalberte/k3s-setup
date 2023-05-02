#!/bin/bash
#
# Dependencies
# - multipass: It is used to launch and delete VMs instances using KVM as virtualization tool.
# - k3sup: It's used to get into each VMs and install kubernetes environment, being one master and others standard workers.
# - jq, curl: Standard tools to download stuff from internet and parse json content.
#
# Exit codes:
# - 1: Error creating the private/public key to log into the VMs using k3sup or standard tools like ssh

. ./utils.sh

# ssh configurations
SSH_KEY_NAME=k3s_testing
PASSPHRASE=""

# Multipass configuration
MULTIPASS_ADDRESS='no' # Example: username@ip # Not working properly
MULTIPASS_CONFIG=${PWD}/multipass/config.yaml
MULTIPASS_VM_CPUS=1
MULTIPASS_VM_DISK='4G'
MULTIPASS_VM_MEMORY='4G'

# Kubernetes configuration
K_WORKER_PREFIX="node-"
K_SERVERS_N=2
K_SERVERS=("master-node")
KUBECONFIG=/tmp/kubeconfig

# usage function just returns a help text to explain what is the purpose of this script and the possible options that it offers.
function usage {
  cat <<EOF
  This script is gonna help you to build from scratch a kubernetes cluster the easy way.

  Parameters:
    -n <number> : specify the number of worker nodes that you want (a good number could be 2). By default 2 and the minimum value is 1.
    -k <ssh_key_name> : specify the name of the key file that you are going to use to authenticate with VMs created by multipass. Also used by k3sup. By default k3s_testing.
    -p <ssh_key_location> : specify the location of the multipass config. Here we are going to set the authorized keys for the multipass VMs. By default, $PWD/multipass/config.yaml
EOF
}

# Curl is used to download stuff from internet
which curl &> /dev/null || { display $PURPLE "Installing curl"; sudo apt-get install --yes curl; }
# Multipass is used to install the VMs
which multipass &> /dev/null || { display $PURPLE "Installing multipass"; sudo snap install multipass; }
# k3sup is used to install k3s in each VM once created
which k3sup > /dev/null 2>&1 || { display $PURPLE "Installing k3sup"; curl -sLS https://get.k3sup.dev | sh; sudo install k3sup /usr/local/bin; }
# We need jq to get the information needed from the json output of multipass
which jq > /dev/null 2>&1 || { display $PURPLE "Installing jq"; sudo apt-get install --yes jq; }

while getopts ":hn:k:c:a:" opt; do
  case $opt in
    n) if ! is_number $OPTARG; then 
      display $RED "The number of machines must be 1 or greater."; usage; exit 2
    else
      if [[ $OPTARG -lt 9 ]]; then
        K_SERVERS_N=$OPTARG
      fi
    fi
    ;;
    k) SSH_KEY_NAME=${OPTARG:-SSH_KEY_NAME}
    ;;
    c) MULTIPASS_CONFIG=${OPTARG:-MULTIPASS_CONFIG} 
    ;;
    a) MULTIPASS_ADDRESS=${OPTARG:-MULTIPASS_ADDRESS}
    ;;
    h) usage
    exit 0
    ;;
    \?) display $RED "Invalid option -$OPTARG" >&2
    exit 2
    ;;
  esac
done

# Adding the worker servers to the array
for((i=1; i<=$K_SERVERS_N; i++)); do K_SERVERS+=("${K_WORKER_PREFIX}$i"); done

display $BLUE "WORKER_NODES=$((${#K_SERVERS[@]}-1))\nSSH_KEY_NAME=${SSH_KEY_NAME}\nMULTIPASS_CONFIG=${MULTIPASS_CONFIG}\n"

rm -rf ~/.ssh/${SSH_KEY_NAME}{,.pub}
ssh-keygen -t rsa -C "`hostname`" -f ~/.ssh/${SSH_KEY_NAME} -P "${PASSPHRASE}"

if ! [[ -f ~/.ssh/${SSH_KEY_NAME} ]]; then display $RED "The private/public key was not created successfully"; exit 1; fi

mkdir -p $(dirname "${MULTIPASS_CONFIG}")
cat <<EOF > ${MULTIPASS_CONFIG}
ssh_authorized_keys:
  - $(cat ~/.ssh/${SSH_KEY_NAME}.pub)
EOF

test -f ${MULTIPASS_CONFIG} && display $GREEN "The multipass config file exists. Well done!"

for MULTIPASS_SERVER_NAME in ${K_SERVERS[@]}; do
  multipass launch --cpus ${MULTIPASS_VM_CPUS} \
                   --memory ${MULTIPASS_VM_MEMORY} \
                   --disk ${MULTIPASS_VM_DISK} \
                   --name ${MULTIPASS_SERVER_NAME} \
                   --cloud-init ${MULTIPASS_CONFIG}
done

# Another option would be: multipass ls | grep "${K_SERVERS[0]}" | awk '{print $3}'
# Or even: multipass ls | awk -v master="${K_SERVERS[0]}" '{ if ($1 == master) print $3 }']}
# Or: awk -v master="${K_SERVERS[0]}" '{ if ($1 == master) print $3 }']} < <(multipass ls)
MASTER_NODE_IP=$(multipass ls --format=json | jq -r --arg MASTER "${K_SERVERS[0]}" '.list[] | select(.name == $MASTER) | select(.state == "Running") | .ipv4[0]')

# Installing the k3s in master node
k3sup install --ip ${MASTER_NODE_IP} --user ubuntu --ssh-key ~/.ssh/${SSH_KEY_NAME} --k3s-extra-args "--cluster-init"

# Installing the k3s in worker node
while read -r WORKER_NODE_IP; do 
  k3sup join --ip ${WORKER_NODE_IP} --user ubuntu --ssh-key ~/.ssh/${SSH_KEY_NAME} --server-ip ${MASTER_NODE_IP} --server-user ubuntu
done < <(multipass ls | awk '{ if ($1 ~ /^node-[1-9]/) print $3 }')

mv kubeconfig $KUBECONFIG

./kubectl_install.sh

cat <<EOF
You can set alias so work in a smoother manner

alias k="kubectl --kubeconfig=$KUBECONFIG"
alias h="helm --kubeconfig=$KUBECONFIG"

Or try to set the environment variable KUBECONFIG to $KUBECONFIG

export KUBECONFIG=$KUBECONFIG
EOF

kubectl --kubeconfig=$KUBECONFIG wait --for=condition=Ready nodes --all --timeout=600s

./addons.sh $KUBECONFIG

# How to get admin-password and admin-user from grafana?
# kubectl get secrets/loki-stack-grafana -n loki -o yaml | yq '.data | (.admin-user, .admin-password)'
#
# One liner to discover the username and password of grafana user interface
# while read -r line; do echo $(base64 -d <<< $line); done < <(kubectl get secrets/loki-stack-grafana -n loki -o yaml | yq '.data | (.admin-user, .admin-password)')

