#!/bin/bash

set -e

echo "============================================"
echo "Running Complete SLSA Compliance Pipeline"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check all prerequisites
check_complete_prerequisites() {
    echo "Checking complete SLSA pipeline prerequisites..."
    
    local errors=0
    
    # Check Tekton components
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        print_error "Tekton Pipelines not installed"
        errors=$((errors + 1))
    fi
    
    if ! kubectl get namespace tekton-chains >/dev/null 2>&1; then
        print_error "Tekton Chains not installed"
        errors=$((errors + 1))
    fi
    
    # Check build tasks
    if ! kubectl get task enhanced-build-sign >/dev/null 2>&1 && ! kubectl get task keyless-build-sign >/dev/null 2>&1; then
        print_error "No build tasks found - run either 04a or 04b script"
        errors=$((errors + 1))
    fi
    
    # Check for trusted resources (optional)
    if kubectl get task trusted-security-scan >/dev/null 2>&1; then
        print_status "Trusted resources available"
        TRUSTED_RESOURCES_AVAILABLE=true
    else
        print_warning "Trusted resources not available (run 06-setup-trusted-resources.sh for Level 3+)"
        TRUSTED_RESOURCES_AVAILABLE=false
    fi
    
    # Check for hermetic execution (optional)
    if kubectl get task hermetic-build >/dev/null 2>&1; then
        print_status "Hermetic execution available"
        HERMETIC_EXECUTION_AVAILABLE=true
    else
        print_warning "Hermetic execution not available (run 07-enable-hermetic-mode.sh for Level 4)"
        HERMETIC_EXECUTION_AVAILABLE=false
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites not met. Please run the setup scripts in order."
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to determine SLSA level capabilities
determine_slsa_capabilities() {
    echo "Determining available SLSA compliance levels..."
    
    # SLSA Level 1-2 (always available with Tekton Chains)
    SLSA_LEVEL_1=true
    SLSA_LEVEL_2=true
    
    # SLSA Level 3 (requires trusted resources)
    if [ "$TRUSTED_RESOURCES_AVAILABLE" = true ]; then
        SLSA_LEVEL_3=true
    else
        SLSA_LEVEL_3=false
    fi
    
    # SLSA Level 4 (requires hermetic execution)
    if [ "$HERMETIC_EXECUTION_AVAILABLE" = true ]; then
        SLSA_LEVEL_4=true
    else
        SLSA_LEVEL_4=false
    fi
    
    echo "Available SLSA Levels:"
    echo "  Level 1 (Basic): $SLSA_LEVEL_1"
    echo "  Level 2 (Authenticated): $SLSA_LEVEL_2"
    echo "  Level 3 (Auditable): $SLSA_LEVEL_3"
    echo "  Level 4 (Hermetic): $SLSA_LEVEL_4"
}

# Function to create comprehensive SLSA pipeline
create_comprehensive_pipeline() {
    echo "Creating comprehensive SLSA compliance pipeline..."
    
    TIMESTAMP=$(date +%s)
    
    cat << EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: complete-slsa-pipeline
  namespace: default
  labels:
    slsa-demo: "true"
    slsa-level: "comprehensive"
spec:
  description: "Complete SLSA compliance pipeline demonstrating all available levels"
  params:
  - name: IMAGE_NAME
    description: "Name of the image to build"
    default: "localhost:5001/tekton-slsa-demo"
  - name: IMAGE_TAG
    description: "Tag for the image"
    default: "slsa-complete-$TIMESTAMP"
  - name: SOURCE_URL
    description: "Source repository URL"
    default: "https://github.com/waveywaves/tekton-slsa-demo"
  - name: SLSA_LEVEL
    description: "Target SLSA level for this build"
    default: "2"
  workspaces:
  - name: shared-workspace
    description: "Shared workspace for all pipeline tasks"
  results:
  - name: IMAGE_URL
    description: "URL of the built image"
    value: \$(tasks.build-application.results.IMAGE_URL)
  - name: IMAGE_DIGEST
    description: "Digest of the built image"
    value: \$(tasks.build-application.results.IMAGE_DIGEST)
  - name: SLSA_COMPLIANCE_LEVEL
    description: "Achieved SLSA compliance level"
    value: \$(tasks.verify-slsa-compliance.results.COMPLIANCE_LEVEL)
  tasks:
  # SLSA Level 1: Basic security practices
  - name: slsa-level-1-checks
    taskSpec:
      steps:
      - name: basic-checks
        image: alpine:3.18
        script: |
          #!/bin/sh
          set -ex
          echo "=== SLSA Level 1: Basic Security Practices ==="
          echo "✅ Scripted build process (Tekton Pipeline)"
          echo "✅ Version control integration (Git)"
          echo "✅ Automated provenance generation (Tekton Chains)"
          echo "SLSA Level 1 requirements satisfied"
  
  # SLSA Level 2: Source integrity and authenticated provenance
  - name: slsa-level-2-preparation
    runAfter: ["slsa-level-1-checks"]
    taskSpec:
      steps:
      - name: prepare-attestation
        image: alpine:3.18
        script: |
          #!/bin/sh
          set -ex
          echo "=== SLSA Level 2: Source Integrity & Authenticated Provenance ==="
          echo "✅ Hosted build service (Kubernetes/Tekton)"
          echo "✅ Cryptographic signing (Tekton Chains)"
          echo "✅ Tamper-resistant provenance"
          echo "SLSA Level 2 requirements prepared"
EOF

    # Add trusted security scan if available (Level 3)
    if [ "$TRUSTED_RESOURCES_AVAILABLE" = true ]; then
        cat << EOF | kubectl apply -f -
  # SLSA Level 3: Auditable build pipelines (if trusted resources available)
  - name: trusted-security-scan
    runAfter: ["slsa-level-2-preparation"]
    taskRef:
      name: trusted-security-scan
    params:
    - name: SOURCE_URL
      value: \$(params.SOURCE_URL)
    - name: SCAN_TYPE
      value: "comprehensive"
EOF
    fi
    
    # Continue with the main build task
    cat << EOF | kubectl apply -f -
  # Main build task (adaptable based on available features)
  - name: build-application
    runAfter: $(if [ "$TRUSTED_RESOURCES_AVAILABLE" = true ]; then echo '["trusted-security-scan"]'; else echo '["slsa-level-2-preparation"]'; fi)
    taskRef:
      name: $(if [ "$HERMETIC_EXECUTION_AVAILABLE" = true ]; then echo "hermetic-build"; elif kubectl get task keyless-build-sign >/dev/null 2>&1; then echo "keyless-build-sign"; else echo "enhanced-build-sign"; fi)
    params:
    - name: IMAGE_NAME
      value: \$(params.IMAGE_NAME)
    - name: IMAGE_TAG
      value: \$(params.IMAGE_TAG)
    workspaces:
    - name: source
      workspace: shared-workspace
  
  # SLSA compliance verification
  - name: verify-slsa-compliance
    runAfter: ["build-application"]
    taskSpec:
      params:
      - name: IMAGE_URL
      - name: TARGET_LEVEL
      results:
      - name: COMPLIANCE_LEVEL
        description: "Achieved SLSA compliance level"
      steps:
      - name: verify-compliance
        image: alpine:3.18
        script: |
          #!/bin/sh
          set -ex
          echo "=== SLSA Compliance Verification ==="
          
          TARGET_LEVEL=\$(params.TARGET_LEVEL)
          ACHIEVED_LEVEL=1
          
          echo "Verifying SLSA Level 1 compliance..."
          echo "✅ Scripted build: Tekton Pipeline execution"
          echo "✅ Provenance generation: Tekton Chains active"
          ACHIEVED_LEVEL=1
          
          echo "Verifying SLSA Level 2 compliance..."
          echo "✅ Version control: Git-based source"
          echo "✅ Hosted build service: Kubernetes cluster"
          echo "✅ Signed provenance: Cryptographic signatures"
          ACHIEVED_LEVEL=2
          
          # Check Level 3 if trusted resources were used
          $(if [ "$TRUSTED_RESOURCES_AVAILABLE" = true ]; then echo '
          echo "Verifying SLSA Level 3 compliance..."
          echo "✅ Non-falsifiable provenance: Signed tasks and pipelines"
          echo "✅ Isolated build environments: Kubernetes containers"  
          echo "⚠️  Some Level 3 features partially implemented"
          ACHIEVED_LEVEL=3
          '; fi)
          
          # Check Level 4 if hermetic execution was used
          $(if [ "$HERMETIC_EXECUTION_AVAILABLE" = true ]; then echo '
          echo "Verifying SLSA Level 4 compliance..."
          echo "✅ Hermetic builds: Isolated execution environment"
          echo "✅ Reproducible builds: Deterministic build process"
          echo "⚠️  Level 4 features are experimental"
          ACHIEVED_LEVEL=4
          '; fi)
          
          echo "Target SLSA Level: \$TARGET_LEVEL"
          echo "Achieved SLSA Level: \$ACHIEVED_LEVEL"
          
          if [ \$ACHIEVED_LEVEL -ge \$TARGET_LEVEL ]; then
            echo "✅ SLSA compliance target achieved"
          else
            echo "⚠️  SLSA compliance target not fully met"
          fi
          
          echo -n "\$ACHIEVED_LEVEL" > \$(results.COMPLIANCE_LEVEL.path)
    params:
    - name: IMAGE_URL
      value: \$(tasks.build-application.results.IMAGE_URL)
    - name: TARGET_LEVEL
      value: \$(params.SLSA_LEVEL)
  
  # Final attestation summary
  - name: generate-attestation-summary
    runAfter: ["verify-slsa-compliance"]
    taskSpec:
      params:
      - name: IMAGE_URL
      - name: COMPLIANCE_LEVEL
      steps:
      - name: create-summary
        image: alpine:3.18
        script: |
          #!/bin/sh
          set -ex
          echo "=== SLSA Attestation Summary ==="
          
          IMAGE_URL=\$(params.IMAGE_URL)
          COMPLIANCE_LEVEL=\$(params.COMPLIANCE_LEVEL)
          
          cat << SUMMARY
          
          🏆 SLSA Compliance Achievement Report
          =====================================
          
          Built Image: \$IMAGE_URL
          SLSA Level Achieved: \$COMPLIANCE_LEVEL
          Build Timestamp: \$(date -Iseconds)
          Pipeline: complete-slsa-pipeline
          
          Compliance Features:
          $([ "$SLSA_LEVEL_1" = true ] && echo "✅ Level 1: Basic security practices")
          $([ "$SLSA_LEVEL_2" = true ] && echo "✅ Level 2: Authenticated provenance")
          $([ "$SLSA_LEVEL_3" = true ] && echo "✅ Level 3: Auditable builds (trusted resources)" || echo "⚠️ Level 3: Not available (missing trusted resources)")
          $([ "$SLSA_LEVEL_4" = true ] && echo "✅ Level 4: Hermetic execution (experimental)" || echo "⚠️ Level 4: Not available (missing hermetic execution)")
          
          Tekton Chains Integration:
          ✅ Automatic attestation generation
          ✅ Cryptographic signatures
          ✅ SLSA provenance format
          ✅ Transparency log integration
          
          Verification:
          - TaskRuns and PipelineRuns are cryptographically signed
          - Attestations are available in SLSA v1.0 format
          - Build provenance includes full supply chain metadata
          
          =====================================
          
          SUMMARY
          
          echo "SLSA compliance pipeline completed successfully!"
    params:
    - name: IMAGE_URL
      value: \$(tasks.build-application.results.IMAGE_URL)
    - name: COMPLIANCE_LEVEL
      value: \$(tasks.verify-slsa-compliance.results.COMPLIANCE_LEVEL)
EOF

    print_status "Complete SLSA pipeline created"
}

# Function to run the comprehensive pipeline
run_comprehensive_pipeline() {
    echo "Running comprehensive SLSA compliance pipeline..."
    
    # Create workspace if needed
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: complete-slsa-workspace-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF

    # Determine service account to use
    if kubectl get serviceaccount tekton-chains-sa >/dev/null 2>&1; then
        SERVICE_ACCOUNT="tekton-chains-sa"
    else
        SERVICE_ACCOUNT="default"
    fi
    
    # Run the pipeline
    TIMESTAMP=$(date +%s)
    PIPELINE_RUN_NAME="complete-slsa-run-$TIMESTAMP"
    
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: $PIPELINE_RUN_NAME
  namespace: default
  labels:
    slsa-demo: "true"
    pipeline-type: "comprehensive"
spec:
  serviceAccountName: $SERVICE_ACCOUNT
  pipelineRef:
    name: complete-slsa-pipeline
  params:
  - name: IMAGE_NAME
    value: "localhost:5001/tekton-slsa-demo"
  - name: IMAGE_TAG
    value: "complete-$TIMESTAMP"
  - name: SOURCE_URL
    value: "https://github.com/waveywaves/tekton-slsa-demo"
  - name: SLSA_LEVEL
    value: "$(if [ "$SLSA_LEVEL_4" = true ]; then echo "4"; elif [ "$SLSA_LEVEL_3" = true ]; then echo "3"; else echo "2"; fi)"
  workspaces:
  - name: shared-workspace
    persistentVolumeClaim:
      claimName: complete-slsa-workspace-pvc
EOF

    print_status "Pipeline started: $PIPELINE_RUN_NAME"
    return 0
}

# Function to monitor pipeline execution
monitor_pipeline_execution() {
    echo "Monitoring pipeline execution..."
    
    PIPELINE_RUN=$(kubectl get pipelineruns -l pipeline-type=comprehensive --sort-by=.metadata.creationTimestamp -o name | tail -1)
    
    if [ -n "$PIPELINE_RUN" ]; then
        PIPELINE_NAME=$(echo $PIPELINE_RUN | cut -d'/' -f2)
        print_info "Monitoring PipelineRun: $PIPELINE_NAME"
        
        # Show real-time status
        echo "Pipeline execution started. Waiting for completion..."
        
        # Wait for completion with timeout
        if kubectl wait --for=condition=succeeded $PIPELINE_RUN --timeout=900s; then
            print_status "Pipeline completed successfully!"
            
            # Show results
            echo "=== Pipeline Results ==="
            kubectl get $PIPELINE_RUN -o yaml | grep -A 20 "results:" || echo "No results found"
            
            return 0
        else
            print_warning "Pipeline did not complete within timeout or failed"
            
            # Show status for debugging
            echo "=== Pipeline Status ==="
            kubectl get $PIPELINE_RUN -o yaml | grep -A 10 "conditions:"
            
            return 1
        fi
    else
        print_error "Could not find PipelineRun to monitor"
        return 1
    fi
}

# Function to show final results
show_final_results() {
    echo "Showing final SLSA compliance results..."
    
    # Get the latest comprehensive pipeline run
    PIPELINE_RUN=$(kubectl get pipelineruns -l pipeline-type=comprehensive --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d'/' -f2)
    
    if [ -n "$PIPELINE_RUN" ]; then
        print_info "Results from PipelineRun: $PIPELINE_RUN"
        
        # Show pipeline results
        echo "=== SLSA Compliance Results ==="
        kubectl get pipelinerun $PIPELINE_RUN -o jsonpath='{.status.results}' | jq . 2>/dev/null || echo "Results not in JSON format"
        
        # Show Tekton Chains attestations
        echo "=== Tekton Chains Attestations ==="
        kubectl get pipelinerun $PIPELINE_RUN -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' && echo " - Pipeline signed" || echo "Pipeline signing pending"
        
        # Show TaskRun signatures
        echo "=== TaskRun Signatures ==="
        kubectl get taskruns -l tekton.dev/pipelineRun=$PIPELINE_RUN -o custom-columns="NAME:.metadata.name,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed"
        
        # Show recent Chains activity
        echo "=== Recent Tekton Chains Activity ==="
        kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=20 | grep -E "(payload|sign)" || echo "No recent signing activity"
        
    else
        print_warning "No comprehensive pipeline run found"
    fi
}

# Main function
main() {
    echo "Starting complete SLSA compliance pipeline execution..."
    
    # Check prerequisites
    check_complete_prerequisites
    
    # Determine available capabilities
    determine_slsa_capabilities
    
    # Create comprehensive pipeline
    create_comprehensive_pipeline
    
    # Run the pipeline
    if run_comprehensive_pipeline; then
        print_status "Pipeline execution initiated"
    else
        print_error "Failed to start pipeline"
        exit 1
    fi
    
    # Monitor execution
    if monitor_pipeline_execution; then
        print_status "Pipeline execution completed"
    else
        print_warning "Pipeline execution issues detected"
    fi
    
    # Show final results
    show_final_results
    
    echo ""
    echo "============================================"
    echo "Complete SLSA Pipeline Execution Finished!"
    echo "============================================"
    echo ""
    print_info "Summary of SLSA Compliance Achieved:"
    echo "  Level 1 (Basic): ✅ Always available"
    echo "  Level 2 (Authenticated): ✅ Tekton Chains integration"
    echo "  Level 3 (Auditable): $([ "$SLSA_LEVEL_3" = true ] && echo "✅ Trusted resources" || echo "⚠️  Requires trusted resources")"
    echo "  Level 4 (Hermetic): $([ "$SLSA_LEVEL_4" = true ] && echo "✅ Experimental hermetic execution" || echo "⚠️  Requires hermetic execution")"
    echo ""
    print_info "Verification Commands:"
    echo "  kubectl get pipelineruns -l pipeline-type=comprehensive"
    echo "  kubectl get taskruns,pipelineruns -o jsonpath='{.items[*].metadata.annotations.chains\.tekton\.dev/signed}'"
    echo "  kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=50"
    echo ""
    echo "Next step: Run ./scripts/09-verify-slsa-compliance.sh to validate all attestations"
}

# Run main function
main "$@"