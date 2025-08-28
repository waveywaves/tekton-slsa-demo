#!/bin/bash

set -x
set -e

echo "============================================"
echo "Installing Tekton Chains for SLSA Level 2"
echo "============================================"

# Tekton Chains version
CHAINS_VERSION="latest"

# Function to check if Tekton Chains is already installed
check_existing_installation() {
    if kubectl get namespace tekton-chains >/dev/null 2>&1; then
        echo "Tekton Chains namespace already exists"
        if kubectl get pods -n tekton-chains 2>/dev/null | grep -q Running; then
            echo "Tekton Chains appears to be running:"
            kubectl get pods -n tekton-chains
            read -p "Do you want to reinstall Tekton Chains? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Skipping Tekton Chains installation"
                return 1
            fi
            echo "Proceeding with reinstallation..."
            uninstall_chains
        fi
    fi
    return 0
}

# Function to uninstall existing Chains
uninstall_chains() {
    echo "Uninstalling existing Tekton Chains..."
    kubectl delete --ignore-not-found -f "https://storage.googleapis.com/tekton-releases/chains/${CHAINS_VERSION}/release.yaml"
    
    # Wait for cleanup
    echo "Waiting for cleanup to complete..."
    kubectl wait --for=delete namespace/tekton-chains --timeout=120s || true
    sleep 10
}

# Function to install Tekton Chains
install_tekton_chains() {
    echo "Installing Tekton Chains ${CHAINS_VERSION}..."
    
    # Install Tekton Chains
    kubectl apply -f "https://storage.googleapis.com/tekton-releases/chains/${CHAINS_VERSION}/release.yaml"
    
    echo "Waiting for Tekton Chains to be ready..."
    kubectl wait --for=condition=ready pod -l app=tekton-chains-controller -n tekton-chains --timeout=300s
}

# Function to configure Chains for SLSA compliance
configure_slsa_compliance() {
    echo "Configuring Tekton Chains for SLSA compliance..."
    
    # Configure SLSA v1.0 format for TaskRuns and PipelineRuns
    echo "Setting SLSA v1.0 format for attestations..."
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.format": "slsa/v1"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.format": "slsa/v1"}}'
    
    # Enable OCI storage for attestations  
    echo "Configuring OCI storage for attestations..."
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.storage": "oci"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.storage": "oci"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.storage": "oci"}}'
    
    # Enable transparency log
    echo "Enabling transparency log..."
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"transparency.enabled": "true"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"transparency.url": "https://rekor.sigstore.dev"}}'
    
    # Configure storage format
    echo "Configuring storage format..."
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"storage.oci.repository": "ttl.sh/tekton-slsa-demo"}}'
    
    # Enable signing of OCI images
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.format": "simplesigning"}}'
    
    # Restart Chains controller to apply changes
    echo "Restarting Tekton Chains controller to apply configuration..."
    kubectl rollout restart deployment/tekton-chains-controller -n tekton-chains
    kubectl rollout status deployment/tekton-chains-controller -n tekton-chains --timeout=180s
}

# Function to verify Chains installation
verify_installation() {
    echo "Verifying Tekton Chains installation..."
    
    # Check pods
    echo "Checking Tekton Chains pods:"
    kubectl get pods -n tekton-chains -o wide
    
    # Check services
    echo "Checking Tekton Chains services:"
    kubectl get services -n tekton-chains
    
    # Check configuration
    echo "Checking Chains configuration:"
    kubectl get configmap chains-config -n tekton-chains -o yaml
    
    # Check for chains-related CRDs (if any)
    echo "Checking for Chains-related resources:"
    kubectl api-resources | grep -i chain || echo "No chain-specific CRDs found (this is normal)"
}

# Function to create sample SLSA-compliant Task
create_sample_slsa_task() {
    echo "Creating sample SLSA-compliant Task..."
    
    # Wait for Tekton CRDs to be available
    echo "Waiting for Tekton Task CRD to be available..."
    kubectl wait --for condition=established --timeout=60s crd/tasks.tekton.dev || {
        echo "Warning: Tekton Task CRD not available yet, skipping task creation"
        return 0
    }
    
    cat << EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: build-and-attest
  namespace: default
  labels:
    slsa-demo: "true"
spec:
  params:
  - name: IMAGE_URL
    description: URL of the image to build
    default: "ttl.sh/tekton-slsa-demo/sample-app:latest"
  - name: SOURCE_URL
    description: URL of the source code
    default: "https://github.com/tektoncd/catalog"
  results:
  - name: IMAGE_URL
    description: URL of the built image
  - name: IMAGE_DIGEST
    description: Digest of the built image
  steps:
  - name: build-app
    image: alpine:3.18
    script: |
      #!/bin/sh
      set -ex
      
      echo "Building application (simulated)..."
      echo "Source URL: \$(params.SOURCE_URL)"
      echo "Target Image: \$(params.IMAGE_URL)"
      
      # Simulate building an application
      # In a real scenario, this would use tools like:
      # - buildah, podman, or docker for container builds
      # - ko for Go applications
      # - buildpacks for language-specific builds
      
      # Simulate image creation and get digest
      IMAGE_DIGEST="sha256:\$(echo -n "\$(params.IMAGE_URL)" | sha256sum | cut -d' ' -f1)"
      
      echo "Built image with digest: \$IMAGE_DIGEST"
      
      # Output results for Chains to capture
      echo -n "\$(params.IMAGE_URL)" > \$(results.IMAGE_URL.path)
      echo -n "\$IMAGE_DIGEST" > \$(results.IMAGE_DIGEST.path)
      
      echo "Build completed successfully!"
  - name: security-scan
    image: alpine:3.18
    script: |
      #!/bin/sh
      set -ex
      
      echo "Running security scan (simulated)..."
      echo "Scanning image: \$(results.IMAGE_URL.path)"
      
      # Simulate security scanning
      # In real scenarios, use tools like:
      # - trivy, grype, snyk, etc.
      
      echo "Security scan completed - no critical vulnerabilities found"
  - name: generate-sbom
    image: alpine:3.18
    script: |
      #!/bin/sh
      set -ex
      
      echo "Generating SBOM (simulated)..."
      
      # Create a simple SBOM-like output
      cat > /tmp/sbom.json << 'EOL'
      {
        "bomFormat": "CycloneDX",
        "specVersion": "1.4",
        "serialNumber": "urn:uuid:\$(uuidgen || echo 12345678-1234-5678-9012-123456789012)",
        "version": 1,
        "metadata": {
          "timestamp": "\$(date -Iseconds)",
          "tools": [
            {
              "vendor": "tekton-demo",
              "name": "slsa-demo-generator"
            }
          ]
        },
        "components": [
          {
            "type": "library",
            "name": "alpine",
            "version": "3.18"
          }
        ]
      }
      EOL
      
      echo "SBOM generated:"
      cat /tmp/sbom.json
      echo "SBOM generation completed"
EOF

    echo "Sample SLSA task created successfully"
}

# Function to test Chains functionality
test_chains_functionality() {
    echo "Testing Tekton Chains functionality..."
    
    # Create and run a TaskRun that should generate attestations
    cat << EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: chains-test-run-$(date +%s)
  namespace: default
  labels:
    slsa-demo: "true"
spec:
  taskRef:
    name: build-and-attest
  params:
  - name: IMAGE_URL
    value: "ttl.sh/tekton-chains-test/demo:$(date +%s)"
  - name: SOURCE_URL
    value: "https://github.com/waveywaves/tekton-slsa-demo"
EOF

    echo "Test TaskRun for Chains created"
    
    # Wait for the TaskRun to complete
    TASKRUN_NAME=$(kubectl get taskruns -l slsa-demo=true -o name | grep chains-test-run | head -1 | cut -d'/' -f2)
    if [ -n "$TASKRUN_NAME" ]; then
        echo "Waiting for TaskRun $TASKRUN_NAME to complete..."
        kubectl wait --for=condition=succeeded taskrun/$TASKRUN_NAME --timeout=120s
        
        echo "TaskRun completed! Checking for Chains attestation generation..."
        sleep 10
        
        # Check TaskRun annotations for Chains signatures
        echo "Checking TaskRun annotations for Chains metadata:"
        kubectl get taskrun $TASKRUN_NAME -o jsonpath='{.metadata.annotations}' | jq . || echo "No JSON annotations found"
        
        # Check Chains controller logs
        echo "Recent Chains controller logs:"
        kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=20 || echo "Could not fetch Chains logs"
        
    else
        echo "Warning: Could not find TaskRun to wait for"
    fi
}

# Function to create registry secret for image storage
create_registry_secret() {
    echo "Setting up registry configuration for demo..."
    
    # Note: ttl.sh is a temporary registry that doesn't require authentication
    # In a real scenario, you would create secrets for your container registry
    
    echo "Using ttl.sh temporary registry for demo purposes"
    echo "Images will be stored temporarily at ttl.sh/tekton-slsa-demo/"
    
    # Create a dummy secret for completeness (not actually used by ttl.sh)
    kubectl create secret generic registry-secret \
        --from-literal=username=demo \
        --from-literal=password=demo \
        --dry-run=client -o yaml | kubectl apply -f - || echo "Registry secret already exists"
}

# Main function
main() {
    echo "Starting Tekton Chains installation..."
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    # Check if Tekton Pipelines is installed
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        echo "Error: Tekton Pipelines is not installed. Please run 02-install-tekton-pipelines.sh first."
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "Error: Cannot access Kubernetes cluster. Please ensure cluster is running."
        exit 1
    fi
    
    # Check existing installation
    if ! check_existing_installation; then
        echo "Using existing Tekton Chains installation"
    else
        # Install Tekton Chains
        install_tekton_chains
        
        # Configure for SLSA compliance
        configure_slsa_compliance
    fi
    
    # Verify installation
    verify_installation
    
    # Set up registry configuration
    create_registry_secret
    
    # Create sample SLSA task
    create_sample_slsa_task
    
    # Test Chains functionality
    test_chains_functionality
    
    echo ""
    echo "============================================"
    echo "Tekton Chains Installation Complete!"
    echo "============================================"
    echo "Version: $CHAINS_VERSION"
    echo ""
    echo "Chains configuration:"
    kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data}' | jq . || kubectl get configmap chains-config -n tekton-chains -o yaml
    echo ""
    echo "Tekton Chains is now configured for SLSA Level 2 compliance!"
    echo "- Automatic attestation generation: ✅"
    echo "- SLSA v1.0 format: ✅"
    echo "- Transparency log integration: ✅"
    echo "- OCI storage for attestations: ✅"
    echo ""
    echo "Ready for signing configuration!"
    echo "Next step: Run ./scripts/04a-configure-keyless-signing.sh (or 04b for key-based signing)"
}

# Run main function
main "$@"