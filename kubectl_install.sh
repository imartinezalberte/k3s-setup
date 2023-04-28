#!/bin/bash

which kubectl &> /dev/null && { echo -e "\033[0;32mkubectl is already installed\033[0m"; exit 0; }

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

rm kubectl
