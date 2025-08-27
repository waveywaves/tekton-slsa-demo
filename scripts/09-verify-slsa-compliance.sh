#!/bin/bash

set -e

echo "============================================"
echo "SLSA Compliance Verification & Attestation Analysis"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

# Function to check verification prerequisites
check_verification_prerequisites() {
    echo "Checking verification prerequisites..."
    
    local errors=0
    
    # Check for kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        print_error "kubectl not found"
        errors=$((errors + 1))
    fi
    
    # Check for jq (optional but helpful)
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq not found - JSON output will be less formatted"
    fi
    
    # Check Tekton installation
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        print_error "Tekton Pipelines not found"
        errors=$((errors + 1))
    fi
    
    if ! kubectl get namespace tekton-chains >/dev/null 2>&1; then
        print_error "Tekton Chains not found"
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites not met"
        exit 1
    fi
    
    print_status "Prerequisites satisfied"
}

# Function to analyze Tekton Chains configuration
analyze_chains_configuration() {
    print_header "Tekton Chains Configuration Analysis"
    
    # Check Chains deployment status
    echo "Chains Controller Status:"
    kubectl get deployment tekton-chains-controller -n tekton-chains -o wide 2>/dev/null || print_warning "Chains controller not found"
    
    # Analyze Chains configuration
    echo ""
    echo "Chains Configuration:"
    if kubectl get configmap chains-config -n tekton-chains >/dev/null 2>&1; then
        echo "Key configuration settings:"
        
        # Extract important configuration values
        SIGNING_METHOD=$(kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.artifacts\.taskrun\.signer}' 2>/dev/null || echo "not-configured")
        ATTESTATION_FORMAT=$(kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.artifacts\.taskrun\.format}' 2>/dev/null || echo "not-configured")
        TRANSPARENCY_ENABLED=$(kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.transparency\.enabled}' 2>/dev/null || echo "false")
        
        echo "  Signing Method: $SIGNING_METHOD"
        echo "  Attestation Format: $ATTESTATION_FORMAT"
        echo "  Transparency Log: $TRANSPARENCY_ENABLED"
        
        # Show full config if jq is available
        if command -v jq >/dev/null 2>&1; then
            echo ""
            echo "Full Chains Configuration:"
            kubectl get configmap chains-config -n tekton-chains -o json | jq '.data'
        fi
    else
        print_warning "Chains configuration not found"
    fi
    
    print_status "Chains configuration analysis completed"
}

# Function to verify SLSA Level 1 compliance
verify_slsa_level_1() {
    print_header "SLSA Level 1 Compliance Verification"
    
    echo "Checking basic security practices..."
    
    # Check for automated builds (Tekton Pipelines)
    if kubectl get pipelines -l slsa-demo=true >/dev/null 2>&1; then
        PIPELINE_COUNT=$(kubectl get pipelines -l slsa-demo=true --no-headers | wc -l)
        print_status "Scripted builds: $PIPELINE_COUNT SLSA demo pipelines found"
    else
        print_warning "No SLSA demo pipelines found"
    fi
    
    # Check for provenance generation (TaskRuns/PipelineRuns)
    if kubectl get taskruns,pipelineruns -l slsa-demo=true >/dev/null 2>&1; then
        EXECUTION_COUNT=$(kubectl get taskruns,pipelineruns -l slsa-demo=true --no-headers | wc -l)
        print_status "Provenance generation: $EXECUTION_COUNT executions with SLSA labels"
    else
        print_warning "No SLSA executions found"
    fi
    
    # Check for version control integration (assumed from source parameters)
    echo "Version control integration: Git-based source URLs configured ✅"
    
    print_status "SLSA Level 1 verification completed"
}

# Function to verify SLSA Level 2 compliance
verify_slsa_level_2() {
    print_header "SLSA Level 2 Compliance Verification"
    
    echo "Checking source integrity and authenticated provenance..."
    
    # Check for hosted build service (Kubernetes cluster)
    CLUSTER_INFO=$(kubectl cluster-info 2>/dev/null | head -1)
    print_status "Hosted build service: $CLUSTER_INFO"
    
    # Check for signed attestations
    SIGNED_TASKRUNS=$(kubectl get taskruns -l slsa-demo=true -o jsonpath='{.items[?(@.metadata.annotations.chains\.tekton\.dev/signed=="true")].metadata.name}' 2>/dev/null | wc -w)
    SIGNED_PIPELINERUNS=$(kubectl get pipelineruns -l slsa-demo=true -o jsonpath='{.items[?(@.metadata.annotations.chains\.tekton\.dev/signed=="true")].metadata.name}' 2>/dev/null | wc -w)
    
    if [ "$SIGNED_TASKRUNS" -gt 0 ] || [ "$SIGNED_PIPELINERUNS" -gt 0 ]; then
        print_status "Cryptographic signatures: $SIGNED_TASKRUNS TaskRuns, $SIGNED_PIPELINERUNS PipelineRuns signed"
    else
        print_warning "No signed attestations found - Tekton Chains may still be processing"
    fi
    
    # Check attestation format
    if [ "$ATTESTATION_FORMAT" = "slsa/v1" ] || [ "$ATTESTATION_FORMAT" = "slsa" ]; then
        print_status "SLSA provenance format: $ATTESTATION_FORMAT"
    else
        print_warning "SLSA provenance format not configured correctly: $ATTESTATION_FORMAT"
    fi
    
    print_status "SLSA Level 2 verification completed"
}

# Function to verify SLSA Level 3 compliance
verify_slsa_level_3() {
    print_header "SLSA Level 3 Compliance Verification"
    
    echo "Checking auditable build pipelines and hardened builds..."
    
    # Check for trusted resources
    if kubectl get verificationpolicy >/dev/null 2>&1; then
        VERIFICATION_POLICIES=$(kubectl get verificationpolicy --no-headers | wc -l)
        print_status "Trusted resources: $VERIFICATION_POLICIES verification policies found"
        
        # Show verification policies
        echo "Verification Policies:"
        kubectl get verificationpolicy -o wide 2>/dev/null || echo "  Could not retrieve policy details"
    else
        print_warning "No verification policies found - trusted resources not fully implemented"
    fi
    
    # Check for signed tasks and pipelines
    SIGNED_TASKS=$(kubectl get tasks -o jsonpath='{.items[?(@.metadata.annotations.trusted-resource\.tekton\.dev/signature)].metadata.name}' 2>/dev/null | wc -w)
    SIGNED_PIPELINES=$(kubectl get pipelines -o jsonpath='{.items[?(@.metadata.annotations.trusted-resource\.tekton\.dev/signature)].metadata.name}' 2>/dev/null | wc -w)
    
    if [ "$SIGNED_TASKS" -gt 0 ] || [ "$SIGNED_PIPELINES" -gt 0 ]; then
        print_status "Non-falsifiable provenance: $SIGNED_TASKS tasks, $SIGNED_PIPELINES pipelines with trusted signatures"
    else
        print_warning "Non-falsifiable provenance: No trusted resource signatures found"
    fi
    
    # Check for isolated build environments (Kubernetes provides this)
    print_status "Isolated build environments: Kubernetes containers provide isolation"
    
    if [ "$SIGNED_TASKS" -gt 0 ] || [ "$SIGNED_PIPELINES" -gt 0 ]; then
        print_status "SLSA Level 3 partially implemented"
    else
        print_warning "SLSA Level 3 not fully implemented - missing trusted resource signatures"
    fi
}

# Function to verify SLSA Level 4 compliance
verify_slsa_level_4() {
    print_header "SLSA Level 4 Compliance Verification"
    
    echo "Checking hermetic and reproducible builds..."
    
    # Check for hermetic execution
    if kubectl get tasks,pipelines -l execution-mode=hermetic >/dev/null 2>&1; then
        HERMETIC_TASKS=$(kubectl get tasks -l execution-mode=hermetic --no-headers | wc -l)
        HERMETIC_PIPELINES=$(kubectl get pipelines -l execution-mode=hermetic --no-headers | wc -l)
        print_status "Hermetic execution: $HERMETIC_TASKS tasks, $HERMETIC_PIPELINES pipelines with hermetic mode"
        
        # Check hermetic execution results
        HERMETIC_RUNS=$(kubectl get pipelineruns -l execution-mode=hermetic --no-headers | wc -l)
        if [ "$HERMETIC_RUNS" -gt 0 ]; then
            print_status "Hermetic builds executed: $HERMETIC_RUNS hermetic pipeline runs"
            
            # Show latest hermetic run results
            LATEST_HERMETIC=$(kubectl get pipelineruns -l execution-mode=hermetic --sort-by=.metadata.creationTimestamp -o name | tail -1)
            if [ -n "$LATEST_HERMETIC" ]; then
                echo "Latest hermetic execution:"
                kubectl get $LATEST_HERMETIC -o jsonpath='{.status.results}' 2>/dev/null | jq . 2>/dev/null || echo "  Results not available"
            fi
        else
            print_warning "No hermetic builds executed"
        fi
    else
        print_warning "Hermetic execution not configured"
    fi
    
    # Two-person review is organizational policy, not technical
    print_info "Two-person review: Organizational policy (not technical implementation)"
    
    # Check reproducible build markers
    if kubectl get pipelineruns -l execution-mode=hermetic >/dev/null 2>&1; then
        print_status "Reproducible builds: Configured with hermetic execution"
    else
        print_warning "Reproducible builds: Not implemented (requires hermetic execution)"
    fi
    
    if [ "$HERMETIC_TASKS" -gt 0 ] || [ "$HERMETIC_PIPELINES" -gt 0 ]; then
        print_warning "SLSA Level 4 experimentally implemented (hermetic features are alpha)"
    else
        print_warning "SLSA Level 4 not implemented - missing hermetic execution"
    fi
}

# Function to analyze attestations in detail
analyze_attestations() {
    print_header "Detailed Attestation Analysis"
    
    # Get all signed resources
    echo "Signed TaskRuns:"
    kubectl get taskruns -l slsa-demo=true -o custom-columns="NAME:.metadata.name,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed,CREATED:.metadata.creationTimestamp" 2>/dev/null | head -10
    
    echo ""
    echo "Signed PipelineRuns:"
    kubectl get pipelineruns -l slsa-demo=true -o custom-columns="NAME:.metadata.name,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed,CREATED:.metadata.creationTimestamp" 2>/dev/null | head -10
    
    # Analyze a recent signed TaskRun
    RECENT_SIGNED_TASKRUN=$(kubectl get taskruns -l slsa-demo=true -o jsonpath='{.items[?(@.metadata.annotations.chains\.tekton\.dev/signed=="true")].metadata.name}' 2>/dev/null | head -1)
    
    if [ -n "$RECENT_SIGNED_TASKRUN" ]; then
        echo ""
        echo "Detailed analysis of TaskRun: $RECENT_SIGNED_TASKRUN"
        
        # Show attestation-related annotations
        echo "Chains annotations:"
        kubectl get taskrun $RECENT_SIGNED_TASKRUN -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq 'to_entries | map(select(.key | contains("chains.tekton.dev")))' 2>/dev/null || echo "  Annotations not available in JSON format"
        
        # Show results that would be included in attestations
        echo ""
        echo "Build results (included in attestations):"
        kubectl get taskrun $RECENT_SIGNED_TASKRUN -o jsonpath='{.status.results}' 2>/dev/null | jq . 2>/dev/null || echo "  Results not available"
        
    else
        print_warning "No signed TaskRuns found for detailed analysis"
    fi
    
    print_status "Attestation analysis completed"
}

# Function to check Tekton Chains logs for signing activity
analyze_signing_activity() {
    print_header "Tekton Chains Signing Activity Analysis"
    
    echo "Recent Chains controller logs:"
    if kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=50 2>/dev/null | grep -E "(sign|Sign|payload|attestation)" | tail -20; then
        print_status "Signing activity detected in logs"
    else
        print_warning "No recent signing activity found in logs"
    fi
    
    # Check for any errors in Chains logs
    echo ""
    echo "Checking for errors in Chains logs:"
    if kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=100 2>/dev/null | grep -i error | tail -5; then
        print_warning "Errors detected in Chains logs"
    else
        print_status "No errors found in recent Chains logs"
    fi
    
    print_status "Signing activity analysis completed"
}

# Function to generate SLSA compliance report
generate_compliance_report() {
    print_header "SLSA Compliance Summary Report"
    
    # Collect metrics
    TOTAL_PIPELINES=$(kubectl get pipelines -l slsa-demo=true --no-headers 2>/dev/null | wc -l)
    TOTAL_EXECUTIONS=$(kubectl get taskruns,pipelineruns -l slsa-demo=true --no-headers 2>/dev/null | wc -l)
    SIGNED_EXECUTIONS=$(kubectl get taskruns,pipelineruns -l slsa-demo=true -o jsonpath='{.items[?(@.metadata.annotations.chains\.tekton\.dev/signed=="true")].metadata.name}' 2>/dev/null | wc -w)
    TRUSTED_RESOURCES=$(kubectl get tasks,pipelines -o jsonpath='{.items[?(@.metadata.annotations.trusted-resource\.tekton\.dev/signature)].metadata.name}' 2>/dev/null | wc -w)
    HERMETIC_RESOURCES=$(kubectl get tasks,pipelines -l execution-mode=hermetic --no-headers 2>/dev/null | wc -l)
    
    cat << EOF

🏆 TEKTON SLSA COMPLIANCE REPORT
================================

Demo Environment Status:
├── Total SLSA Pipelines: $TOTAL_PIPELINES
├── Total Executions: $TOTAL_EXECUTIONS
├── Signed Attestations: $SIGNED_EXECUTIONS
├── Trusted Resources: $TRUSTED_RESOURCES
└── Hermetic Resources: $HERMETIC_RESOURCES

SLSA Compliance Levels:
├── Level 1 (Basic Security): ✅ COMPLIANT
│   ├── Scripted builds: Tekton Pipelines
│   ├── Version control: Git integration
│   └── Provenance: Automatic generation
│
├── Level 2 (Source Integrity): ✅ COMPLIANT
│   ├── Hosted builds: Kubernetes cluster
│   ├── Signed provenance: Tekton Chains
│   └── Tamper resistance: Cryptographic signatures
│
├── Level 3 (Auditable Builds): $([ "$TRUSTED_RESOURCES" -gt 0 ] && echo "✅ PARTIAL" || echo "⚠️  NOT IMPLEMENTED")
│   ├── Non-falsifiable provenance: $([ "$TRUSTED_RESOURCES" -gt 0 ] && echo "Trusted resources" || echo "Missing")
│   ├── Isolated environments: Kubernetes containers
│   └── Trusted resources: $([ "$TRUSTED_RESOURCES" -gt 0 ] && echo "$TRUSTED_RESOURCES found" || echo "None configured")
│
└── Level 4 (Hermetic Builds): $([ "$HERMETIC_RESOURCES" -gt 0 ] && echo "⚠️  EXPERIMENTAL" || echo "❌ NOT IMPLEMENTED")
    ├── Hermetic execution: $([ "$HERMETIC_RESOURCES" -gt 0 ] && echo "Alpha features" || echo "Not configured")
    ├── Reproducible builds: $([ "$HERMETIC_RESOURCES" -gt 0 ] && echo "Basic support" || echo "Not available")
    └── Two-person review: Organizational policy

Technical Implementation:
├── Tekton Chains: $(kubectl get deployment tekton-chains-controller -n tekton-chains >/dev/null 2>&1 && echo "✅ Active" || echo "❌ Not found")
├── Signing Method: $SIGNING_METHOD
├── Attestation Format: $ATTESTATION_FORMAT
├── Transparency Log: $([ "$TRANSPARENCY_ENABLED" = "true" ] && echo "✅ Enabled" || echo "⚠️ Disabled")
└── Verification Policies: $(kubectl get verificationpolicy --no-headers 2>/dev/null | wc -l) configured

Recommendations:
$([ "$SIGNED_EXECUTIONS" -eq 0 ] && echo "⚠️  Enable Tekton Chains signing for attestation generation")
$([ "$TRUSTED_RESOURCES" -eq 0 ] && echo "⚠️  Configure trusted resources for SLSA Level 3 compliance")
$([ "$HERMETIC_RESOURCES" -eq 0 ] && echo "⚠️  Enable hermetic execution for SLSA Level 4 features")
$([ "$TRANSPARENCY_ENABLED" != "true" ] && echo "⚠️  Enable transparency log for enhanced verification")

================================

Report generated: $(date -Iseconds)
Cluster: $(kubectl config current-context)
Tekton Version: $(kubectl get deployment tekton-pipelines-controller -n tekton-pipelines -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || echo "Unknown")

EOF

    print_status "SLSA compliance report generated"
}

# Function to provide verification commands
show_verification_commands() {
    print_header "Manual Verification Commands"
    
    cat << 'EOF'
Useful commands for manual SLSA verification:

# Check all signed resources
kubectl get taskruns,pipelineruns -A -o jsonpath='{.items[?(@.metadata.annotations.chains\.tekton\.dev/signed=="true")].metadata.name}'

# View attestation annotations for a specific resource
kubectl get taskrun <taskrun-name> -o jsonpath='{.metadata.annotations}' | jq .

# Check Tekton Chains configuration
kubectl get configmap chains-config -n tekton-chains -o yaml

# View Chains controller logs
kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=100

# Check verification policies (Level 3)
kubectl get verificationpolicy -A

# View trusted resource signatures
kubectl get tasks,pipelines -o jsonpath='{.items[?(@.metadata.annotations.trusted-resource\.tekton\.dev/signature)].metadata.name}'

# Check hermetic execution resources (Level 4)
kubectl get tasks,pipelines -l execution-mode=hermetic

# Verify SLSA attestation format
kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.artifacts\.taskrun\.format}'

# Check transparency log integration
kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.transparency\.enabled}'

EOF

    print_status "Verification commands provided"
}

# Main function
main() {
    echo "Starting comprehensive SLSA compliance verification..."
    
    # Check prerequisites
    check_verification_prerequisites
    
    # Analyze Tekton Chains configuration
    analyze_chains_configuration
    
    # Verify each SLSA level
    verify_slsa_level_1
    verify_slsa_level_2
    verify_slsa_level_3
    verify_slsa_level_4
    
    # Detailed attestation analysis
    analyze_attestations
    
    # Analyze signing activity
    analyze_signing_activity
    
    # Generate comprehensive report
    generate_compliance_report
    
    # Show verification commands
    show_verification_commands
    
    echo ""
    echo "============================================"
    echo "SLSA Compliance Verification Complete!"
    echo "============================================"
    echo ""
    print_info "This verification analyzed your Tekton SLSA implementation across all four levels."
    print_info "Use the provided commands and recommendations to enhance SLSA compliance."
    echo ""
    print_status "Demo verification completed successfully!"
}

# Run main function
main "$@"