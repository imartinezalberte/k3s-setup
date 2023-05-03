#!/bin/bash
# 
# The First parameter is the kubeconfig path

. ../lib/utils.sh

if [[ -z $KUBECONFIG ]]; then
  KUBECONFIG=${1:-$HOME/.kube/config}
fi

HELM_REPOS=(
  "grafana"
  "https://grafana.github.io/helm-charts"
  # Add more entries here if necessary
)

# Installing helm
which helm &> /dev/null || { display $GREEN "Installing helm"; curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }

for((i=0; i<=${#HELM_REPOS[@]}; i+=2)); do
  helm repo add "${HELM_REPOS[$i]}" "${HELM_REPOS[$((i+1))]}"
done

helm install --values ./values.yaml loki-stack grafana/loki-stack -n loki --create-namespace

