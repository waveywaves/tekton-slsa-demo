#!/bin/bash
# Demo Part 4: Deploy Application (Script 05)

set -x

pause() {
    read -p "Press Enter to continue..."
}

# Run deployment script
# SAY: "Now let me deploy our application using a complete SLSA-compliant pipeline"
# SAY: "This will build, sign, and deploy our application with full attestation generation"
./scripts/05-deploy-sample-go-app.sh
pause

# Show deployment status
# SAY: "Here's our deployed application - built with SLSA attestations and running in production"
# SAY: "Every component has cryptographic proof of how it was built"
kubectl get deployment,pods,svc -l app=tekton-slsa-demo
pause

# Show recent pipeline runs
# SAY: "These are the pipeline runs that built and deployed our application"
# SAY: "Each one generates comprehensive SLSA provenance documents"
kubectl get pipelineruns -l deployment=sample-app
pause

# Show SLSA attestations from deployment
# SAY: "Here's the complete signing summary - every build artifact is cryptographically signed"
# SAY: "This demonstrates end-to-end supply chain security from source to deployment"
kubectl get taskruns,pipelineruns -l slsa-demo=true -o custom-columns="KIND:.kind,NAME:.metadata.name,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed"
pause

# Show Chains activity
# SAY: "Here's live activity from Tekton Chains - showing real-time signing operations"
# SAY: "This happens automatically for every build without developer intervention"
kubectl logs -n tekton-chains -l app=tekton-chains-controller --tail=10
pause

echo "Part 4 complete. Run ./demo/5.sh for trusted resources."
