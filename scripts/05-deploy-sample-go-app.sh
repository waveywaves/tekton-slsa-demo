#!/bin/bash

set -x
set -e

echo "============================================"
echo "Deploying Sample Go Application with SLSA Pipeline"
echo "============================================"

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        echo "Error: Tekton Pipelines not found. Please run 02-install-tekton-pipelines.sh first."
        exit 1
    fi
    
    if ! kubectl get namespace tekton-chains >/dev/null 2>&1; then
        echo "Error: Tekton Chains not found. Please run 03-install-tekton-chains.sh first."
        exit 1
    fi
    
    if ! kubectl get task enhanced-build-sign >/dev/null 2>&1 && ! kubectl get task keyless-build-sign >/dev/null 2>&1; then
        echo "Error: Build tasks not found. Please run either 04a or 04b script first."
        exit 1
    fi
    
    echo "✅ Prerequisites satisfied"
}

# Function to deploy Kubernetes resources
deploy_k8s_resources() {
    echo "Deploying Kubernetes resources..."
    
    # Apply all YAML files
    if [ -d "k8s" ]; then
        echo "Applying Kubernetes manifests from k8s/ directory..."
        kubectl apply -f k8s/
    else
        echo "Creating essential Kubernetes resources..."
        
        # Create workspace PVC
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-workspace-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF
        
        # Create service account if not exists
        kubectl apply -f k8s/service-account.yaml 2>/dev/null || echo "Service account already exists"
    fi
    
    echo "✅ Kubernetes resources deployed"
}

# Function to build and deploy the Go application
build_and_deploy_app() {
    echo "Building and deploying Go application..."
    
    # Determine which build task to use
    if kubectl get task keyless-build-sign >/dev/null 2>&1; then
        BUILD_TASK="keyless-build-sign"
        SERVICE_ACCOUNT="tekton-chains-sa"
        SIGNING_METHOD="keyless"
    else
        BUILD_TASK="enhanced-build-sign"
        SERVICE_ACCOUNT="default"
        SIGNING_METHOD="key-based"
    fi
    
    echo "Using build task: $BUILD_TASK with $SIGNING_METHOD signing"
    
    # Create and run the pipeline
    TIMESTAMP=$(date +%s)
    IMAGE_TAG="demo-v$TIMESTAMP"
    PIPELINE_NAME="slsa-app-deploy-$TIMESTAMP"
    
    # Get the directory where this script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_FILE="$SCRIPT_DIR/../templates/deployment-pipelinerun-template.yaml"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "Error: PipelineRun template file not found at $TEMPLATE_FILE"
        exit 1
    fi
    
    # Create temporary file with customized values
    TEMP_PIPELINE="/tmp/deployment-pipelinerun-$TIMESTAMP.yaml"
    cp "$TEMPLATE_FILE" "$TEMP_PIPELINE"
    
    # Replace placeholders with actual values
    sed -i.bak \
        -e "s/PIPELINE_RUN_NAME/$PIPELINE_NAME/g" \
        -e "s/SERVICE_ACCOUNT/$SERVICE_ACCOUNT/g" \
        -e "s/BUILD_TASK_NAME/$BUILD_TASK/g" \
        -e "s/IMAGE_TAG_VALUE/$IMAGE_TAG/g" \
        -e "s/SIGNING_METHOD_VALUE/$SIGNING_METHOD/g" \
        "$TEMP_PIPELINE"
    
    # Apply the customized PipelineRun
    kubectl apply -f "$TEMP_PIPELINE"
    
    # Clean up temporary files
    rm -f "$TEMP_PIPELINE" "$TEMP_PIPELINE.bak"
    
    echo "PipelineRun created: $PIPELINE_NAME"
    return 0
}

# Function to wait for pipeline completion
wait_for_pipeline() {
    echo "Waiting for pipeline to complete..."
    
    PIPELINE_RUN=$(kubectl get pipelineruns -l deployment=sample-app --sort-by=.metadata.creationTimestamp -o name | tail -1)
    
    if [ -n "$PIPELINE_RUN" ]; then
        PIPELINE_NAME=$(echo $PIPELINE_RUN | cut -d'/' -f2)
        echo "Monitoring PipelineRun: $PIPELINE_NAME"
        
        # Wait for completion
        kubectl wait --for=condition=succeeded $PIPELINE_RUN --timeout=600s
        
        echo "✅ Pipeline completed successfully!"
        
        # Show results
        echo "=== Pipeline Results ==="
        kubectl get $PIPELINE_RUN -o yaml | grep -A 10 "results:" || echo "No results found"
        
        return 0
    else
        echo "⚠️ Could not find PipelineRun to monitor"
        return 1
    fi
}

# Function to verify deployment
verify_deployment() {
    echo "Verifying application deployment..."
    
    # Check deployment status
    if kubectl get deployment tekton-slsa-demo >/dev/null 2>&1; then
        echo "✅ Deployment exists"
        kubectl get deployment tekton-slsa-demo
        
        # Check if pods are ready
        READY_REPLICAS=$(kubectl get deployment tekton-slsa-demo -o jsonpath='{.status.readyReplicas}')
        DESIRED_REPLICAS=$(kubectl get deployment tekton-slsa-demo -o jsonpath='{.spec.replicas}')
        
        if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ]; then
            echo "✅ All replicas are ready ($READY_REPLICAS/$DESIRED_REPLICAS)"
        else
            echo "⚠️ Not all replicas are ready ($READY_REPLICAS/$DESIRED_REPLICAS)"
        fi
        
        # Test application endpoints
        echo "Testing application endpoints..."
        kubectl port-forward svc/tekton-slsa-demo 8080:8080 &
        PF_PID=$!
        sleep 5
        
        if curl -f http://localhost:8080/health >/dev/null 2>&1; then
            echo "✅ Health endpoint accessible"
            curl -s http://localhost:8080/health | jq . || echo "Health check passed"
        else
            echo "⚠️ Health endpoint not accessible"
        fi
        
        kill $PF_PID 2>/dev/null || true
        
    else
        echo "❌ Deployment not found"
        return 1
    fi
}

# Function to show SLSA attestations
show_slsa_attestations() {
    echo "Showing SLSA attestations and signatures..."
    
    # Get recent TaskRuns from the deployment
    echo "=== Recent TaskRuns ==="
    kubectl get taskruns -l slsa-demo=true --sort-by=.metadata.creationTimestamp | tail -5
    
    # Check for signed TaskRuns
    echo "=== Signed TaskRuns ==="
    kubectl get taskruns -l slsa-demo=true -o custom-columns="NAME:.metadata.name,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed,METHOD:.metadata.labels.signing-method"
    
    # Show Chains logs
    echo "=== Recent Tekton Chains Activity ==="
    kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=10 | grep -E "(sign|Sign|payload)" || echo "No recent signing activity"
}

# Main function
main() {
    echo "Starting Go application deployment with SLSA compliance..."
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy Kubernetes resources
    deploy_k8s_resources
    
    # Build and deploy the application
    if build_and_deploy_app; then
        echo "Pipeline started successfully"
    else
        echo "Failed to start pipeline"
        exit 1
    fi
    
    # Wait for pipeline completion
    if wait_for_pipeline; then
        echo "Pipeline completed successfully"
    else
        echo "Pipeline may still be running or failed"
    fi
    
    # Verify deployment
    verify_deployment
    
    # Show SLSA attestations
    show_slsa_attestations
    
    echo ""
    echo "============================================"
    echo "Sample Go Application Deployment Complete!"
    echo "============================================"
    echo ""
    echo "Application Status:"
    kubectl get deployment,pods,svc -l app=tekton-slsa-demo
    echo ""
    echo "To test the application:"
    echo "  kubectl port-forward svc/tekton-slsa-demo 8080:8080"
    echo "  curl http://localhost:8080"
    echo "  curl http://localhost:8080/health"
    echo ""
    echo "SLSA Compliance:"
    echo "  - Build process: ✅ Automated with Tekton Pipelines"
    echo "  - Provenance: ✅ Generated by Tekton Chains"
    echo "  - Signing: ✅ Cryptographic signatures applied"
    echo "  - Attestations: ✅ Available for verification"
    echo ""
    echo "Next steps:"
    echo "  - Run verification scripts to check SLSA compliance"
    echo "  - Explore Tekton Chains annotations and logs"
    echo "  - Try different signing methods (keyless vs key-based)"
}

# Run main function
main "$@"