# PowerShell Setup Script for Windows
# setup.ps1

param(
    [switch]$SkipAWS,
    [switch]$SkipTerraform,
    [switch]$SkipSecretsSetup
)

# Colors for output
$Red = "Red"
$Green = "Green" 
$Yellow = "Yellow"
$Blue = "Cyan"

function Write-Header {
    param($Message)
    Write-Host "=============================================" -ForegroundColor $Blue
    Write-Host $Message -ForegroundColor $Blue
    Write-Host "=============================================" -ForegroundColor $Blue
}

function Write-Success {
    param($Message)
    Write-Host "✅ $Message" -ForegroundColor $Green
}

function Write-Warning {
    param($Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Yellow
}

function Write-Error {
    param($Message)
    Write-Host "❌ $Message" -ForegroundColor $Red
}

# Check prerequisites
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    $missingTools = @()
    
    # Check AWS CLI
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        $missingTools += "aws-cli"
    }
    
    # Check Terraform
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        $missingTools += "terraform"
    }
    
    # Check kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        $missingTools += "kubectl"
    }
    
    # Check Docker
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        $missingTools += "docker"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Error "Missing required tools: $($missingTools -join ', ')"
        Write-Host ""
        Write-Host "Please install the missing tools and run this script again."
        Write-Host ""
        Write-Host "Installation guides:"
        Write-Host "- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        Write-Host "- Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        Write-Host "- kubectl: https://kubernetes.io/docs/tasks/tools/"
        Write-Host "- Docker: https://docs.docker.com/get-docker/"
        exit 1
    }
    
    Write-Success "All prerequisites are installed"
}

# Setup AWS resources
function Initialize-AWSResources {
    if ($SkipAWS) {
        Write-Warning "Skipping AWS setup as requested"
        return
    }
    
    Write-Header "Setting up AWS Resources"
    
    # Check AWS credentials
    try {
        aws sts get-caller-identity --output text | Out-Null
        Write-Success "AWS credentials are configured"
    }
    catch {
        Write-Error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    }
    
    # Read configuration from terraform.tfvars
    $tfvarsContent = Get-Content "terraform.tfvars" -Raw
    $bucketName = ($tfvarsContent | Select-String 'bucket_name\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
    $awsRegion = ($tfvarsContent | Select-String 'aws_region\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
    
    # Check if S3 bucket exists
    try {
        aws s3api head-bucket --bucket $bucketName 2>$null
        Write-Success "S3 bucket $bucketName already exists"
    }
    catch {
        Write-Warning "Creating S3 bucket: $bucketName"
        
        if ($awsRegion -eq "us-east-1") {
            aws s3api create-bucket --bucket $bucketName --region $awsRegion
        }
        else {
            aws s3api create-bucket --bucket $bucketName --region $awsRegion --create-bucket-configuration LocationConstraint=$awsRegion
        }
        
        # Enable versioning
        aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled
        
        Write-Success "S3 bucket created with versioning enabled"
    }
}

# Initialize Terraform
function Initialize-Terraform {
    if ($SkipTerraform) {
        Write-Warning "Skipping Terraform setup as requested"
        return
    }
    
    Write-Header "Initializing Terraform"
    
    # Read configuration from terraform.tfvars
    $tfvarsContent = Get-Content "terraform.tfvars" -Raw
    $bucketName = ($tfvarsContent | Select-String 'bucket_name\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
    $awsRegion = ($tfvarsContent | Select-String 'aws_region\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
    
    # Initialize Terraform
    terraform init `
        -backend-config="bucket=$bucketName" `
        -backend-config="key=terraform.tfstate" `
        -backend-config="region=$awsRegion"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform initialized"
    }
    else {
        Write-Error "Terraform initialization failed"
        exit 1
    }
    
    # Validate configuration
    terraform validate
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform configuration is valid"
    }
    else {
        Write-Error "Terraform validation failed"
        exit 1
    }
    
    # Plan infrastructure
    Write-Warning "Creating Terraform plan..."
    terraform plan -var-file="terraform.tfvars" -out=tfplan
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform plan created successfully"
    }
    else {
        Write-Error "Terraform plan failed"
        exit 1
    }
}

# Setup GitHub secrets
function Show-GitHubSecretsInfo {
    if ($SkipSecretsSetup) {
        Write-Warning "Skipping GitHub secrets setup as requested"
        return
    }
    
    Write-Header "GitHub Secrets Setup"
    
    # Read bucket name from terraform.tfvars
    $tfvarsContent = Get-Content "terraform.tfvars" -Raw
    $bucketName = ($tfvarsContent | Select-String 'bucket_name\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
    
    Write-Host "Please ensure the following secrets are configured in your GitHub repository:"
    Write-Host ""
    Write-Host "Repository Settings > Secrets and variables > Actions"
    Write-Host ""
    Write-Host "Required secrets:"
    Write-Host "  AWS_ACCESS_KEY_ID      - Your AWS access key"
    Write-Host "  AWS_SECRET_ACCESS_KEY  - Your AWS secret key"
    Write-Host "  TF_STATE_BUCKET        - $bucketName"
    Write-Host "  AWS_ACCOUNT_ID         - Your AWS account ID"
    Write-Host "  DB_USERNAME            - Database username for sealed secrets"
    Write-Host "  DB_PASSWORD            - Database password for sealed secrets"
    Write-Host ""
    
    $response = Read-Host "Have you configured all GitHub secrets? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Warning "Please configure GitHub secrets before proceeding with deployment"
    }
}

# Deploy infrastructure
function Deploy-Infrastructure {
    Write-Header "Deploying Infrastructure"
    
    if (-not (Test-Path "tfplan")) {
        Write-Warning "No Terraform plan found. Run without -SkipTerraform first."
        return
    }
    
    $response = Read-Host "Do you want to deploy the infrastructure now? (y/N)"
    if ($response -eq "y" -or $response -eq "Y") {
        Write-Warning "Applying Terraform configuration..."
        terraform apply tfplan
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Infrastructure deployed successfully"
            
            # Update kubeconfig
            $tfvarsContent = Get-Content "terraform.tfvars" -Raw
            $projectName = ($tfvarsContent | Select-String 'project_name\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
            $awsRegion = ($tfvarsContent | Select-String 'aws_region\s*=\s*"([^"]*)"').Matches[0].Groups[1].Value
            $eksClusterName = "$projectName-eks-cluster"
            
            aws eks update-kubeconfig --region $awsRegion --name $eksClusterName
            Write-Success "Kubeconfig updated for EKS cluster"
        }
        else {
            Write-Error "Infrastructure deployment failed"
        }
    }
    else {
        Write-Warning "Skipping infrastructure deployment"
        Write-Host "To deploy later, run: terraform apply tfplan"
    }
}

# Main setup function
function Start-Setup {
    Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                    DevSecOps Setup Script                   ║
║              GitHub Actions + Terraform + EKS               ║
║                  with Security Scanning                     ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $Blue
    
    Test-Prerequisites
    Initialize-AWSResources
    Initialize-Terraform
    Show-GitHubSecretsInfo
    Deploy-Infrastructure
    
    Write-Header "Setup Complete! 🎉"
    
    Write-Host "Next steps:"
    Write-Host ""
    Write-Host "1. 📝 Commit and push your code to GitHub"
    Write-Host "2. 🔄 GitHub Actions will automatically run the DevSecOps pipeline"
    Write-Host "3. 🔐 Create sealed secrets using the scripts in the scripts/ folder"
    Write-Host "4. 🚀 Deploy your applications to the Kubernetes cluster"
    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  kubectl get pods -A                    # Check all pods"
    Write-Host "  kubectl get svc -n devopsasg1         # Check services"
    Write-Host "  docker-compose up --build             # Test locally"
    Write-Host ""
    Write-Host "Documentation: See README.md for detailed instructions"
    Write-Host ""
    Write-Success "Happy DevSecOps! 🛡️🚀"
}

# Run the setup
Start-Setup
