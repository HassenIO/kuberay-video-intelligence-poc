#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
K8S_DIR="$PROJECT_ROOT/k8s"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command '$1' not found. Install it and retry."
    exit 2
  }
}

require_cmd terraform
require_cmd doctl
require_cmd kubectl
require_cmd helm

# ---------------------------
# Setup and run Terraform
# ---------------------------

cd "$TERRAFORM_DIR"

# secrets.auto.tfvars MUST exists or it will not work
if [ ! -f "secrets.auto.tfvars" ]; then
    echo "Error: secrets.auto.tfvars not found in $TERRAFORM_DIR"
    echo "Please create the secrets.auto.tfvars file before running this script."
    exit 1
fi

echo "Running terraform..."
terraform init
terraform validate
terraform plan -out=tfplan

if terraform show -no-color tfplan | grep -q 'No changes'; then
    echo "Terraform plan indicates no changes. Skipping apply."
else
    echo "Terraform plan indicates changes. Applying..."
    terraform apply -auto-approve tfplan
fi
rm -f tfplan

# ---------------------------
# Setup and run Kubernetes
# ---------------------------

echo "Extracting DigitalOcean API token..."
if [ -z "${DOCTL_ACCESS_TOKEN:-}" ]; then
    DOCTL_ACCESS_TOKEN=$(sed -nE 's/^[[:space:]]*do_token[[:space:]]*=[[:space:]]*"([^"]*)"[[:space:]]*$/\1/p' secrets.auto.tfvars)
fi

if [ -z "${DOCTL_ACCESS_TOKEN:-}" ]; then
    echo "Error: DOCTL_ACCESS_TOKEN is not set and do_token was not found in secrets.auto.tfvars"
    exit 1
fi

echo "Authenticating doctl..."
doctl auth init --access-token "$DOCTL_ACCESS_TOKEN"

echo "Retrieving DigitalOcean cluster ID from Terraform outputs..."
CLUSTER_ID=$(terraform output -raw cluster_id)

if [ -z "$CLUSTER_ID" ]; then
    echo "Error: Terraform output cluster_id is empty. Make sure terraform apply created the cluster and output exists."
    exit 1
fi

echo "Saving kubeconfig for cluster $CLUSTER_ID..."
doctl kubernetes cluster kubeconfig save "$CLUSTER_ID"

cd "$K8S_DIR"

echo "Installing or upgrading KubeRay operator..."
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ || true
helm repo update
helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system \
  --create-namespace \
  --version 1.6.0 \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=1Gi \
  --set resources.requests.cpu=200m \
  --set resources.requests.memory=512Mi

echo "Waiting for KubeRay operator to be ready..."
kubectl wait \
  --for=condition=available \
  --timeout=300s \
  deployment/kuberay-operator -n kuberay-system

echo "Creating ray-system namespace..."
kubectl create namespace ray-system --dry-run=client -o yaml | kubectl apply -f -

echo "Syncing serve_app.py into k8s directory..."
cp "$PROJECT_ROOT/serve_app.py" "$K8S_DIR/serve_app.py"

echo "Ensuring ConfigMap video-intelligence-app will be recreated in ray-system..."
kubectl delete configmap video-intelligence-app -n ray-system --ignore-not-found || true

echo "Applying RayService manifest via kustomize..."
cd "$PROJECT_ROOT"
kubectl apply -k "$K8S_DIR"

echo "Waiting for RayService pods to become ready..."
if ! kubectl wait --for=condition=ready pod -l ray.io/service=video-intelligence-service -n ray-system --timeout=300s; then
  echo "RayService pods failed to become ready within 5 minutes."
  kubectl get pods -n ray-system -o wide
  kubectl get events -n ray-system --sort-by='.lastTimestamp' | tail -40
  kubectl describe rayservice video-intelligence-service -n ray-system || true
  exit 1
fi

echo "RayService pods are ready."
