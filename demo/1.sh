#!/bin/bash
# Demo Part 1: System Overview

set -x

pause() {
    read -p "Press Enter to continue..."
}

# Show cluster status
# SAY: "Let me show you our Kubernetes cluster running Tekton - our build system"
kubectl get nodes
pause

# SAY: "Here's Tekton Pipelines - this is our CI/CD build engine running on Kubernetes"
kubectl get pods -n tekton-pipelines
pause

# SAY: "And here's Tekton Chains - the component that automatically signs every build"
kubectl get pods -n tekton-chains  
pause

# Show signing configuration
# SAY: "Let me show you our SLSA configuration. Notice artifacts.taskrun.format: slsa/v1 - this generates SLSA v1.0 compliant attestations"
# SAY: "The signers.x509.enabled: true shows we use traditional x509 key-based signing with strong cryptographic guarantees"
kubectl get configmap chains-config -n tekton-chains -o jsonpath='{.data}' | jq .
pause

# Show application
# SAY: "Here's our sample application - a simple Go HTTP server. The magic isn't in the app, but in HOW we build and attest to it"
cat cmd/main.go
pause

# Show build task
# SAY: "This is our enhanced build task with structured outputs that Tekton Chains can sign"
# SAY: "Notice the git-clone step for source integrity and kaniko for reproducible builds - all SLSA requirements"
kubectl get task enhanced-build-sign -o yaml
pause

echo "Part 1 complete. Run ./demo/2.sh next."