#!/bin/bash
# 
# The First parameter is the kubeconfig path

## Colors
NO_COLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BROWN='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'

if [[ -z $KUBECONFIG ]]; then
  KUBECONFIG=${1:-$HOME/.kube/config}
fi

HELM_REPOS=(
  "grafana"
  "https://grafana.github.io/helm-charts"
  # Add more entries here if necessary
)

# display function echo the text with the desired color.
# 
# Arguments:
#   - First is the color
#   - Second and so on is the text that you want to display
function display {
  if [[ $# -lt 2 ]]; then return 0; fi
  color=$1
  text=${@:2}

  echo -e "${color}${text}${NO_COLOR}"
}

# Installing helm
which helm &> /dev/null || { display $GREEN "Installing helm"; curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }

for((i=0; i<=${#HELM_REPOS[@]}; i+=2)); do
  helm repo add "${HELM_REPOS[$i]}" "${HELM_REPOS[$((i+1))]}"
done

helm --kubeconfig=$KUBECONFIG install --values ./values.yaml loki-stack grafana/loki-stack -n loki --create-namespace

