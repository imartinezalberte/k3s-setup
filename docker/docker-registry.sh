#!/bin/bash

absolute_path=$(readlink -f "$0")
script_path=$(dirname "$absolute_path")

. ${script_path}/../lib/utils.sh

MULTIPASS_VM_NAME=${1:-"docker-registry"}

. ${script_path}/../docker/docker.sh ${MULTIPASS_VM_NAME}

multipass exec ${MULTIPASS_VM_NAME} -- /bin/bash <<EOF
which jq &> /dev/null || { sudo apt-get install --yes jq; }
if [[ \$(docker container ls -a --format="{{json .}}" | jq -r 'select(.Names=="registry" and .State=="running") | .Names' | grep -c registry) -eq 0 ]]; then
  docker rm -f registry
  docker run -d -p 5000:5000 \
    --restart=always \
    -v /mnt/registry:/var/lib/registry \
    --name registry registry:2
fi
EOF

MULTIPASS_IP=$(multipass ls --format=json | jq -r --arg MULTIPASS_VM_NAME "${MULTIPASS_VM_NAME}" '.list[] | select(.state=="Running" and .name==$MULTIPASS_VM_NAME) | .ipv4[0]')

display $GREEN "Now you have to tag the docker images as ${MULTIPASS_IP}:5000/<docker-image-name>"

