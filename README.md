# DevSecOps Integration Project

This project demonstrates a comprehensive DevSecOps pipeline using GitHub Actions, Terraform, Kubernetes, and various security scanning tools.

## 🏗️ Architecture

- **Infrastructure**: AWS EKS cluster provisioned with Terraform
- **Security**: tfsec for Terraform scanning, Trivy for container scanning
- **Secrets Management**: Bitnami Sealed Secrets for secure secret management
- **CI/CD**: GitHub Actions with security gates
- **Application**: Containerized web application deployed to Kubernetes

## 🔧 Prerequisites

- AWS Account with appropriate permissions
- GitHub repository with Actions enabled
- kubectl installed locally
- Terraform installed locally
- Docker installed locally

## 🚀 Quick Start

### 1. Setup AWS Credentials

Create the following GitHub Secrets:
```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
TF_STATE_BUCKET
AWS_ACCOUNT_ID
DB_USERNAME
DB_PASSWORD
```

### 2. Create S3 Bucket for Terraform State

```bash
aws s3 mb s3://your-terraform-state-bucket --region ap-south-1
```

### 3. Update terraform.tfvars

Update the values in `terraform.tfvars` with your specific configuration.

### 4. Local Development Setup

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run local security scan
./scripts/security-scan.sh

# Setup Sealed Secrets (after EKS cluster is ready)
./scripts/setup-sealed-secrets.sh

# Create sealed secrets
./scripts/create-sealed-secret.sh db-secret devopsasg1 username=admin password=secret123
```

## 📋 Pipeline Overview

### Security Scanning Job
- **Terraform Format Check**: Ensures consistent code formatting
- **tfsec**: Scans Terraform code for security issues
- **Checkov**: Additional static analysis for IaC

### Build and Scan Job
- **Docker Build**: Builds application container
- **Trivy Scan**: Scans container for vulnerabilities
- **ECR Push**: Pushes secure images to Amazon ECR

### Infrastructure Deployment
- **Terraform Plan**: Plans infrastructure changes
- **Terraform Apply**: Applies changes to AWS (production only)

### Application Deployment
- **Sealed Secrets**: Applies encrypted secrets to cluster
- **Kubernetes Deployment**: Deploys application with rolling updates
- **Health Checks**: Verifies deployment success

## 🔐 Security Features

### Infrastructure Security
- VPC with public/private subnets
- Security groups with minimal required access
- EKS cluster with managed node groups
- Network policies for pod-to-pod communication

### Container Security
- Non-root user in containers
- Security headers in Nginx configuration
- Resource limits and health checks
- Vulnerability scanning with Trivy

### Secret Management
- Sealed Secrets for encrypted secret storage in Git
- Kubernetes secrets automatically decrypted in cluster
- No plain-text secrets in repository

### Pipeline Security
- Security scanning gates in CI/CD
- SARIF format results uploaded to GitHub Security
- Fail-fast on critical vulnerabilities
- Environment-based deployments with approvals

## 📁 Project Structure

```
.
├── .github/
│   └── workflows/
│       └── devsecops-pipeline.yml    # Main CI/CD pipeline
├── app/
│   ├── Dockerfile                    # Secure container definition
│   ├── index.html                    # Application frontend
│   └── nginx.conf                    # Nginx configuration with security headers
├── k8s/
│   ├── deployment.yaml               # Kubernetes manifests
│   └── secret.yaml                   # Example secret (to be sealed)
├── scripts/
│   ├── setup-sealed-secrets.sh       # Setup script for Sealed Secrets
│   ├── create-sealed-secret.sh       # Script to create sealed secrets
│   └── security-scan.sh              # Local security scanning
├── main.tf                          # Main Terraform configuration
├── variables.tf                     # Terraform variables
├── outputs.tf                       # Terraform outputs
├── terraform.tfvars                 # Terraform variable values
├── user-data.sh                     # EC2 user data script
└── README.md                        # This file
```

## 🔄 Workflow Triggers

The pipeline runs on:
- **Push to main/develop**: Full pipeline including deployment
- **Pull Requests**: Security scanning and build only
- **Manual dispatch**: Can be triggered manually

## 📊 Security Scanning Tools

### tfsec
- Scans Terraform code for security misconfigurations
- Checks for AWS best practices
- Results uploaded to GitHub Security tab

### Trivy
- Scans container images for vulnerabilities
- Checks for known CVEs in base images and dependencies
- Fails build on HIGH/CRITICAL vulnerabilities

### Checkov
- Additional static analysis for infrastructure as code
- Policy-as-code security scanning
- Complements tfsec with different rule sets

## 🛡️ Sealed Secrets Usage

### Creating Sealed Secrets

```bash
# Create a regular secret
kubectl create secret generic mysecret \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  --dry-run=client -o yaml > mysecret.yaml

# Seal the secret
kubeseal -f mysecret.yaml -w mysealedsecret.yaml

# Apply the sealed secret
kubectl apply -f mysealedsecret.yaml

# Clean up the unencrypted secret
rm mysecret.yaml
```

### Updating Sealed Secrets

1. Create new secret with updated values
2. Seal the new secret
3. Apply the updated sealed secret
4. The controller will automatically update the cluster secret

## 🚨 Security Considerations

### Secrets Management
- Never commit plain-text secrets to Git
- Use Sealed Secrets for Kubernetes secrets
- Store sensitive values in GitHub Secrets
- Rotate secrets regularly

### Access Control
- Use least-privilege IAM roles
- Enable MFA for AWS accounts
- Restrict GitHub repository access
- Use environment protection rules

### Monitoring
- Enable AWS CloudTrail
- Monitor EKS cluster logs
- Set up alerts for security events
- Regular security audits

## 🧪 Testing

### Local Testing
```bash
# Run security scans locally
./scripts/security-scan.sh

# Test Docker build
docker build -t test-app ./app
docker run -p 8080:8080 test-app

# Validate Terraform
terraform init
terraform plan -var-file="terraform.tfvars"
```

### Pipeline Testing
- Create feature branches for testing changes
- Use pull requests to trigger security scans
- Test in development environment before production

## 🔧 Troubleshooting

### Common Issues

1. **tfsec failures**: Review Terraform code for security best practices
2. **Trivy failures**: Update base images or fix application dependencies
3. **Sealed Secrets not working**: Ensure controller is running and certificate is valid
4. **EKS access issues**: Check IAM roles and kubeconfig

### Debug Commands

```bash
# Check EKS cluster status
kubectl cluster-info

# Check Sealed Secrets controller
kubectl get pods -n kube-system | grep sealed-secrets

# Check application pods
kubectl get pods -n devopsasg1

# View application logs
kubectl logs -f deployment/devopsasg1-app -n devopsasg1
```

## 📈 Monitoring and Observability

### Kubernetes Monitoring
- Pod health checks and readiness probes
- Resource utilization monitoring
- Application logs collection

### AWS Monitoring
- CloudWatch metrics for EKS
- VPC Flow Logs
- CloudTrail for API auditing

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Run local security scans
4. Submit a pull request
5. Ensure all pipeline checks pass

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Create an issue in the GitHub repository
- Review the troubleshooting section
- Check AWS and Kubernetes documentation
