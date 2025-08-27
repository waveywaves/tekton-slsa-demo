#!/bin/bash

set -e

# Function for error handling
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function for logging
log_info() {
    echo "INFO: $1"
}

# Function for validation
validate_installation() {
    local tool="$1"
    local validation_cmd="$2"
    
    if command_exists "$tool"; then
        if eval "$validation_cmd" >/dev/null 2>&1; then
            log_info "✅ $tool installed and working correctly"
            return 0
        else
            error_exit "$tool is installed but not working properly"
        fi
    else
        error_exit "$tool installation failed"
    fi
}

echo "============================================"
echo "Installing Prerequisites for Tekton SLSA Demo"
echo "============================================"

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="darwin"
    ARCH="amd64"
    if [[ $(uname -m) == "arm64" ]]; then
        ARCH="arm64"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
    ARCH="amd64"
    if [[ $(uname -m) == "aarch64" ]]; then
        ARCH="arm64"
    fi
else
    echo "Unsupported platform: $OSTYPE"
    exit 1
fi

echo "Detected platform: $PLATFORM/$ARCH"

# Create temporary directory for downloads
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install kubectl
install_kubectl() {
    if command_exists kubectl; then
        log_info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return
    fi
    
    log_info "Installing kubectl..."
    
    # Get latest stable version
    local latest_version
    latest_version=$(curl -L -s https://dl.k8s.io/release/stable.txt) || error_exit "Failed to get latest kubectl version"
    
    # Download kubectl
    curl -LO "https://dl.k8s.io/release/$latest_version/bin/$PLATFORM/$ARCH/kubectl" || error_exit "Failed to download kubectl"
    
    # Verify download
    if [[ ! -f kubectl ]]; then
        error_exit "kubectl binary not found after download"
    fi
    
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/ || error_exit "Failed to move kubectl to /usr/local/bin/"
    
    # Validate installation
    validate_installation "kubectl" "kubectl version --client"
}

# Function to install kind
install_kind() {
    if command_exists kind; then
        echo "kind already installed: $(kind version)"
        return
    fi
    
    echo "Installing kind..."
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-$PLATFORM-$ARCH"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    kind version
}

# Function to install cosign
install_cosign() {
    if command_exists cosign; then
        echo "cosign already installed: $(cosign version)"
        return
    fi
    
    echo "Installing cosign..."
    COSIGN_VERSION="v2.2.2"
    curl -L "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-$PLATFORM-$ARCH" -o cosign
    chmod +x cosign
    sudo mv cosign /usr/local/bin/
    cosign version
}

# Function to install tekton CLI
install_tekton_cli() {
    if command_exists tkn; then
        echo "Tekton CLI already installed: $(tkn version)"
        return
    fi
    
    echo "Installing Tekton CLI..."
    TKN_VERSION="0.32.2"
    if [[ "$PLATFORM" == "darwin" ]]; then
        curl -L "https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tkn_${TKN_VERSION}_Darwin_all.tar.gz" | tar xz -C $TEMP_DIR
    else
        curl -L "https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tkn_${TKN_VERSION}_Linux_x86_64.tar.gz" | tar xz -C $TEMP_DIR
    fi
    chmod +x $TEMP_DIR/tkn
    sudo mv $TEMP_DIR/tkn /usr/local/bin/
    tkn version
}

# Function to check docker
check_docker() {
    if ! command_exists docker; then
        echo "Docker is not installed. Please install Docker first."
        echo "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    echo "Docker is installed and running: $(docker version --format '{{.Client.Version}}')"
}

# Function to install jq (for JSON processing)
install_jq() {
    if command_exists jq; then
        echo "jq already installed: $(jq --version)"
        return
    fi
    
    echo "Installing jq..."
    if [[ "$PLATFORM" == "darwin" ]]; then
        if command_exists brew; then
            brew install jq
        else
            curl -L "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64" -o jq
            chmod +x jq
            sudo mv jq /usr/local/bin/
        fi
    else
        sudo apt-get update && sudo apt-get install -y jq
    fi
    jq --version
}

# Function to install yq (for YAML processing)
install_yq() {
    if command_exists yq; then
        echo "yq already installed: $(yq --version)"
        return
    fi
    
    echo "Installing yq..."
    YQ_VERSION="v4.35.2"
    curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${PLATFORM}_${ARCH}" -o yq
    chmod +x yq
    sudo mv yq /usr/local/bin/
    yq --version
}

# Main installation process
main() {
    echo "Starting prerequisite installation..."
    
    # Check Docker first as it's critical
    check_docker
    
    # Install tools
    install_kubectl
    install_kind
    install_cosign
    install_tekton_cli
    install_jq
    install_yq
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "============================================"
    echo "Prerequisites Installation Complete!"
    echo "============================================"
    echo "Installed versions:"
    echo "- kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    echo "- kind: $(kind version)"
    echo "- cosign: $(cosign version | head -1)"
    echo "- tekton CLI: $(tkn version | head -1)"
    echo "- jq: $(jq --version)"
    echo "- yq: $(yq --version)"
    echo "- docker: $(docker version --format '{{.Client.Version}}')"
    echo ""
    echo "Ready to proceed with Tekton SLSA demo setup!"
    echo "Next step: Run ./scripts/01-setup-kind-cluster-with-oidc.sh"
}

# Run main function
main "$@"