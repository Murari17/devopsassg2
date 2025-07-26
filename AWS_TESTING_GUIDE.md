# 🧪 AWS DevSecOps Testing Guide

## Overview
This guide walks you through testing the complete DevSecOps pipeline on AWS, including infrastructure deployment, security scanning, and Kubernetes operations.

## 📋 Prerequisites Verified
✅ AWS CLI: v2.27.58  
✅ Terraform: v1.12.2  
✅ kubectl: v1.33.3  
✅ AWS Account: 597047871118 (user: murari)

## 🔧 Step 1: Local Security Testing

### Run Security Scans Locally
```powershell
# Make scripts executable (if on Linux/Mac)
# chmod +x scripts/*.sh

# Run comprehensive security scan
.\scripts\security-scan.sh

# Or run individual security tools
terraform fmt -check -recursive
terraform validate
```

### Test Docker Build and Security
```powershell
# Build the application image
docker build -t devopsasg1-app:test ./app

# Test the application locally
docker run -d -p 8080:8080 --name test-app devopsasg1-app:test

# Check if app is running
curl http://localhost:8080

# Clean up
docker stop test-app
docker rm test-app
```

## 🏗️ Step 2: Infrastructure Testing

### 2.1 Create S3 Bucket for Terraform State
```powershell
# Create unique bucket name
$bucketName = "terraform-bucket-$(Get-Random)"
aws s3 mb s3://$bucketName --region ap-south-1

# Enable versioning
aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled

# Update terraform.tfvars with the new bucket name
# bucket_name = "$bucketName"
```

### 2.2 Initialize and Plan Terraform
```powershell
# Initialize Terraform
terraform init `
  -backend-config="bucket=$bucketName" `
  -backend-config="key=terraform.tfstate" `
  -backend-config="region=ap-south-1"

# Validate configuration
terraform validate

# Create execution plan
terraform plan -var-file="terraform.tfvars"

# Review the plan output for:
# - VPC and networking resources
# - EKS cluster configuration
# - Security groups and IAM roles
# - EC2 instance setup
```

### 2.3 Deploy Infrastructure (Optional - for full testing)
```powershell
# Apply infrastructure (WARNING: This creates real AWS resources and incurs costs)
terraform apply -var-file="terraform.tfvars" -auto-approve

# Wait for EKS cluster to be ready (10-15 minutes)
```

## 🔐 Step 3: Test Sealed Secrets

### 3.1 Install Sealed Secrets Controller (after EKS is ready)
```powershell
# Update kubeconfig for EKS
aws eks update-kubeconfig --region ap-south-1 --name devopsasg1-eks-cluster

# Install Sealed Secrets Controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/sealed-secrets-controller -n kube-system --timeout=300s
```

### 3.2 Test Secret Sealing
```powershell
# Install kubeseal (Windows)
$kubesealUrl = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-windows-amd64.tar.gz"
Invoke-WebRequest -Uri $kubesealUrl -OutFile "kubeseal.tar.gz"
tar -xzf kubeseal.tar.gz
Move-Item kubeseal.exe C:\Windows\System32\

# Create a test secret
kubectl create secret generic test-secret `
  --from-literal=username=testuser `
  --from-literal=password=testpass `
  --namespace=default `
  --dry-run=client -o yaml > test-secret.yaml

# Seal the secret
kubeseal -f test-secret.yaml -w test-sealed-secret.yaml

# Apply the sealed secret
kubectl apply -f test-sealed-secret.yaml

# Verify the secret was created
kubectl get secret test-secret -o yaml

# Clean up
kubectl delete sealedsecret test-secret
Remove-Item test-secret.yaml, test-sealed-secret.yaml
```

## 🚀 Step 4: Application Deployment Testing

### 4.1 Deploy Application to EKS
```powershell
# Create namespace
kubectl create namespace devopsasg1

# Create sealed secrets for the application
kubectl create secret generic db-secret `
  --from-literal=username=admin `
  --from-literal=password=securepass123 `
  --namespace=devopsasg1 `
  --dry-run=client -o yaml > db-secret.yaml

kubeseal -f db-secret.yaml -w db-sealed-secret.yaml
kubectl apply -f db-sealed-secret.yaml

# Deploy the application
kubectl apply -f k8s/deployment.yaml

# Check deployment status
kubectl get pods -n devopsasg1
kubectl get svc -n devopsasg1

# Wait for LoadBalancer to be ready
kubectl get svc devopsasg1-app -n devopsasg1 -w
```

### 4.2 Test Application Access
```powershell
# Get the LoadBalancer URL
$loadBalancerUrl = kubectl get svc devopsasg1-app -n devopsasg1 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host "Application URL: http://$loadBalancerUrl"

# Test the application
curl "http://$loadBalancerUrl"

# Test health endpoint
curl "http://$loadBalancerUrl/health"
```

## 🔄 Step 5: GitHub Actions Pipeline Testing

### 5.1 Configure GitHub Secrets
Go to: https://github.com/Murari17/devopsassg2/settings/secrets/actions

Add these secrets:
```
AWS_ACCESS_KEY_ID=AIDAYWAWTQ2HNXVWPCO3T
AWS_SECRET_ACCESS_KEY=<your-secret-key>
TF_STATE_BUCKET=<your-bucket-name>
AWS_ACCOUNT_ID=597047871118
DB_USERNAME=admin
DB_PASSWORD=securepass123
```

### 5.2 Trigger Pipeline
```powershell
# Make a small change to trigger the pipeline
echo "# Pipeline test $(Get-Date)" >> README.md
git add README.md
git commit -m "Test: Trigger DevSecOps pipeline"
git push origin main
```

### 5.3 Monitor Pipeline
- Visit: https://github.com/Murari17/devopsassg2/actions
- Watch the pipeline stages:
  1. ✅ Security scanning (tfsec, Trivy)
  2. ✅ Build and push to ECR
  3. ✅ Infrastructure deployment
  4. ✅ Kubernetes deployment with sealed secrets

## 🔍 Step 6: Security Testing Validation

### 6.1 Test Security Scanning
```powershell
# Introduce a security issue to test scanning
# Add this to main.tf temporarily:
resource "aws_s3_bucket_public_access_block" "test" {
  bucket = "public-bucket"
  
  block_public_acls       = false  # This should trigger tfsec
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Run tfsec to see security issues
tfsec .

# Remove the test resource after validation
```

### 6.2 Test Container Vulnerability Scanning
```powershell
# Build image with known vulnerable base
# Modify app/Dockerfile temporarily:
FROM nginx:1.10-alpine  # Old version with vulnerabilities

# Build and scan
docker build -t vulnerable-test ./app
trivy image vulnerable-test

# Restore secure Dockerfile after testing
```

## 📊 Step 7: Monitoring and Observability

### 7.1 Check EKS Cluster Health
```powershell
# Cluster info
kubectl cluster-info

# Node status
kubectl get nodes

# System pods
kubectl get pods -n kube-system

# Application pods
kubectl get pods -n devopsasg1

# View logs
kubectl logs -f deployment/devopsasg1-app -n devopsasg1
```

### 7.2 AWS Resource Monitoring
```powershell
# Check EKS cluster status
aws eks describe-cluster --name devopsasg1-eks-cluster --region ap-south-1

# Check EC2 instances
aws ec2 describe-instances --region ap-south-1 --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]'

# Check VPC
aws ec2 describe-vpcs --region ap-south-1 --query 'Vpcs[*].[VpcId,State,Tags[?Key==`Name`].Value|[0]]'
```

## 🧹 Step 8: Cleanup (Important!)

### 8.1 Destroy Infrastructure (To avoid charges)
```powershell
# Destroy all resources
terraform destroy -var-file="terraform.tfvars" -auto-approve

# Delete S3 bucket (after emptying)
aws s3 rm s3://$bucketName --recursive
aws s3 rb s3://$bucketName
```

### 8.2 Clean Local Resources
```powershell
# Remove Docker images
docker rmi devopsasg1-app:test
docker rmi vulnerable-test

# Clean Terraform state
Remove-Item .terraform -Recurse -Force
Remove-Item terraform.tfstate*
Remove-Item .terraform.lock.hcl
```

## 🎯 Expected Test Results

### ✅ Successful Tests Should Show:
1. **Security Scans**: tfsec and Trivy pass without critical issues
2. **Infrastructure**: EKS cluster and VPC created successfully
3. **Secrets**: Sealed secrets encrypted and applied correctly
4. **Application**: Web app accessible via LoadBalancer
5. **Pipeline**: GitHub Actions complete all stages
6. **Monitoring**: All pods running and healthy

### ⚠️ Common Issues and Solutions:

**Issue**: EKS cluster creation timeout
**Solution**: EKS takes 10-15 minutes; increase timeout or wait longer

**Issue**: Sealed Secrets controller not ready
**Solution**: Ensure controller pod is running in kube-system namespace

**Issue**: LoadBalancer pending
**Solution**: Check security groups and subnet configuration

**Issue**: tfsec failures
**Solution**: Review and fix Terraform security configurations

**Issue**: Trivy vulnerabilities
**Solution**: Update base images to latest versions

## 💰 Cost Considerations

**Estimated AWS costs for testing**:
- EKS Cluster: ~$0.10/hour
- t3.micro EC2: ~$0.01/hour  
- VPC/Networking: ~$0.05/hour
- LoadBalancer: ~$0.025/hour

**Total**: ~$0.18/hour or ~$4.30/day

**⚠️ Remember to destroy resources after testing to avoid ongoing charges!**

## 🎉 Success Criteria

Your DevSecOps setup is working correctly if:
- ✅ All security scans pass in GitHub Actions
- ✅ Infrastructure deploys successfully via Terraform
- ✅ Sealed secrets are created and applied
- ✅ Application is accessible via LoadBalancer
- ✅ Pipeline runs automatically on code push
- ✅ Security results appear in GitHub Security tab

## 📞 Support

If you encounter issues:
1. Check GitHub Actions logs
2. Review kubectl logs for pods
3. Verify AWS permissions and quotas
4. Ensure all prerequisites are installed
5. Check the troubleshooting section in README.md
