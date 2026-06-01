#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

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

echo "Running terraform init..."
terraform init

if [ ! -d ".terraform" ]; then
    echo "First time terraform init detected. Running validate and apply..."
    terraform validate
    terraform apply -auto-approve
else
    echo "Terraform already initialized. Skipping validate and apply."
fi
