#!/bin/bash

# create-sealed-secret.sh
# Script to create and seal Kubernetes secrets

set -e

# Function to display usage
usage() {
    echo "Usage: $0 <secret-name> <namespace> <key1=value1> [key2=value2] [...]"
    echo ""
    echo "Examples:"
    echo "  $0 db-secret devopsasg1 username=admin password=secret123"
    echo "  $0 api-secret default api-key=abc123 webhook-url=https://example.com"
    exit 1
}

# Check if minimum arguments are provided
if [ $# -lt 3 ]; then
    usage
fi

SECRET_NAME=$1
NAMESPACE=$2
shift 2

# Check if kubectl and kubeseal are available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo "❌ kubeseal is not installed"
    exit 1
fi

echo "🔐 Creating sealed secret: $SECRET_NAME in namespace: $NAMESPACE"

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Build the kubectl command with key-value pairs
KUBECTL_CMD="kubectl create secret generic $SECRET_NAME --namespace=$NAMESPACE --dry-run=client -o yaml"

for arg in "$@"; do
    if [[ $arg == *"="* ]]; then
        KUBECTL_CMD="$KUBECTL_CMD --from-literal=$arg"
    else
        echo "❌ Invalid format: $arg (expected key=value)"
        usage
    fi
done

echo "📝 Creating secret manifest..."
eval "$KUBECTL_CMD" > "${SECRET_NAME}-secret.yaml"

echo "🔒 Sealing the secret..."
kubeseal -f "${SECRET_NAME}-secret.yaml" -w "${SECRET_NAME}-sealed.yaml"

echo "🧹 Cleaning up temporary files..."
rm "${SECRET_NAME}-secret.yaml"

echo "✅ Sealed secret created: ${SECRET_NAME}-sealed.yaml"
echo ""
echo "📋 You can now:"
echo "1. Commit ${SECRET_NAME}-sealed.yaml to your Git repository"
echo "2. Apply it to your cluster: kubectl apply -f ${SECRET_NAME}-sealed.yaml"
echo "3. The sealed secret will be automatically decrypted by the controller"

# Optionally apply the sealed secret
read -p "🚀 Do you want to apply this sealed secret to the cluster now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl apply -f "${SECRET_NAME}-sealed.yaml"
    echo "✅ Sealed secret applied to cluster successfully!"
fi
