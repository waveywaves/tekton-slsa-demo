#!/bin/bash
# Demo Part 5: Trusted Resources (Script 06)

set -x

pause() {
    read -p "Press Enter to continue..."
}

# Setup trusted resources
# SAY: "Now let me show you SLSA Level 3 - where even the build definitions are cryptographically signed"
# SAY: "This prevents tampering with build processes and ensures non-falsifiable provenance"
./scripts/06-setup-trusted-resources.sh
pause

# Show feature flags
# SAY: "Here are the feature flags enabling trusted resources in Tekton Pipelines"
# SAY: "This enables verification of signed Tasks and Pipelines at runtime"
kubectl get configmap feature-flags -n tekton-pipelines -o yaml | grep -A 3 -B 3 "trusted-resources"
pause

# Show verification policies
# SAY: "These are our verification policies - they enforce that only signed resources can be executed"
# SAY: "This prevents unauthorized or tampered build definitions from running"
kubectl get verificationpolicy -A
pause

# Show trusted task
# SAY: "This is a trusted Task - cryptographically signed and verified at runtime"
# SAY: "Even the build definition has tamper-evident security"
kubectl get task trusted-security-scan -o yaml | head -20
pause

# Show trusted pipeline
# SAY: "Here's our trusted Pipeline - the entire workflow definition is signed"
# SAY: "This ensures end-to-end integrity from build definition to execution"
kubectl get pipeline trusted-slsa-pipeline -o yaml | head -20
pause

# Show signed resources
# SAY: "Here are our signed Tasks - each has a cryptographic signature annotation"
# SAY: "These signatures are verified before execution, preventing tampered build processes"
kubectl get tasks -l trusted-resource=true -o custom-columns="NAME:.metadata.name,SIGNATURE:.metadata.annotations.trusted-resource\.tekton\.dev/signature"
pause

# SAY: "And here are our signed Pipelines - complete workflow definitions with cryptographic guarantees"
kubectl get pipelines -l trusted-resource=true -o custom-columns="NAME:.metadata.name,SIGNATURE:.metadata.annotations.trusted-resource\.tekton\.dev/signature"
pause

# Show trusted pipeline run
# SAY: "This is a test run using our trusted resources - demonstrating signed build execution"
# SAY: "Both the build artifacts AND the build process are now cryptographically verified"
kubectl get pipelineruns -l test-type=trusted-resources
pause

# Show controller logs for verification
# SAY: "Here are the controller logs showing trusted resource verification in action"
# SAY: "The system is actively verifying signatures before executing any build definitions"
kubectl logs -n tekton-pipelines -l app.kubernetes.io/name=controller --tail=15 | grep -i "trust\|verif\|sign"
pause

# Show public key for trusted resources
# SAY: "This is our trusted resources public key - used to verify signed Tasks and Pipelines"
# SAY: "This completes our SLSA Level 3 implementation with comprehensive supply chain security"
if [[ -f /tmp/trusted-resource.pub ]]; then
    cat /tmp/trusted-resource.pub
else
    echo "Trusted resource public key not found"
fi
pause

echo "Demo complete! SLSA Level 3+ with trusted resources achieved."
