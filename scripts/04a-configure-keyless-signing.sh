#!/bin/bash

set -x
set -e

echo "============================================"
echo "Configuring Keyless Signing for Tekton Chains"
echo "============================================"

# Function to check if Tekton Chains is installed
check_chains_installation() {
    if ! kubectl get namespace tekton-chains >/dev/null 2>&1; then
        echo "Error: Tekton Chains is not installed. Please run 03-install-tekton-chains.sh first."
        exit 1
    fi
    
    if ! kubectl get deployment tekton-chains-controller -n tekton-chains >/dev/null 2>&1; then
        echo "Error: Tekton Chains controller not found. Please run 03-install-tekton-chains.sh first."
        exit 1
    fi
    
    echo "✅ Tekton Chains installation verified"
}

# Function to configure keyless signing with OIDC
configure_keyless_signing() {
    echo "Configuring Tekton Chains for keyless signing..."
    
    # Disable key-based signing if it was enabled
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"signers.x509.enabled": "false"}}'
    
    # Enable keyless signing with Fulcio
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"signers.x509.fulcio.enabled": "true"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"signers.x509.fulcio.address": "https://fulcio.sigstore.dev"}}'
    
    # Configure Rekor transparency log
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"transparency.enabled": "true"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"transparency.url": "https://rekor.sigstore.dev"}}'
    
    # Configure OIDC issuer (use Kubernetes service account tokens)
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"signers.x509.fulcio.identity.token": "default"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"signers.x509.fulcio.provider": "spiffe"}}'
    
    # Configure signing format
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.signer": "x509"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.signer": "x509"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.signer": "x509"}}'
    
    # Configure SLSA provenance format
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.format": "slsa/v1"}}'
    kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.format": "slsa/v1"}}'
    
    echo "Chains configuration updated for keyless signing"
}

# Function to set up service account for keyless signing
setup_service_account() {
    echo "Setting up service account for keyless signing..."
    
    # Create service account with proper annotations
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-chains-sa
  namespace: default
  annotations:
    chains.tekton.dev/keyless-signing: "true"
automountServiceAccountToken: true
EOF

    # Create RBAC for the service account
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-chains-keyless
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods", "secrets"]
  verbs: ["get", "list"]
- apiGroups: ["tekton.dev"]
  resources: ["taskruns", "pipelineruns"]
  verbs: ["get", "list", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-chains-keyless
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-chains-keyless
subjects:
- kind: ServiceAccount
  name: tekton-chains-sa
  namespace: default
EOF

    echo "Service account and RBAC configured for keyless signing"
}

# Function to restart Chains controller
restart_chains_controller() {
    echo "Restarting Tekton Chains controller to apply keyless configuration..."
    kubectl rollout restart deployment/tekton-chains-controller -n tekton-chains
    kubectl rollout status deployment/tekton-chains-controller -n tekton-chains --timeout=180s
    
    echo "Waiting for Chains controller to stabilize..."
    sleep 15
    
    # Check controller logs for keyless signing setup
    echo "Checking controller logs for keyless signing setup..."
    kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=20 | grep -i "fulcio\|keyless\|x509" || echo "No keyless signing logs found yet"
}

# Function to verify keyless configuration
verify_keyless_config() {
    echo "Verifying keyless signing configuration..."
    
    # Check Chains configuration
    echo "Current Chains keyless configuration:"
    kubectl get configmap chains-config -n tekton-chains -o yaml | grep -A 5 -B 5 "fulcio\|keyless\|x509\|transparency"
    
    # Check service account
    echo "Checking keyless signing service account:"
    kubectl get serviceaccount tekton-chains-sa -o yaml | grep -A 3 -B 3 "annotations"
    
    # Test OIDC token generation (this validates the setup)
    echo "Testing service account token generation..."
    kubectl create token tekton-chains-sa --duration=10m > /tmp/test-token.jwt
    if [ -s /tmp/test-token.jwt ]; then
        echo "✅ Service account token generation successful"
        # Decode the token to check claims (just for verification)
        if command -v jq >/dev/null 2>&1; then
            echo "Token claims (header and payload):"
            cat /tmp/test-token.jwt | cut -d. -f1-2 | sed 's/\./\n/' | while read part; do
                echo "$part" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Could not decode part"
            done
        fi
        rm -f /tmp/test-token.jwt
    else
        echo "⚠️ Service account token generation failed"
    fi
}

# Function to create keyless build task
create_keyless_build_task() {
    echo "Creating enhanced build task for keyless signing..."
    
    # Get the directory where this script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    KEYLESS_TASK_FILE="$SCRIPT_DIR/../k8s/keyless-build-task.yaml"
    
    if [ ! -f "$KEYLESS_TASK_FILE" ]; then
        echo "Error: Keyless build task file not found at $KEYLESS_TASK_FILE"
        exit 1
    fi
    
    kubectl apply -f "$KEYLESS_TASK_FILE"
    echo "Keyless build task created successfully"
}

# Function to test keyless signing
test_keyless_signing() {
    echo "Testing keyless signing with enhanced build task..."
    
    # Create source workspace and test TaskRun
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: keyless-source-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: keyless-signing-test-$(date +%s)
  namespace: default
  labels:
    slsa-demo: "true"
    test-type: "keyless-signing"
spec:
  serviceAccountName: tekton-chains-sa
  taskRef:
    name: keyless-build-sign
  params:
  - name: IMAGE_NAME
    value: "kind-registry:5000/tekton-slsa-demo"
  - name: IMAGE_TAG
    value: "keyless-v1.0.0-$(date +%s)"
  workspaces:
  - name: source
    persistentVolumeClaim:
      claimName: keyless-source-pvc
EOF

    echo "Test TaskRun for keyless signing created"
    
    # Wait for the TaskRun to complete
    TASKRUN_NAME=$(kubectl get taskruns -l test-type=keyless-signing -o name | grep keyless-signing-test | tail -1 | cut -d'/' -f2)
    if [ -n "$TASKRUN_NAME" ]; then
        echo "Waiting for TaskRun $TASKRUN_NAME to complete..."
        kubectl wait --for=condition=succeeded taskrun/$TASKRUN_NAME --timeout=300s
        
        echo "TaskRun completed! Checking for keyless signing results..."
        sleep 20  # Give Chains more time for keyless signing
        
        # Check TaskRun annotations for Chains keyless signatures
        echo "=== Checking TaskRun annotations for keyless signatures ==="
        kubectl get taskrun $TASKRUN_NAME -o jsonpath='{.metadata.annotations}' | jq . || echo "No JSON annotations found"
        
        # Check for keyless signing logs
        echo "=== Recent Chains controller logs after keyless signing ==="
        kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=50 | grep -E "(keyless|fulcio|x509|rekor|transparency)" || echo "No keyless signing logs found"
        
        # Display TaskRun results
        echo "=== Keyless TaskRun Results ==="
        kubectl get taskrun $TASKRUN_NAME -o yaml | grep -A 20 "results:" || echo "No results found"
        
    else
        echo "Warning: Could not find TaskRun to wait for"
    fi
}

# Function to create keyless verification script
create_keyless_verification_script() {
    echo "Creating keyless verification script..."
    
    cat > /tmp/verify-keyless-signatures.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Keyless Signature Verification Script ==="

# Get the latest keyless-signed TaskRun
TASKRUN=$(kubectl get taskruns -l test-type=keyless-signing -o name | tail -1)
if [[ -z "$TASKRUN" ]]; then
    echo "No keyless test TaskRuns found"
    exit 1
fi

echo "Checking keyless TaskRun: $TASKRUN"

# Get TaskRun details
kubectl get $TASKRUN -o yaml > /tmp/keyless-taskrun.yaml

# Check for Chains keyless signatures in annotations
echo "=== Keyless Chains Annotations ==="
kubectl get $TASKRUN -o jsonpath='{.metadata.annotations}' | jq . || echo "No annotations found"

# Look for keyless signature-related annotations
if kubectl get $TASKRUN -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' | grep -q "true"; then
    echo "✅ TaskRun has been signed by Tekton Chains (keyless method)"
    
    # Look for Fulcio/Rekor related annotations
    echo "=== Keyless Signing Details ==="
    kubectl get $TASKRUN -o jsonpath='{.metadata.annotations}' | jq . | grep -E "(fulcio|rekor|transparency|x509)" || echo "No keyless signing details found in annotations"
    
else
    echo "❌ TaskRun has not been signed by Tekton Chains"
fi

# Check for transparency log entries (Rekor)
echo "=== Transparency Log Status ==="
kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=100 | grep -E "(rekor|transparency)" | tail -5 || echo "No transparency log entries found"

echo "=== Keyless Verification completed ==="
EOF

    chmod +x /tmp/verify-keyless-signatures.sh
    echo "Keyless verification script created at /tmp/verify-keyless-signatures.sh"
}

# Main function
main() {
    echo "Starting keyless signing configuration..."
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    # Check Tekton Chains installation
    check_chains_installation
    
    # Configure keyless signing
    configure_keyless_signing
    
    # Set up service account for keyless signing
    setup_service_account
    
    # Restart Chains controller
    restart_chains_controller
    
    # Verify keyless configuration
    verify_keyless_config
    
    # Create keyless build task
    create_keyless_build_task
    
    # Test keyless signing
    test_keyless_signing
    
    # Create keyless verification script
    create_keyless_verification_script
    
    echo ""
    echo "============================================"
    echo "Keyless Signing Configuration Complete!"
    echo "============================================"
    echo ""
    echo "Configuration Summary:"
    echo "- Keyless signing: ✅ Configured with Fulcio and Rekor"
    echo "- Service account: ✅ tekton-chains-sa created for OIDC tokens"
    echo "- Transparency log: ✅ Enabled with Rekor integration"
    echo "- Test TaskRun: ✅ Created and should be keyless-signed"
    echo ""
    echo "Verification:"
    echo "- Run /tmp/verify-keyless-signatures.sh to check keyless signatures"
    echo "- Check 'kubectl get taskruns -l test-type=keyless-signing' for signed TaskRuns"
    echo ""
    echo "Note: Keyless signing depends on external Sigstore services (Fulcio/Rekor)"
    echo "If external services are unavailable, signing may fail gracefully"
    echo ""
    echo "Next step: Run ./scripts/05-deploy-sample-go-app.sh"
    echo "Or for key-based signing: ./scripts/04b-configure-key-signing.sh"
}

# Run main function
main "$@"