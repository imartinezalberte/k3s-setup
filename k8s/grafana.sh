#!/bin/bash

absolute_path=$(readlink -f "$0")
script_path=$(dirname "$absolute_path")

. ${script_path}/../lib/utils.sh

ADDRESS=${1:-"0.0.0.0"}
KUBECONFIG=${2:-"/tmp/kubeconfig"}

username=$(kubectl --kubeconfig=$KUBECONFIG get secrets/loki-stack-grafana -n loki -o json | jq -r '.data."admin-username"' | base64 --decode)
password=$(kubectl --kubeconfig=$KUBECONFIG get secrets/loki-stack-grafana -n loki -o json | jq -r '.data."admin-password"' | base64 --decode)

display $GREEN "Here your credentials:\n\tusername: $username\n\tpassword: $password"

kubectl --kubeconfig=$KUBECONFIG port-forward svc/loki-stack-grafana 3000:80 -n loki --address ${ADDRESS}

