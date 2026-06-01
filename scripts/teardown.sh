#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command '$1' not found. Install it and retry."
    exit 2
  }
}

require_cmd terraform

echo "Changing to terraform directory: $TERRAFORM_DIR"
cd "$TERRAFORM_DIR"

# secrets.auto.tfvars MUST exist
if [ ! -f "secrets.auto.tfvars" ]; then
    echo "Error: secrets.auto.tfvars not found in $TERRAFORM_DIR"
    echo "Please provide secrets.auto.tfvars before running this script."
    exit 1
fi

echo "Initializing Terraform (no k8s/helm cleanup)..."
terraform init -input=false

echo "Performing abrupt Terraform destroy..."
terraform destroy -auto-approve

if command -v kubectl >/dev/null 2>&1; then
  echo "Resetting kubectl current-context (if set)..."
  kubectl config unset current-context || true
fi

echo "Teardown complete."
