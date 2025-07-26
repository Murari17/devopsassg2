#!/bin/bash

# security-scan.sh
# Script to run local security scans before pushing code

set -e

echo "🔍 Running DevSecOps Security Scans..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    echo "🔧 Checking dependencies..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v tfsec &> /dev/null; then
        print_warning "tfsec not found. Installing..."
        # Install tfsec
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install tfsec
        else
            print_error "Please install tfsec manually"
            missing_tools+=("tfsec")
        fi
    fi
    
    if ! command -v trivy &> /dev/null; then
        print_warning "trivy not found. Installing..."
        # Install trivy
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install trivy
        else
            print_error "Please install trivy manually"
            missing_tools+=("trivy")
        fi
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_status "All dependencies are available"
}

# Run Terraform format check
terraform_format_check() {
    echo "📋 Running Terraform format check..."
    if terraform fmt -check -diff; then
        print_status "Terraform formatting is correct"
    else
        print_warning "Terraform files need formatting. Run 'terraform fmt -recursive' to fix."
    fi
}

# Run tfsec scan
run_tfsec() {
    echo "🔒 Running tfsec security scan..."
    if tfsec . --format=table; then
        print_status "tfsec scan completed - no critical issues found"
    else
        print_error "tfsec found security issues. Please review and fix them."
        return 1
    fi
}

# Run Terraform validation
terraform_validate() {
    echo "✅ Running Terraform validation..."
    if [ -f "main.tf" ]; then
        terraform init -backend=false
        if terraform validate; then
            print_status "Terraform configuration is valid"
        else
            print_error "Terraform validation failed"
            return 1
        fi
    else
        print_warning "No Terraform files found, skipping validation"
    fi
}

# Build and scan Docker image
docker_security_scan() {
    echo "🐳 Building and scanning Docker image..."
    if [ -f "app/Dockerfile" ]; then
        # Build the image
        docker build -t local-security-scan:latest ./app
        
        # Run Trivy scan
        echo "🔍 Running Trivy vulnerability scan..."
        if trivy image --severity HIGH,CRITICAL local-security-scan:latest; then
            print_status "Docker image scan completed"
        else
            print_error "Docker image has security vulnerabilities"
            return 1
        fi
        
        # Clean up
        docker rmi local-security-scan:latest 2>/dev/null || true
    else
        print_warning "No Dockerfile found, skipping Docker scan"
    fi
}

# Run hadolint for Dockerfile linting
dockerfile_lint() {
    echo "📝 Running Dockerfile linting..."
    if [ -f "app/Dockerfile" ]; then
        if command -v hadolint &> /dev/null; then
            if hadolint app/Dockerfile; then
                print_status "Dockerfile linting passed"
            else
                print_warning "Dockerfile linting found issues"
            fi
        else
            print_warning "hadolint not found, skipping Dockerfile linting"
        fi
    fi
}

# Check for secrets in code
check_secrets() {
    echo "🔍 Checking for exposed secrets..."
    
    # Simple pattern matching for common secrets
    secret_patterns=(
        "password\s*=\s*['\"][^'\"]*['\"]"
        "api[_-]?key\s*=\s*['\"][^'\"]*['\"]"
        "secret\s*=\s*['\"][^'\"]*['\"]"
        "token\s*=\s*['\"][^'\"]*['\"]"
        "AKIA[0-9A-Z]{16}"  # AWS Access Key
        "ghp_[0-9a-zA-Z]{36}"  # GitHub Personal Access Token
    )
    
    found_secrets=false
    for pattern in "${secret_patterns[@]}"; do
        if grep -r -i -E "$pattern" . --exclude-dir=.git --exclude="*.md" --exclude="security-scan.sh" 2>/dev/null; then
            found_secrets=true
        fi
    done
    
    if [ "$found_secrets" = true ]; then
        print_error "Potential secrets found in code. Please review and remove them."
        return 1
    else
        print_status "No obvious secrets found in code"
    fi
}

# Main execution
main() {
    echo "🚀 Starting DevSecOps Security Scan Pipeline"
    echo "============================================="
    
    check_dependencies
    
    # Track overall status
    overall_status=0
    
    terraform_format_check || overall_status=1
    terraform_validate || overall_status=1
    run_tfsec || overall_status=1
    dockerfile_lint || overall_status=1
    docker_security_scan || overall_status=1
    check_secrets || overall_status=1
    
    echo ""
    echo "============================================="
    if [ $overall_status -eq 0 ]; then
        print_status "🎉 All security scans passed! Ready to push to repository."
    else
        print_error "❌ Some security scans failed. Please fix the issues before pushing."
        exit 1
    fi
}

# Run main function
main "$@"
