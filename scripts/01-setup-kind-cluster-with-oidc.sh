#!/bin/bash

set -x
set -e

echo "============================================"
echo "Setting up Kind Cluster with OIDC Support"
echo "============================================"

CLUSTER_NAME="tekton-slsa-demo"
CLUSTER_CONFIG_FILE="/tmp/kind-config.yaml"

# Function to check if cluster exists
cluster_exists() {
    kind get clusters | grep -q "^${CLUSTER_NAME}$"
}

# Function to create kind cluster configuration
create_cluster_config() {
    echo "Creating Kind cluster configuration with OIDC support..."
    cat > "$CLUSTER_CONFIG_FILE" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        # Enable service account issuer for better token validation
        service-account-issuer: "https://kubernetes.default.svc.cluster.local"
        service-account-signing-key-file: "/etc/kubernetes/pki/sa.key"
        service-account-key-file: "/etc/kubernetes/pki/sa.pub"
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
EOF
    echo "Kind configuration created at: $CLUSTER_CONFIG_FILE"
}

# Function to create kind cluster
create_cluster() {
    echo "Creating Kind cluster: $CLUSTER_NAME"
    
    # Delete existing cluster if it exists
    if cluster_exists; then
        echo "Deleting existing cluster: $CLUSTER_NAME"
        kind delete cluster --name "$CLUSTER_NAME"
        sleep 5
    fi
    
    # Create new cluster
    kind create cluster --config "$CLUSTER_CONFIG_FILE" --wait 300s
    
    # Verify cluster is ready
    echo "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

# Function to verify cluster configuration
verify_oidc_config() {
    echo "Verifying cluster configuration..."
    
    # Wait for API server to be ready
    sleep 10
    
    # Basic cluster connectivity test
    if kubectl cluster-info > /dev/null 2>&1; then
        echo "✅ Kubernetes cluster is accessible"
        kubectl cluster-info | head -2
    else
        echo "⚠️  Issue accessing Kubernetes cluster"
        return 1
    fi
    
    # Check if service accounts work
    echo "Testing service account functionality..."
    if kubectl get serviceaccounts default > /dev/null 2>&1; then
        echo "✅ Service account operations working"
    else
        echo "⚠️  Service account operations may have issues"
    fi
    
    # Check basic OIDC/service account issuer (optional)
    echo "Checking service account issuer configuration..."
    if kubectl get --raw=/.well-known/openid_configuration > /dev/null 2>&1; then
        echo "✅ OIDC discovery endpoint accessible"
    else
        echo "ℹ️  OIDC discovery endpoint not available (this is OK for basic operation)"
    fi
}

# Function to set up cluster networking
setup_networking() {
    echo "Setting up cluster networking..."
    
    # Install CNI (should be already installed by kind)
    kubectl get pods -n kube-system -l k8s-app=kindnet
    
    # Verify nodes are ready
    kubectl get nodes -o wide
    
    # Create ingress controller (useful for later demos)
    echo "Installing NGINX Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    # Wait for ingress controller to be ready
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s
}

# Function to set up local container registry
setup_local_registry() {
    echo "Setting up local container registry..."
    
    # Check if registry container already exists
    if docker ps -a --format '{{.Names}}' | grep -q '^kind-registry$'; then
        echo "Registry container already exists"
        if ! docker ps --format '{{.Names}}' | grep -q '^kind-registry$'; then
            echo "Starting existing registry container"
            docker start kind-registry
        fi
    else
        echo "Creating local container registry..."
        docker run -d --restart=always -p "5001:5000" --name "kind-registry" registry:2
    fi
    
    # Wait for registry to be ready
    echo "Waiting for registry to be ready..."
    for i in {1..30}; do
        if curl -f http://localhost:5001/v2/ >/dev/null 2>&1; then
            echo "✅ Registry is ready"
            break
        fi
        echo "Waiting for registry... ($i/30)"
        sleep 2
    done
    
    # Connect registry to kind network (this is the critical fix)
    echo "Connecting registry to kind network..."
    docker network connect "kind" "kind-registry" 2>/dev/null || echo "Registry already connected to kind network"
    
    # Apply the configmap to use the registry - this tells Kind about the registry
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "kind-registry:5000"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

    # Create containerd config patch for registry
    echo "Configuring containerd for local registry..."
    docker exec "${CLUSTER_NAME}-control-plane" sh -c '
mkdir -p /etc/containerd/certs.d/kind-registry:5000
cat > /etc/containerd/certs.d/kind-registry:5000/hosts.toml << "TOML"
[host."http://kind-registry:5000"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
TOML
'
    
    # Restart containerd on the nodes to pick up the configuration
    echo "Restarting containerd to apply registry configuration..."
    docker exec "${CLUSTER_NAME}-control-plane" systemctl restart containerd
    
    # If worker node exists, configure it too
    if docker ps --format '{{.Names}}' | grep -q "${CLUSTER_NAME}-worker"; then
        docker exec "${CLUSTER_NAME}-worker" sh -c '
mkdir -p /etc/containerd/certs.d/kind-registry:5000
cat > /etc/containerd/certs.d/kind-registry:5000/hosts.toml << "TOML"
[host."http://kind-registry:5000"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
TOML
'
        docker exec "${CLUSTER_NAME}-worker" systemctl restart containerd
    fi
    
    # Wait for nodes to be ready after containerd restart
    echo "Waiting for nodes to be ready after containerd restart..."
    kubectl wait --for=condition=Ready nodes --all --timeout=180s
    
    # Test registry connectivity from both host and cluster
    echo "Testing registry connectivity..."
    if curl -f http://localhost:5001/v2/ >/dev/null 2>&1; then
        echo "✅ Registry accessible from host (localhost:5001)"
    else
        echo "⚠️ Registry not accessible from host"
    fi
    
    # Test from within cluster
    echo "Testing registry connectivity from within cluster..."
    if kubectl run registry-test --image=curlimages/curl:latest --rm -i --restart=Never --timeout=30s --command -- curl -f http://kind-registry:5000/v2/ >/dev/null 2>&1; then
        echo "✅ Registry accessible from cluster (kind-registry:5000)"
    else
        echo "⚠️ Registry not accessible from cluster"
        echo "This may cause build issues. Registry troubleshooting:"
        echo "1. Check if registry container is running: docker ps | grep kind-registry"
        echo "2. Check network connectivity: docker network ls | grep kind"
        echo "3. Verify containerd configuration was applied"
        return 1
    fi
}

# Function to configure kubectl context
setup_kubectl_context() {
    echo "Setting up kubectl context..."
    
    # Set current context to our cluster
    kubectl config use-context "kind-${CLUSTER_NAME}"
    
    # Verify context is set correctly
    echo "Current kubectl context:"
    kubectl config current-context
    
    echo "Cluster info:"
    kubectl cluster-info
}

# Function to create necessary namespaces
create_namespaces() {
    echo "Creating necessary namespaces..."
    
    # These namespaces will be used by Tekton components
    kubectl create namespace tekton-pipelines || echo "Namespace tekton-pipelines already exists"
    kubectl create namespace tekton-chains || echo "Namespace tekton-chains already exists"
    kubectl create namespace tekton-demo || echo "Namespace tekton-demo already exists"
    
    # Label the demo namespace
    kubectl label namespace tekton-demo slsa-demo=true --overwrite
    
    echo "Created namespaces:"
    kubectl get namespaces -l slsa-demo=true
}

# Main function
main() {
    echo "Starting Kind cluster setup with OIDC support..."
    
    # Check if kind is available
    if ! command -v kind >/dev/null 2>&1; then
        echo "Error: kind is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed. Please run 00-prerequisites.sh first."
        exit 1
    fi
    
    # Create cluster configuration
    create_cluster_config
    
    # Create the cluster
    create_cluster
    
    # Set up kubectl context
    setup_kubectl_context
    
    # Set up networking
    setup_networking
    
    # Set up local container registry
    setup_local_registry
    
    # Create necessary namespaces
    create_namespaces
    
    # Verify OIDC configuration
    verify_oidc_config
    
    # Clean up config file
    rm -f "$CLUSTER_CONFIG_FILE"
    
    echo ""
    echo "============================================"
    echo "Kind Cluster Setup Complete!"
    echo "============================================"
    echo "Cluster name: $CLUSTER_NAME"
    echo "API server: https://127.0.0.1:6443"
    echo "OIDC issuer: https://127.0.0.1:6443"
    echo ""
    echo "Cluster status:"
    kubectl get nodes -o wide
    echo ""
    echo "Ready for Tekton installation!"
    echo "Next step: Run ./scripts/02-install-tekton-pipelines.sh"
}

# Run main function
main "$@"