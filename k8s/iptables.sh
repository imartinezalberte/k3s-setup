#!/bin/bash

absolute_path=$(readlink -f "$0")
script_path=$(dirname "$absolute_path")

. ${script_path}/../lib/utils.sh

function usage {
  cat <<EOF
  This script is useful when you want to expose a port in a multipass machine to the outside in the given interface
  Parameters:
  - p[ort]: port of the mulitpass vm that you want to expose.
  - a[address]: address of the multipass vm that you want to expose.
  - i[nterface]: interface of the host machine that you want to expose.
EOF
}

while getopts ":hp:a:i:" opt; do
  case $opt in
    p) if ! is_number $OPTARG; then
      display $RED "You have to enter a port number between 1 and 65535" 
      exit 1
    fi
    MULTIPASS_VM_PORT=${OPTARG:-"6443"}
    ;;
    a) if ! is_ipv4_address $OPTARG; then
      display $RED "You have to enter an IPv4 address with the following format xxx.xxx.xxx.xxx"
      exit 1
    fi
    MULTIPASS_VM_IP=$OPTARG
    ;;
    i) if ! is_ipv4_name $OPTARG; then
      addresses=$(ip -4 addr show | grep -E "^[0-9]+" | awk -F' ' '{ print $2 }' | cut -d' ' -f2 | cut -d':' -f1)
      display $RED "You have to enter a valid ipv4 name. Those are the only ones available on your computer: $addresses"
      exit 1
    fi
    MACHINE_INTERFACE=$OPTARG
    ;;
    h) usage
    exit 0
    ;;
    /?) usage
    exit 1
    ;;
  esac
done

if [[ $UID -ne 0 ]]; then
  display $RED "You should use super user in this case"
  exit 1
fi

display $GREEN "MULTIPASS_VM_PORT=${MULTIPASS_VM_PORT}\nMULTIPASS_VM_IP=${MULTIPASS_VM_IP}\nMACHINE_INTERFACE=${MACHINE_INTERFACE}\n"

iptables -t nat -I PREROUTING 1 -i ${MACHINE_INTERFACE} -p tcp --dport ${MULTIPASS_VM_PORT} -j DNAT --to-destination ${MULTIPASS_VM_IP}
iptables -I FORWARD 1 -p tcp -d ${MULTIPASS_VM_IP} --dport ${MULTIPASS_VM_PORT} -j ACCEPT

