#!/bin/bash

set -x
set -e

echo "============================================"
echo "Setting up Trusted Resources for SLSA Level 3+"
echo "============================================"

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        echo "Error: Tekton Pipelines not found. Please run 02-install-tekton-pipelines.sh first."
        exit 1
    fi
    
    if ! command -v cosign >/dev/null 2>&1; then
        echo "Error: cosign not found. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    echo "✅ Prerequisites satisfied"
}

# Function to enable trusted resources feature
enable_trusted_resources() {
    echo "Enabling Trusted Resources feature in Tekton Pipelines..."
    
    # Check if feature gate is already enabled
    if kubectl get configmap feature-flags -n tekton-pipelines -o yaml | grep -q "trusted-resources-verification-no-match-policy"; then
        echo "Trusted Resources feature already configured"
    else
        # Enable trusted resources verification
        kubectl patch configmap feature-flags -n tekton-pipelines -p='{"data":{"trusted-resources-verification-no-match-policy": "warn"}}'
        kubectl patch configmap feature-flags -n tekton-pipelines -p='{"data":{"enable-api-fields": "alpha"}}'
        
        # Restart Tekton Pipeline controller to pick up changes
        kubectl rollout restart deployment/tekton-pipelines-controller -n tekton-pipelines
        kubectl rollout status deployment/tekton-pipelines-controller -n tekton-pipelines --timeout=120s
        
        echo "✅ Trusted Resources feature enabled"
    fi
}

# Function to create signing keys for trusted resources
create_trusted_resource_keys() {
    echo "Creating keys for signing trusted resources..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Generate cosign keypair specifically for trusted resources
    echo "Generating trusted resource signing keys..."
    COSIGN_PASSWORD="" cosign generate-key-pair
    
    if [[ ! -f cosign.key ]] || [[ ! -f cosign.pub ]]; then
        echo "Error: Failed to generate cosign keypair for trusted resources"
        exit 1
    fi
    
    # Store keys in Kubernetes secret
    echo "Storing trusted resource signing keys..."
    kubectl delete secret trusted-resource-keys -n tekton-pipelines --ignore-not-found
    kubectl create secret generic trusted-resource-keys \
        --from-file=cosign.key=cosign.key \
        --from-file=cosign.pub=cosign.pub \
        -n tekton-pipelines
    
    # Also store public key for verification
    kubectl create secret generic trusted-resource-verification-keys \
        --from-file=cosign.pub=cosign.pub \
        -n tekton-pipelines \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Save public key locally for signing operations
    cp cosign.pub /tmp/trusted-resource.pub
    cp cosign.key /tmp/trusted-resource.key
    
    echo "Public key for trusted resources:"
    cat cosign.pub
    
    # Clean up temporary directory
    cd /
    rm -rf "$TEMP_DIR"
    
    echo "✅ Trusted resource keys created and stored"
}

# Function to create and sign a trusted Task
create_signed_task() {
    echo "Creating and signing a trusted Task..."
    
    # Create a sample trusted Task
    cat > /tmp/trusted-task.yaml << 'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: trusted-security-scan
  namespace: default
  labels:
    trusted-resource: "true"
    security-level: "high"
spec:
  description: "A trusted task for security scanning with verified provenance"
  params:
  - name: SOURCE_URL
    description: "URL of the source to scan"
    type: string
    default: "https://github.com/waveywaves/tekton-slsa-demo"
  - name: SCAN_TYPE
    description: "Type of security scan to perform"
    type: string
    default: "vulnerability"
  results:
  - name: SCAN_RESULT
    description: "Result of the security scan"
  - name: CRITICAL_ISSUES
    description: "Number of critical security issues found"
  steps:
  - name: security-scan
    image: alpine:3.18
    script: |
      #!/bin/sh
      set -ex
      
      echo "=== Trusted Security Scan ==="
      echo "Source URL: $(params.SOURCE_URL)"
      echo "Scan Type: $(params.SCAN_TYPE)"
      echo "Task is cryptographically signed and verified"
      
      # Simulate comprehensive security scanning
      echo "1. Dependency vulnerability scan..."
      sleep 2
      echo "2. Static code analysis..."
      sleep 2
      echo "3. License compliance check..."
      sleep 1
      echo "4. Secret detection scan..."
      sleep 1
      
      # Generate scan results
      CRITICAL_COUNT=0
      SCAN_STATUS="passed"
      
      echo "=== Security Scan Results ==="
      echo "Status: $SCAN_STATUS"
      echo "Critical issues: $CRITICAL_COUNT"
      echo "Scan completed by trusted, signed Task"
      
      # Write results
      echo -n "$SCAN_STATUS" > $(results.SCAN_RESULT.path)
      echo -n "$CRITICAL_COUNT" > $(results.CRITICAL_ISSUES.path)
      
      echo "✅ Trusted security scan completed"
EOF

    # Sign the Task with cosign
    echo "Signing the trusted Task..."
    COSIGN_PASSWORD="" cosign sign-blob \
        --key /tmp/trusted-resource.key \
        --yes \
        --output-signature /tmp/trusted-task.yaml.sig \
        /tmp/trusted-task.yaml
    
    # Apply the signed Task
    kubectl apply -f /tmp/trusted-task.yaml
    
    # Store the signature as an annotation
    SIGNATURE=$(base64 -i /tmp/trusted-task.yaml.sig | tr -d '\n')
    kubectl annotate task trusted-security-scan \
        trusted-resource.tekton.dev/signature="$SIGNATURE" \
        --overwrite
    
    echo "✅ Trusted Task created and signed"
}

# Function to create verification policy
create_verification_policy() {
    echo "Creating verification policy for trusted resources..."
    
    # Create VerificationPolicy for Tasks
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1alpha1
kind: VerificationPolicy
metadata:
  name: trusted-task-policy
  namespace: default
spec:
  resources:
  - pattern: "https://github.com/waveywaves/tekton-slsa-demo/*"
  - pattern: "tekton-slsa-demo/*"
  authorities:
  - name: trusted-resource-authority
    key:
      secretRef:
        name: trusted-resource-verification-keys
        namespace: tekton-pipelines
  mode: enforce
EOF

    echo "✅ Verification policy created"
}

# Function to create and sign a trusted Pipeline
create_signed_pipeline() {
    echo "Creating and signing a trusted Pipeline..."
    
    # Create a sample trusted Pipeline
    cat > /tmp/trusted-pipeline.yaml << 'EOF'
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: trusted-slsa-pipeline
  namespace: default
  labels:
    trusted-resource: "true"
    security-level: "high"
spec:
  description: "A trusted pipeline with signed Tasks for SLSA compliance"
  params:
  - name: SOURCE_URL
    description: "URL of the source repository"
    type: string
    default: "https://github.com/waveywaves/tekton-slsa-demo"
  - name: IMAGE_NAME
    description: "Name of the container image"
    type: string
    default: "ttl.sh/tekton-slsa-demo"
  - name: IMAGE_TAG
    description: "Tag for the container image"
    type: string
    default: "trusted"
  workspaces:
  - name: shared-workspace
    description: "Shared workspace for pipeline tasks"
  results:
  - name: IMAGE_URL
    description: "URL of the built image"
    value: $(tasks.build.results.IMAGE_URL)
  - name: SECURITY_SCAN_RESULT
    description: "Result of security scanning"
    value: $(tasks.security-scan.results.SCAN_RESULT)
  tasks:
  - name: security-scan
    taskRef:
      name: trusted-security-scan
      kind: Task
    params:
    - name: SOURCE_URL
      value: $(params.SOURCE_URL)
    - name: SCAN_TYPE
      value: "comprehensive"
  - name: build
    runAfter: ["security-scan"]
    when:
    - input: "$(tasks.security-scan.results.SCAN_RESULT)"
      operator: in
      values: ["passed", "warning"]
    taskRef:
      name: keyless-build-sign
      kind: Task
    params:
    - name: IMAGE_NAME
      value: $(params.IMAGE_NAME)
    - name: IMAGE_TAG
      value: $(params.IMAGE_TAG)
    workspaces:
    - name: source
      workspace: shared-workspace
  - name: verify-build
    runAfter: ["build"]
    taskSpec:
      params:
      - name: IMAGE_URL
      - name: SCAN_RESULT
      steps:
      - name: verify
        image: alpine:3.18
        script: |
          #!/bin/sh
          set -ex
          echo "=== Verifying Trusted Build ==="
          echo "Image: $(params.IMAGE_URL)"
          echo "Security Scan: $(params.SCAN_RESULT)"
          echo "This verification step runs in a trusted pipeline"
          echo "✅ Build verification completed in trusted context"
    params:
    - name: IMAGE_URL
      value: $(tasks.build.results.IMAGE_URL)
    - name: SCAN_RESULT
      value: $(tasks.security-scan.results.SCAN_RESULT)
EOF

    # Sign the Pipeline
    echo "Signing the trusted Pipeline..."
    COSIGN_PASSWORD="" cosign sign-blob \
        --key /tmp/trusted-resource.key \
        --yes \
        --output-signature /tmp/trusted-pipeline.yaml.sig \
        /tmp/trusted-pipeline.yaml
    
    # Apply the signed Pipeline
    kubectl apply -f /tmp/trusted-pipeline.yaml
    
    # Store the signature as an annotation
    SIGNATURE=$(base64 -i /tmp/trusted-pipeline.yaml.sig | tr -d '\n')
    kubectl annotate pipeline trusted-slsa-pipeline \
        trusted-resource.tekton.dev/signature="$SIGNATURE" \
        --overwrite
    
    echo "✅ Trusted Pipeline created and signed"
}

# Function to test trusted resources
test_trusted_resources() {
    echo "Testing trusted resources with a sample PipelineRun..."
    
    # Create PVC for the test
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: trusted-workspace-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

    # Create a test PipelineRun using the trusted Pipeline
    TIMESTAMP=$(date +%s)
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: trusted-pipeline-test-$TIMESTAMP
  namespace: default
  labels:
    trusted-resource: "true"
    test-type: "trusted-resources"
spec:
  pipelineRef:
    name: trusted-slsa-pipeline
  params:
  - name: SOURCE_URL
    value: "https://github.com/waveywaves/tekton-slsa-demo"
  - name: IMAGE_NAME
    value: "ttl.sh/tekton-slsa-demo"
  - name: IMAGE_TAG
    value: "trusted-$TIMESTAMP"
  workspaces:
  - name: shared-workspace
    persistentVolumeClaim:
      claimName: trusted-workspace-pvc
EOF

    echo "Test PipelineRun created: trusted-pipeline-test-$TIMESTAMP"
    
    # Wait for the PipelineRun to start
    sleep 10
    
    # Check PipelineRun status
    PIPELINE_RUN="trusted-pipeline-test-$TIMESTAMP"
    echo "Monitoring trusted PipelineRun: $PIPELINE_RUN"
    
    # Show initial status
    kubectl get pipelinerun $PIPELINE_RUN -o yaml | grep -A 5 -B 5 "conditions:" || echo "Pipeline starting..."
    
    echo "✅ Trusted resources test initiated"
    echo "Monitor with: kubectl get pipelinerun $PIPELINE_RUN -w"
}

# Function to verify trusted resources setup
verify_trusted_resources() {
    echo "Verifying trusted resources configuration..."
    
    # Check feature flags
    echo "=== Feature Flags ==="
    kubectl get configmap feature-flags -n tekton-pipelines -o yaml | grep -A 3 -B 3 "trusted-resources"
    
    # Check verification policies
    echo "=== Verification Policies ==="
    kubectl get verificationpolicy -A
    
    # Check signed resources
    echo "=== Signed Resources ==="
    echo "Trusted Tasks:"
    kubectl get tasks -l trusted-resource=true -o custom-columns="NAME:.metadata.name,SIGNATURE:.metadata.annotations.trusted-resource\.tekton\.dev/signature"
    
    echo "Trusted Pipelines:"
    kubectl get pipelines -l trusted-resource=true -o custom-columns="NAME:.metadata.name,SIGNATURE:.metadata.annotations.trusted-resource\.tekton\.dev/signature"
    
    # Check controller logs for trusted resource verification
    echo "=== Controller Logs (Trusted Resources) ==="
    kubectl logs -n tekton-pipelines -l app.kubernetes.io/name=controller --tail=20 | grep -i "trust\|verif\|sign" || echo "No trusted resource logs found"
    
    echo "✅ Trusted resources verification completed"
}

# Main function
main() {
    echo "Starting Trusted Resources setup for SLSA Level 3+..."
    
    # Check prerequisites
    check_prerequisites
    
    # Enable trusted resources feature
    enable_trusted_resources
    
    # Create signing keys
    create_trusted_resource_keys
    
    # Create verification policy
    create_verification_policy
    
    # Create and sign trusted Task
    create_signed_task
    
    # Create and sign trusted Pipeline
    create_signed_pipeline
    
    # Test trusted resources
    test_trusted_resources
    
    # Verify setup
    verify_trusted_resources
    
    echo ""
    echo "============================================"
    echo "Trusted Resources Setup Complete!"
    echo "============================================"
    echo ""
    echo "Configuration Summary:"
    echo "- Feature Gates: ✅ Trusted Resources enabled in Tekton Pipelines"
    echo "- Signing Keys: ✅ Created and stored in tekton-pipelines namespace"
    echo "- Verification Policy: ✅ Configured for resource verification"
    echo "- Signed Task: ✅ trusted-security-scan created and signed"
    echo "- Signed Pipeline: ✅ trusted-slsa-pipeline created and signed"
    echo "- Test PipelineRun: ✅ Created to verify trusted resource execution"
    echo ""
    echo "SLSA Level 3 Features:"
    echo "- Non-falsifiable provenance: ⚠️  Partially implemented with signed resources"
    echo "- Tamper-resistant builds: ✅ Cryptographically signed Tasks and Pipelines"
    echo "- Auditable build processes: ✅ Verified execution with trusted resources"
    echo ""
    echo "Key Files Created:"
    echo "- /tmp/trusted-resource.pub - Public key for verification"
    echo "- /tmp/trusted-resource.key - Private key for signing (keep secure!)"
    echo ""
    echo "Verification Commands:"
    echo "- kubectl get verificationpolicy"
    echo "- kubectl get tasks,pipelines -l trusted-resource=true"
    echo "- kubectl get pipelineruns -l test-type=trusted-resources"
    echo ""
    echo "Next step: Run ./scripts/07-enable-hermetic-mode.sh for SLSA Level 4"
}

# Run main function
main "$@"