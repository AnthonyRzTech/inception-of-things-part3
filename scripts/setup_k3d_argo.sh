#!/bin/bash

# Ensure the script is run as root
if [ $(whoami) != root ]; then
    sudo bash "$0"
    exit
fi

# Dependencies of the 3rd part

# Add Docker's official GPG key:
apt-get update -y
apt-get install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    tee /etc/apt/sources.list.d/docker.list >/dev/null
apt-get update -y

# Install docker
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Install k3d
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.0 bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
mv kubectl /usr/local/bin
chmod +x /usr/local/bin/kubectl

# Setup k3d and kubectl
if ! command -v k3d &>/dev/null; then
    echo "k3d could not be found"
    exit 1
fi
if ! command -v kubectl &>/dev/null; then
    echo "kubectl could not be found"
    exit 1
fi

if [ -d /vagrant ]; then
    cd /vagrant
fi

k3d cluster create --port 8888:8888

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

sleep 10

kubectl wait --timeout=200s --for=condition=Ready -n argocd --all pod

echo "ArgoCD password:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
echo

# Create the git credentials secret
kubectl create secret generic git-credentials \
  --from-literal=username='<AnthonyRzTech>' \
  --from-literal=password='<>' \
  -n argocd

# Port forward setup
{
    while true; do
        kubectl port-forward service/argocd-server --address 0.0.0.0 -n argocd 8080:443 &>/dev/null
    done
} &

kubectl apply -f confs/argocd_app.yaml -n argocd
kubectl apply -f confs/deploy.yaml -n dev

sleep 60

