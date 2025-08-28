#!/bin/bash

set -e

echo "============================================"
echo "Component Validation Script"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for colored output
print_status() {
    local status="$1"
    local message="$2"
    case $status in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC}: $message"
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC}: $message"
            return 1
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC}: $message"
            ;;
        "INFO")
            echo -e "ℹ️  INFO: $message"
            ;;
    esac
}

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "Test $TOTAL_TESTS: $test_name"
    echo "----------------------------------------"
    
    if eval "$test_command"; then
        print_status "PASS" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_status "FAIL" "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Test 1: Check Prerequisites
test_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    for tool in kubectl kind docker cosign; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_status "PASS" "$tool is installed"
        else
            print_status "FAIL" "$tool is not installed"
            return 1
        fi
    done
    
    # Test kubectl connectivity
    if kubectl cluster-info >/dev/null 2>&1; then
        print_status "PASS" "kubectl can connect to cluster"
    else
        print_status "FAIL" "kubectl cannot connect to cluster"
        return 1
    fi
    
    return 0
}

# Test 2: Check Kind Cluster
test_kind_cluster() {
    print_status "INFO" "Checking Kind cluster..."
    
    # Check if kind cluster exists
    if kind get clusters | grep -q "tekton-slsa-demo"; then
        print_status "PASS" "Kind cluster 'tekton-slsa-demo' exists"
    else
        print_status "FAIL" "Kind cluster 'tekton-slsa-demo' not found"
        return 1
    fi
    
    # Check cluster nodes
    if kubectl get nodes | grep -q Ready; then
        print_status "PASS" "Cluster nodes are ready"
        kubectl get nodes --no-headers | while read line; do
            echo "  $line"
        done
    else
        print_status "FAIL" "Cluster nodes are not ready"
        return 1
    fi
    
    return 0
}

# Test 3: Check Local Registry
test_local_registry() {
    print_status "INFO" "Checking local container registry..."
    
    # Check if registry container is running
    if docker ps | grep -q "kind-registry"; then
        print_status "PASS" "Registry container is running"
    else
        print_status "FAIL" "Registry container is not running"
        return 1
    fi
    
    # Test registry connectivity from host
    if curl -f http://localhost:5001/v2/ >/dev/null 2>&1; then
        print_status "PASS" "Registry accessible from host (localhost:5001)"
    else
        print_status "WARN" "Registry not accessible from host"
    fi
    
    # Test registry connectivity from cluster
    if kubectl run registry-test --image=curlimages/curl:latest --rm -i --restart=Never --timeout=30s --command -- curl -f http://kind-registry:5000/v2/ >/dev/null 2>&1; then
        print_status "PASS" "Registry accessible from cluster (kind-registry:5000)"
    else
        print_status "FAIL" "Registry not accessible from cluster"
        return 1
    fi
    
    return 0
}

# Test 4: Check Tekton Pipelines
test_tekton_pipelines() {
    print_status "INFO" "Checking Tekton Pipelines installation..."
    
    # Check namespace
    if kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        print_status "PASS" "tekton-pipelines namespace exists"
    else
        print_status "FAIL" "tekton-pipelines namespace not found"
        return 1
    fi
    
    # Check controller deployment
    if kubectl get deployment tekton-pipelines-controller -n tekton-pipelines >/dev/null 2>&1; then
        if kubectl get deployment tekton-pipelines-controller -n tekton-pipelines -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
            print_status "PASS" "Tekton Pipelines controller is ready"
        else
            print_status "FAIL" "Tekton Pipelines controller is not ready"
            return 1
        fi
    else
        print_status "FAIL" "Tekton Pipelines controller not found"
        return 1
    fi
    
    # Check webhook deployment
    if kubectl get deployment tekton-pipelines-webhook -n tekton-pipelines >/dev/null 2>&1; then
        if kubectl get deployment tekton-pipelines-webhook -n tekton-pipelines -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
            print_status "PASS" "Tekton Pipelines webhook is ready"
        else
            print_status "FAIL" "Tekton Pipelines webhook is not ready"
            return 1
        fi
    else
        print_status "FAIL" "Tekton Pipelines webhook not found"
        return 1
    fi
    
    return 0
}

# Test 5: Check Tekton Chains
test_tekton_chains() {
    print_status "INFO" "Checking Tekton Chains installation..."
    
    # Check namespace
    if kubectl get namespace tekton-chains >/dev/null 2>&1; then
        print_status "PASS" "tekton-chains namespace exists"
    else
        print_status "FAIL" "tekton-chains namespace not found"
        return 1
    fi
    
    # Check controller deployment
    if kubectl get deployment tekton-chains-controller -n tekton-chains >/dev/null 2>&1; then
        if kubectl get deployment tekton-chains-controller -n tekton-chains -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
            print_status "PASS" "Tekton Chains controller is ready"
        else
            print_status "FAIL" "Tekton Chains controller is not ready"
            return 1
        fi
    else
        print_status "FAIL" "Tekton Chains controller not found"
        return 1
    fi
    
    # Check configuration
    if kubectl get configmap chains-config -n tekton-chains >/dev/null 2>&1; then
        print_status "PASS" "Tekton Chains configuration exists"
        
        # Show current signing configuration
        echo "  Current signing configuration:"
        kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data}' | jq -r 'to_entries[] | select(.key | contains("signer")) | "    \(.key): \(.value)"' 2>/dev/null || echo "    Unable to parse configuration"
    else
        print_status "FAIL" "Tekton Chains configuration not found"
        return 1
    fi
    
    return 0
}

# Test 6: Check Signing Configuration
test_signing_config() {
    print_status "INFO" "Checking signing configuration..."
    
    # Check if x509 signing is enabled
    x509_enabled=$(kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.signers\.x509\.enabled}' 2>/dev/null || echo "false")
    
    # Check if keyless signing is enabled
    keyless_enabled=$(kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data.signers\.x509\.fulcio\.enabled}' 2>/dev/null || echo "false")
    
    if [[ "$x509_enabled" == "true" ]]; then
        print_status "PASS" "X509 key-based signing is enabled"
        
        # Check for signing keys
        if kubectl get secret signing-secrets -n tekton-chains >/dev/null 2>&1; then
            print_status "PASS" "Signing keys secret exists"
        else
            print_status "FAIL" "Signing keys secret not found"
            return 1
        fi
        
    elif [[ "$keyless_enabled" == "true" ]]; then
        print_status "PASS" "Keyless signing with Fulcio is enabled"
        
        # Check service account for keyless signing
        if kubectl get serviceaccount tekton-chains-sa >/dev/null 2>&1; then
            print_status "PASS" "Keyless signing service account exists"
        else
            print_status "WARN" "Keyless signing service account not found"
        fi
        
    else
        print_status "WARN" "No signing method appears to be enabled"
        return 1
    fi
    
    return 0
}

# Test 7: Check Build Tasks
test_build_tasks() {
    print_status "INFO" "Checking build tasks..."
    
    # Check for enhanced build task
    if kubectl get task enhanced-build-sign >/dev/null 2>&1; then
        print_status "PASS" "enhanced-build-sign task exists"
    else
        print_status "WARN" "enhanced-build-sign task not found"
    fi
    
    # Check for keyless build task
    if kubectl get task keyless-build-sign >/dev/null 2>&1; then
        print_status "PASS" "keyless-build-sign task exists"
    else
        print_status "WARN" "keyless-build-sign task not found"
    fi
    
    # Check for demo pipeline
    if kubectl get pipeline slsa-demo-pipeline >/dev/null 2>&1; then
        print_status "PASS" "slsa-demo-pipeline exists"
    else
        print_status "WARN" "slsa-demo-pipeline not found"
    fi
    
    return 0
}

# Test 8: Check Recent Signing Activity
test_recent_signing() {
    print_status "INFO" "Checking recent signing activity..."
    
    # Look for recent TaskRuns with signatures
    recent_taskruns=$(kubectl get taskruns -l slsa-demo=true --sort-by=.metadata.creationTimestamp | tail -n 3)
    
    if [[ -n "$recent_taskruns" ]]; then
        print_status "INFO" "Recent TaskRuns found:"
        echo "$recent_taskruns"
        
        # Check latest TaskRun for signatures
        latest_taskrun=$(kubectl get taskruns -l slsa-demo=true --sort-by=.metadata.creationTimestamp -o name | tail -n 1)
        if [[ -n "$latest_taskrun" ]]; then
            signed_annotation=$(kubectl get "$latest_taskrun" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' 2>/dev/null || echo "false")
            if [[ "$signed_annotation" == "true" ]]; then
                print_status "PASS" "Latest TaskRun is signed by Tekton Chains"
            else
                print_status "WARN" "Latest TaskRun is not signed by Tekton Chains"
            fi
        fi
    else
        print_status "WARN" "No recent TaskRuns with slsa-demo label found"
    fi
    
    return 0
}

# Run all tests
main() {
    echo "Starting component validation..."
    echo "Date: $(date)"
    echo "Cluster context: $(kubectl config current-context 2>/dev/null || echo "No context")"
    echo ""
    
    # Run tests
    run_test "Prerequisites Check" "test_prerequisites"
    run_test "Kind Cluster Check" "test_kind_cluster"
    run_test "Local Registry Check" "test_local_registry"
    run_test "Tekton Pipelines Check" "test_tekton_pipelines"
    run_test "Tekton Chains Check" "test_tekton_chains"
    run_test "Signing Configuration Check" "test_signing_config"
    run_test "Build Tasks Check" "test_build_tasks"
    run_test "Recent Signing Activity Check" "test_recent_signing"
    
    # Summary
    # echo ""
    # echo "============================================"
    # echo "Validation Summary"
    # echo "============================================"
    # echo "Total tests: $TOTAL_TESTS"
    # echo "Passed: $PASSED_TESTS"
    # echo "Failed: $FAILED_TESTS"
    # echo ""
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo ""
        exit 0
    else
        print_status "FAIL" "Some components have issues"
        echo ""
        echo "Please fix the failing components before running the demo."
        echo "Refer to the individual script logs for detailed troubleshooting."
        exit 1
    fi
}

# Cleanup function
cleanup() {
    echo "Cleaning up temporary test resources..."
    kubectl delete pod registry-test --ignore-not-found >/dev/null 2>&1 || true
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"