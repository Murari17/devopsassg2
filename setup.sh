#!/bin/bash

# setup.sh
# Main setup script for the DevSecOps project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "============================================="
    echo "$1"
    echo "============================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools and run this script again."
        echo ""
        echo "Installation guides:"
        echo "- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo "- Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        echo "- kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "- Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Setup AWS resources
setup_aws() {
    print_header "Setting up AWS Resources"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "AWS credentials are configured"
    
    # Create S3 bucket for Terraform state
    BUCKET_NAME=$(grep 'bucket_name' terraform.tfvars | cut -d'"' -f2)
    AWS_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2)
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        print_success "S3 bucket $BUCKET_NAME already exists"
    else
        print_warning "Creating S3 bucket: $BUCKET_NAME"
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        print_success "S3 bucket created with versioning enabled"
    fi
}

# Initialize Terraform
setup_terraform() {
    print_header "Initializing Terraform"
    
    BUCKET_NAME=$(grep 'bucket_name' terraform.tfvars | cut -d'"' -f2)
    AWS_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2)
    
    terraform init \
        -backend-config="bucket=$BUCKET_NAME" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=$AWS_REGION"
    
    print_success "Terraform initialized"
    
    # Validate configuration
    if terraform validate; then
        print_success "Terraform configuration is valid"
    else
        print_error "Terraform validation failed"
        exit 1
    fi
    
    # Plan infrastructure
    print_warning "Creating Terraform plan..."
    terraform plan -var-file="terraform.tfvars" -out=tfplan
    
    print_success "Terraform plan created successfully"
}

# Setup GitHub secrets
setup_github_secrets() {
    print_header "GitHub Secrets Setup"
    
    echo "Please ensure the following secrets are configured in your GitHub repository:"
    echo ""
    echo "Repository Settings > Secrets and variables > Actions"
    echo ""
    echo "Required secrets:"
    echo "  AWS_ACCESS_KEY_ID      - Your AWS access key"
    echo "  AWS_SECRET_ACCESS_KEY  - Your AWS secret key"
    echo "  TF_STATE_BUCKET        - $(grep 'bucket_name' terraform.tfvars | cut -d'"' -f2)"
    echo "  AWS_ACCOUNT_ID         - Your AWS account ID"
    echo "  DB_USERNAME            - Database username for sealed secrets"
    echo "  DB_PASSWORD            - Database password for sealed secrets"
    echo ""
    
    read -p "Have you configured all GitHub secrets? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Please configure GitHub secrets before proceeding with deployment"
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    read -p "Do you want to deploy the infrastructure now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Applying Terraform configuration..."
        terraform apply tfplan
        print_success "Infrastructure deployed successfully"
        
        # Update kubeconfig
        EKS_CLUSTER_NAME=$(grep 'project_name' terraform.tfvars | cut -d'"' -f2)-eks-cluster
        AWS_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2)
        
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
        print_success "Kubeconfig updated for EKS cluster"
    else
        print_warning "Skipping infrastructure deployment"
        echo "To deploy later, run: terraform apply tfplan"
    fi
}

# Setup Sealed Secrets
setup_sealed_secrets() {
    print_header "Setting up Sealed Secrets"
    
    if [ -f "tfplan" ]; then
        read -p "Do you want to setup Sealed Secrets? (EKS cluster must be running) (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            chmod +x scripts/setup-sealed-secrets.sh
            ./scripts/setup-sealed-secrets.sh
            print_success "Sealed Secrets setup completed"
        fi
    else
        print_warning "Infrastructure not deployed yet. Skipping Sealed Secrets setup."
    fi
}

# Make scripts executable
setup_scripts() {
    print_header "Setting up Scripts"
    
    chmod +x scripts/*.sh
    print_success "Scripts are now executable"
}

# Main setup function
main() {
    echo -e "${BLUE}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    DevSecOps Setup Script                   ║
║              GitHub Actions + Terraform + EKS               ║
║                  with Security Scanning                     ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_prerequisites
    setup_scripts
    setup_aws
    setup_terraform
    setup_github_secrets
    deploy_infrastructure
    setup_sealed_secrets
    
    print_header "Setup Complete! 🎉"
    
    echo "Next steps:"
    echo ""
    echo "1. 📝 Commit and push your code to GitHub"
    echo "2. 🔄 GitHub Actions will automatically run the DevSecOps pipeline"
    echo "3. 🔐 Create sealed secrets using: ./scripts/create-sealed-secret.sh"
    echo "4. 🚀 Deploy your applications to the Kubernetes cluster"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -A                    # Check all pods"
    echo "  kubectl get svc -n devopsasg1         # Check services"
    echo "  ./scripts/security-scan.sh            # Run local security scan"
    echo ""
    echo "Documentation: See README.md for detailed instructions"
    echo ""
    print_success "Happy DevSecOps! 🛡️🚀"
}

# Run main function
main "$@"
