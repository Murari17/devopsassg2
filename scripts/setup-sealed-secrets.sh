#!/bin/bash

# setup-sealed-secrets.sh
# Script to install and configure Sealed Secrets Controller

set -e

echo "🔐 Setting up Sealed Secrets Controller..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if kubeseal is available
if ! command -v kubeseal &> /dev/null; then
    echo "📦 Installing kubeseal..."
    
    # Detect OS
    OS="linux"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
    fi
    
    # Download and install kubeseal
    KUBESEAL_VERSION="v0.24.0"
    wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-0.24.0-${OS}-amd64.tar.gz"
    tar -xvzf "kubeseal-0.24.0-${OS}-amd64.tar.gz"
    sudo install -m 755 kubeseal /usr/local/bin/kubeseal
    rm kubeseal "kubeseal-0.24.0-${OS}-amd64.tar.gz"
    
    echo "✅ kubeseal installed successfully"
fi

# Install Sealed Secrets Controller
echo "🚀 Installing Sealed Secrets Controller to Kubernetes cluster..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

echo "⏳ Waiting for Sealed Secrets Controller to be ready..."
kubectl wait --for=condition=Available deployment/sealed-secrets-controller -n kube-system --timeout=300s

echo "✅ Sealed Secrets Controller is ready!"

# Fetch the public key
echo "🔑 Fetching public key for sealing secrets..."
kubeseal --fetch-cert > sealed-secrets-public.pem

echo "📋 Public key saved to: sealed-secrets-public.pem"
echo "🎉 Sealed Secrets setup complete!"

echo ""
echo "Next steps:"
echo "1. Use 'kubeseal' to encrypt your secrets"
echo "2. Store the sealed secrets in your Git repository"
echo "3. Apply sealed secrets to your cluster"
echo ""
echo "Example usage:"
echo "  kubectl create secret generic mysecret --dry-run=client --from-literal=key=value -o yaml | kubeseal -o yaml > mysealedsecret.yaml"
