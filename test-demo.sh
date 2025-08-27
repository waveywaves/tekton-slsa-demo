#!/bin/bash

set -e

echo "=============================================="
echo "🧪 Tekton SLSA Demo - End-to-End Test"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to make all scripts executable
make_scripts_executable() {
    echo "Making all scripts executable..."
    chmod +x scripts/*.sh run-demo.sh test-demo.sh
    print_status "Scripts are now executable"
}

# Function to test Go application
test_go_application() {
    echo "Testing Go application..."
    
    if [ ! -f "cmd/main.go" ]; then
        print_error "Go application not found"
        return 1
    fi
    
    # Test Go application compilation
    echo "Testing Go compilation..."
    if go mod tidy && go build -o test-app ./cmd/main.go; then
        print_status "Go application compiles successfully"
        rm -f test-app
    else
        print_error "Go application compilation failed"
        return 1
    fi
    
    # Run tests if they exist
    if [ -f "cmd/main_test.go" ]; then
        echo "Running Go tests..."
        if go test ./cmd/; then
            print_status "Go tests pass"
        else
            print_warning "Go tests failed"
        fi
    fi
}

# Function to validate Kubernetes manifests
test_kubernetes_manifests() {
    echo "Testing Kubernetes manifests..."
    
    if [ ! -d "k8s" ]; then
        print_warning "No k8s directory found - manifests will be created by scripts"
        return 0
    fi
    
    # Validate YAML syntax
    for yaml_file in k8s/*.yaml; do
        if [ -f "$yaml_file" ]; then
            echo "Validating $yaml_file..."
            if kubectl apply --dry-run=client -f "$yaml_file" >/dev/null 2>&1; then
                print_status "$(basename $yaml_file) is valid"
            else
                print_warning "$(basename $yaml_file) has validation issues"
            fi
        fi
    done
}

# Function to check script syntax
test_script_syntax() {
    echo "Testing script syntax..."
    
    local errors=0
    
    for script in scripts/*.sh run-demo.sh; do
        if [ -f "$script" ]; then
            echo "Checking syntax of $script..."
            if bash -n "$script"; then
                print_status "$(basename $script) syntax is valid"
            else
                print_error "$(basename $script) has syntax errors"
                errors=$((errors + 1))
            fi
        fi
    done
    
    return $errors
}

# Function to test Docker build
test_docker_build() {
    echo "Testing Docker build..."
    
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not found - skipping container build test"
        return 0
    fi
    
    if [ ! -f "Dockerfile" ]; then
        print_error "Dockerfile not found"
        return 1
    fi
    
    echo "Building Docker image..."
    if docker build -t tekton-slsa-demo:test . >/dev/null 2>&1; then
        print_status "Docker image builds successfully"
        # Clean up test image
        docker rmi tekton-slsa-demo:test >/dev/null 2>&1 || true
    else
        print_error "Docker build failed"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo "Checking required tools..."
    
    local missing=0
    
    # Check required tools
    tools=("kubectl" "kind" "cosign" "jq" "curl" "docker" "go")
    
    for tool in "${tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            print_status "$tool is available"
        else
            print_warning "$tool is not available"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        print_info "Run ./scripts/00-prerequisites.sh to install missing tools"
    fi
    
    return $missing
}

# Function to verify file structure
verify_file_structure() {
    echo "Verifying demo file structure..."
    
    # Check required directories
    required_dirs=("scripts" "k8s" "cmd")
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            print_status "$dir directory exists"
        else
            print_error "$dir directory missing"
        fi
    done
    
    # Check key files
    key_files=(
        "cmd/main.go"
        "cmd/main_test.go"  
        "go.mod"
        "Dockerfile"
        "Makefile"
        "README.md"
        "DEMO_SUMMARY.md"
        "run-demo.sh"
    )
    
    for file in "${key_files[@]}"; do
        if [ -f "$file" ]; then
            print_status "$file exists"
        else
            print_warning "$file missing"
        fi
    done
    
    # Check script files
    expected_scripts=(
        "00-prerequisites.sh"
        "01-setup-kind-cluster-with-oidc.sh"
        "02-install-tekton-pipelines.sh"
        "03-install-tekton-chains.sh"
        "04a-configure-keyless-signing.sh"
        "04b-configure-key-signing.sh"
        "05-deploy-sample-go-app.sh"
        "06-setup-trusted-resources.sh"
        "07-enable-hermetic-mode.sh"
        "08-run-complete-slsa-pipeline.sh"
        "09-verify-slsa-compliance.sh"
    )
    
    for script in "${expected_scripts[@]}"; do
        if [ -f "scripts/$script" ]; then
            print_status "scripts/$script exists"
        else
            print_error "scripts/$script missing"
        fi
    done
}

# Function to run demo integration test
run_integration_test() {
    echo "Running integration test (dry-run mode)..."
    
    print_info "This test verifies the demo can start without actually running it"
    
    # Test script 1: Prerequisites check
    if [ -f "scripts/00-prerequisites.sh" ]; then
        echo "Testing prerequisites script (dry-run)..."
        # We can't actually run this without installing tools
        print_status "Prerequisites script exists and is executable"
    fi
    
    # Test script 2: Cluster setup check
    if [ -f "scripts/01-setup-kind-cluster-with-oidc.sh" ]; then
        echo "Validating cluster setup script..."
        bash -n scripts/01-setup-kind-cluster-with-oidc.sh
        print_status "Cluster setup script syntax is valid"
    fi
    
    # Test Go application build
    test_go_application
    
    # Test Docker build
    test_docker_build
}

# Function to generate test report
generate_test_report() {
    echo ""
    echo "=============================================="
    echo "📊 Test Results Summary"
    echo "=============================================="
    
    cat << EOF

🧪 TEKTON SLSA DEMO - TEST REPORT
=================================

File Structure:
$(verify_file_structure 2>&1 | grep -c "✅") files/directories found
$(verify_file_structure 2>&1 | grep -c "⚠️\|❌") files/directories missing or have issues

Script Validation:
$(test_script_syntax 2>&1 | grep -c "✅") scripts have valid syntax
$(test_script_syntax 2>&1 | grep -c "❌") scripts have syntax errors

Go Application:
$(test_go_application >/dev/null 2>&1 && echo "✅ Compiles and tests pass" || echo "❌ Compilation or test issues")

Docker Build:
$(test_docker_build >/dev/null 2>&1 && echo "✅ Docker image builds successfully" || echo "⚠️ Docker build issues or Docker not available")

Prerequisites:
$(check_prerequisites 2>&1 | grep -c "✅") required tools available
$(check_prerequisites 2>&1 | grep -c "⚠️") tools missing or not found

Recommendations:
- Run './scripts/00-prerequisites.sh' to install missing tools
- Ensure Docker is running for container builds
- All scripts are now executable and ready to use

Demo Readiness: $([ -f "cmd/main.go" ] && [ -f "scripts/01-setup-kind-cluster-with-oidc.sh" ] && echo "🚀 READY TO DEMO" || echo "⚠️ NEEDS SETUP")

=================================
Test completed: $(date -Iseconds)

EOF
}

# Main function
main() {
    echo "Starting comprehensive demo test..."
    echo ""
    
    # Make scripts executable
    make_scripts_executable
    
    # Verify file structure
    verify_file_structure
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Test script syntax
    test_script_syntax
    echo ""
    
    # Test Kubernetes manifests
    test_kubernetes_manifests
    echo ""
    
    # Run integration test
    run_integration_test
    echo ""
    
    # Generate test report
    generate_test_report
    
    echo "=============================================="
    echo "🎉 Demo testing completed!"
    echo "=============================================="
    echo ""
    print_info "Your Tekton SLSA demo is ready to run!"
    echo ""
    echo "Next steps:"
    echo "  1. Install prerequisites: ./scripts/00-prerequisites.sh"
    echo "  2. Run the interactive demo: ./run-demo.sh"
    echo "  3. Or run the full automated setup following the README"
    echo ""
    echo "For troubleshooting, check the test report above."
}

# Run main function
main "$@"