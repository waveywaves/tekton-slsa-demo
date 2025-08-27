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

# Function to wait for deployment with timeout
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"
    
    log_info "Waiting for deployment $deployment in namespace $namespace..."
    if kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=${timeout}s; then
        log_info "✅ Deployment $deployment is ready"
    else
        error_exit "Deployment $deployment failed to become ready within ${timeout} seconds"
    fi
}

echo "============================================"
echo "Installing Tekton Pipelines"
echo "============================================"

# Tekton Pipelines version (use latest for better compatibility)
TEKTON_VERSION="latest"

# Function to check if Tekton is already installed
check_existing_installation() {
    if kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        echo "Tekton Pipelines namespace already exists"
        if kubectl get pods -n tekton-pipelines 2>/dev/null | grep -q Running; then
            echo "Tekton Pipelines appears to be running:"
            kubectl get pods -n tekton-pipelines
            read -p "Do you want to reinstall Tekton Pipelines? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Skipping Tekton Pipelines installation"
                return 1
            fi
            echo "Proceeding with reinstallation..."
            uninstall_tekton
        fi
    fi
    return 0
}

# Function to uninstall existing Tekton
uninstall_tekton() {
    echo "Uninstalling existing Tekton Pipelines..."
    kubectl delete --ignore-not-found -f "https://storage.googleapis.com/tekton-releases/pipeline/${TEKTON_VERSION}/release.yaml"
    
    # Wait for cleanup
    echo "Waiting for cleanup to complete..."
    kubectl wait --for=delete namespace/tekton-pipelines --timeout=120s || true
    sleep 10
}

# Function to install Tekton Pipelines
install_tekton_pipelines() {
    echo "Installing Tekton Pipelines ${TEKTON_VERSION}..."
    
    # Install Tekton Pipelines
    kubectl apply -f "https://storage.googleapis.com/tekton-releases/pipeline/${TEKTON_VERSION}/release.yaml"
    
    echo "Waiting for Tekton Pipelines to be ready..."
    kubectl wait --for=condition=ready pod -l app=tekton-pipelines-controller -n tekton-pipelines --timeout=300s
    kubectl wait --for=condition=ready pod -l app=tekton-pipelines-webhook -n tekton-pipelines --timeout=300s
    
    # Wait for additional components if they exist
    if kubectl get deployment -n tekton-pipelines tekton-pipelines-remote-resolvers >/dev/null 2>&1; then
        kubectl wait --for=condition=ready pod -l app=tekton-pipelines-remote-resolvers -n tekton-pipelines --timeout=300s
    fi
}

# Function to verify installation
verify_installation() {
    echo "Verifying Tekton Pipelines installation..."
    
    # Check pods
    echo "Checking Tekton Pipelines pods:"
    kubectl get pods -n tekton-pipelines -o wide
    
    # Check services
    echo "Checking Tekton Pipelines services:"
    kubectl get services -n tekton-pipelines
    
    # Check CRDs
    echo "Checking installed CRDs:"
    kubectl get crds | grep tekton || echo "No Tekton CRDs found yet (they may still be installing)"
    
    # Wait a bit more for CRDs to be fully ready
    echo "Waiting for CRDs to be ready..."
    sleep 15
    
    echo "Available Tekton resources:"
    kubectl api-resources | grep tekton
}

# Function to create sample resources to test installation
create_test_resources() {
    echo "Creating test resources to verify installation..."
    
    # Create a simple hello-world task
    cat << EOF | kubectl apply -f -
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello-world
  namespace: default
spec:
  steps:
  - name: hello
    image: alpine:3.18
    command:
    - /bin/sh
    - -c
    args:
    - echo "Hello, World! Tekton is working!"
EOF

    echo "Test task created successfully"
    
    # Verify the task was created
    kubectl get task hello-world -o yaml
}

# Function to test basic functionality
test_basic_functionality() {
    echo "Testing basic Tekton functionality..."
    
    # Create and run a simple TaskRun
    cat << EOF | kubectl apply -f -
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: hello-world-run-$(date +%s)
  namespace: default
spec:
  taskRef:
    name: hello-world
EOF

    echo "Test TaskRun created"
    
    # Wait for the TaskRun to complete
    TASKRUN_NAME=$(kubectl get taskruns -o name | grep hello-world-run | head -1 | cut -d'/' -f2)
    if [ -n "$TASKRUN_NAME" ]; then
        echo "Waiting for TaskRun $TASKRUN_NAME to complete..."
        kubectl wait --for=condition=succeeded taskrun/$TASKRUN_NAME --timeout=120s
        
        echo "TaskRun logs:"
        kubectl logs -l tekton.dev/taskRun=$TASKRUN_NAME --all-containers=true
        
        echo "TaskRun completed successfully!"
    else
        echo "Warning: Could not find TaskRun to wait for"
    fi
}

# Function to configure RBAC for demo
configure_rbac() {
    echo "Configuring RBAC for demo..."
    
    # Create service account for Tekton tasks
    kubectl create serviceaccount tekton-demo-sa --namespace default || echo "Service account already exists"
    
    # Create ClusterRole with necessary permissions
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-demo-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]
  verbs: ["*"]
- apiGroups: ["tekton.dev"]
  resources: ["tasks", "taskruns", "pipelines", "pipelineruns"]
  verbs: ["*"]
- apiGroups: ["security.openshift.io"]
  resources: ["securitycontextconstraints"]
  verbs: ["use"]
  resourceNames: ["anyuid"]
EOF

    # Bind the role to the service account
    kubectl create clusterrolebinding tekton-demo-binding \
        --clusterrole=tekton-demo-role \
        --serviceaccount=default:tekton-demo-sa || echo "ClusterRoleBinding already exists"
}

# Function to enable additional features
enable_features() {
    echo "Enabling additional Tekton features..."
    
    # Enable alpha features in Tekton config
    kubectl patch configmap feature-flags -n tekton-pipelines -p '{"data":{"enable-api-fields":"alpha"}}'
    
    # Enable tekton bundles
    kubectl patch configmap feature-flags -n tekton-pipelines -p '{"data":{"enable-tekton-oci-bundles":"true"}}'
    
    # Enable custom tasks
    kubectl patch configmap feature-flags -n tekton-pipelines -p '{"data":{"enable-custom-tasks":"true"}}'
    
    echo "Restarting Tekton controller to apply feature changes..."
    kubectl rollout restart deployment/tekton-pipelines-controller -n tekton-pipelines
    kubectl rollout status deployment/tekton-pipelines-controller -n tekton-pipelines --timeout=180s
}

# Main function
main() {
    echo "Starting Tekton Pipelines installation..."
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "Error: Cannot access Kubernetes cluster. Please ensure cluster is running."
        exit 1
    fi
    
    # Check existing installation
    if ! check_existing_installation; then
        echo "Using existing Tekton Pipelines installation"
    else
        # Install Tekton Pipelines
        install_tekton_pipelines
        
        # Enable additional features
        enable_features
    fi
    
    # Verify installation
    verify_installation
    
    # Configure RBAC
    configure_rbac
    
    # Create test resources
    create_test_resources
    
    # Test basic functionality
    test_basic_functionality
    
    echo ""
    echo "============================================"
    echo "Tekton Pipelines Installation Complete!"
    echo "============================================"
    echo "Version: $TEKTON_VERSION"
    echo ""
    echo "Tekton components:"
    kubectl get pods -n tekton-pipelines -o wide
    echo ""
    echo "Available Tekton resources:"
    kubectl api-resources | grep tekton
    echo ""
    echo "Ready for Tekton Chains installation!"
    echo "Next step: Run ./scripts/03-install-tekton-chains.sh"
}

# Run main function
main "$@"