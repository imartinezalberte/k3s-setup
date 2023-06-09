#!/bin/bash
#
# Dependencies
# - multipass: It is used to launch and delete VMs instances using KVM as virtualization tool.
# - k3sup: It's used to get into each VMs and install kubernetes environment, being one master and others standard workers.
# - jq, curl: Standard tools to download stuff from internet and parse json content.
#
# Exit codes:
# - 1: Error creating the private/public key to log into the VMs using k3sup or standard tools like ssh

absolute_path=$(readlink -f "$0")
script_path=$(dirname "$absolute_path")

. ${script_path}/../lib/utils.sh

# Curl is used to download stuff from internet
which curl &> /dev/null || { display $PURPLE "Installing curl"; sudo apt-get install --yes curl; }
# Multipass is used to install the VMs
which multipass &> /dev/null || { display $PURPLE "Installing multipass"; sudo snap install multipass; }
# k3sup is used to install k3s in each VM once created
which k3sup > /dev/null 2>&1 || { display $PURPLE "Installing k3sup"; curl -sLS https://get.k3sup.dev | sh; sudo install k3sup /usr/local/bin; }
# We need jq to get the information needed from the json output of multipass
which jq > /dev/null 2>&1 || { display $PURPLE "Installing jq"; sudo apt-get install --yes jq; }
# We need yq to get the information needed from configuration
which yq > /dev/null 2>&1 || { display $PURPLE "Installing yq"; wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O ./yq && sudo install -o root -g root -m 0755 ./yq /usr/local/bin/yq && rm ./yq; }

CONFIG_FILE=${K_CONFIG_FILE:-"${script_path}/config.yaml"}
DEBUGGING="false"

function expr_or_default {
  if [[ $# -ne 2 ]]; then return 0; fi
  if ! [[ -f ${CONFIG_FILE} ]]; then return $2; fi
  query=$1
  echo $(yq $query ${CONFIG_FILE})
}

# ssh configurations
SSH_KEY_NAME=$(expr_or_default '.ssh.name' "k3s_testing")
SSH_KEY_PASSPHRASE=$(expr_or_default '.ssh.passphrase' "")

# Multipass VM instance name for the docker VM
REGISTRY_NAME=$(expr_or_default '.registry.name' "docker-registry")

# Multipass configuration
MULTIPASS_CONFIG=$(expr_or_default '.multipass.config_file' "${script_path}/multipass/config.yaml")
MULTIPASS_VM_CPUS=$(expr_or_default '.multipass.vm.cpus' 1)
MULTIPASS_VM_DISK=$(expr_or_default '.multipass.vm.disk' '4G')
MULTIPASS_VM_MEMORY=$(expr_or_default '.multipass.vm.memory' '2G')

# Kubernetes configuration
K_WORKER_PREFIX=$(expr_or_default '.kubernetes.worker_prefix' "node-")
K_SERVERS_N=$(expr_or_default '.kubernetes.servers' 2)
K_REGISTRY_HOSTNAME=$(expr_or_default '.kubernetes.registry_hostname' "docker.es")
K_SERVERS_N=$(expr_or_default '.kubernetes.servers' 2)
K_SERVERS=("master-node")
K_KUBECONFIG=/tmp/kubeconfig

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

while getopts ":hn:k:c:a:v" opt; do
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
    v) DEBUGGING="true"
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

# Some verbose information
if [[ "$DEBUGGING" == "true" ]]; then
  for i in ${!SSH_KEY_*}; do display $BLUE "$i=${!i}"; done
  for i in ${!MULTIPASS_*}; do display $BLUE "$i=${!i}"; done
  for i in ${!K_*}; do display $BLUE "$i=${!i}"; done
fi

rm -rf ~/.ssh/${SSH_KEY_NAME}{,.pub}
ssh-keygen -t rsa -C "`hostname`" -f ~/.ssh/${SSH_KEY_NAME} -P "${SSH_KEY_PASSPHRASE}"

if ! [[ -f ~/.ssh/${SSH_KEY_NAME} ]]; then display $RED "The private/public key was not created successfully"; exit 1; fi

mkdir -p $(dirname "${MULTIPASS_CONFIG}")
cat <<EOF > ${MULTIPASS_CONFIG}
ssh_authorized_keys:
  - $(cat ~/.ssh/${SSH_KEY_NAME}.pub)
EOF

test -f ${MULTIPASS_CONFIG} && display $GREEN "The multipass config file exists. Well done!"

display $GREEN "We are going to install the docker registry in a multipass VM"

. ${script_path}/../docker/docker-registry.sh ${REGISTRY_NAME}

DOCKER_REGISTRY_IP=$(multipass ls --format=json | jq -r --arg REGISTRY_NAME "${REGISTRY_NAME}" '.list[] | select(.state=="Running" and .name==$REGISTRY_NAME) | .ipv4[0]')

for MULTIPASS_SERVER_NAME in ${K_SERVERS[@]}; do
  multipass launch --cpus ${MULTIPASS_VM_CPUS} \
                   --memory ${MULTIPASS_VM_MEMORY} \
                   --disk ${MULTIPASS_VM_DISK} \
                   --name ${MULTIPASS_SERVER_NAME} \
                   --cloud-init ${MULTIPASS_CONFIG}
  multipass exec ${MULTIPASS_SERVER_NAME} -- sudo /bin/bash <<EOF
mkdir --parents /etc/rancher/k3s/
echo -e "mirrors:\n  \"${K_REGISTRY_HOSTNAME}\":\n    endpoint:\n    - \"http://${DOCKER_REGISTRY_IP}:5000\"" > /etc/rancher/k3s/registries.yaml
EOF
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
done < <(multipass ls | grep -E "$K_WORKER_PREFIX[1-9]" | awk '{print $3}')

mv kubeconfig $K_KUBECONFIG

. ${script_path}/kubectl_install.sh

cat <<EOF
You can set alias so work in a smoother manner

alias k="kubectl --kubeconfig=$K_KUBECONFIG"
alias h="helm --kubeconfig=$K_KUBECONFIG"

Or try to set the environment variable KUBECONFIG to $K_KUBECONFIG

export KUBECONFIG=$K_KUBECONFIG
EOF

kubectl --kubeconfig=$K_KUBECONFIG wait --for=condition=Ready nodes --all --timeout=600s

. ${script_path}/addons.sh $K_KUBECONFIG

kubectl --kubeconfig=/tmp/kubeconfig wait --for=condition=Available deployment.apps/loki-stack-grafana -n loki --timeout=60s

. ${script_path}/grafana.sh

# How to get admin-password and admin-user from grafana?
# kubectl get secrets/loki-stack-grafana -n loki -o yaml | yq '.data | (.admin-user, .admin-password)'
#
# One liner to discover the username and password of grafana user interface
# while read -r line; do echo $(base64 -d <<< $line); done < <(kubectl get secrets/loki-stack-grafana -n loki -o yaml | yq '.data | (.admin-user, .admin-password)')

# If you want to display all the docker registries, then use:
# sudo crictl info | jq '.config.registry.mirrors | keys'
