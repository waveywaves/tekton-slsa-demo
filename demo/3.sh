#!/bin/bash
# Demo Part 3: Verify Signing

set -x

pause() {
    read -p "Press Enter to continue..."
}

# Get TaskRun name from part 2
if [[ -f /tmp/current-demo-taskrun ]]; then
    TR_NAME=$(cat /tmp/current-demo-taskrun)
else
    TR_NAME=$(kubectl get taskruns -l slsa-demo=true -o name | tail -1 | cut -d'/' -f2)
fi

echo "Using TaskRun: $TR_NAME"
pause

# Check signing status
# SAY: "Perfect! See that 'true' value? That's cryptographic proof that Tekton Chains automatically signed our TaskRun"
# SAY: "This represents SLSA Level 2 compliance - automated provenance generation with unforgeable signatures"
kubectl get taskrun $TR_NAME -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}'
pause

# Show signing metadata
# SAY: "Here's all the signing metadata Chains generated - signed confirmation, the SLSA provenance payload, and the cryptographic signature"
# SAY: "An attacker cannot forge this without access to our private signing keys"
kubectl get taskrun $TR_NAME -o jsonpath='{.metadata.annotations}' | jq . | grep chains
pause

# Show complete attestation metadata
# SAY: "This is the complete SLSA provenance document - comprehensive build attestation"
# SAY: "It includes builder identity, timestamps, source materials, build parameters, and cryptographic signature"
# SAY: "This creates an unbreakable chain from source code to final artifact"
kubectl get taskrun $TR_NAME -o yaml | grep -A 20 "annotations:"
pause

# Show public key
# SAY: "Here's our public key - this is not secret and can be shared publicly"
# SAY: "Anyone with this key can cryptographically verify our artifacts - they don't have to trust our word"
if [[ -f /tmp/cosign.pub ]]; then
    cat /tmp/cosign.pub
else
    echo "Public key not found at /tmp/cosign.pub"
fi
pause

# Show multiple builds  
# SAY: "Notice we have multiple signed builds - each one is independently verifiable"
# SAY: "This isn't a one-off demo trick - this scales to thousands of builds per day"
kubectl get taskruns -l slsa-demo=true
pause

# Show signing summary
# SAY: "Here's the signing summary - every build gets automatic cryptographic signatures"
# SAY: "Downstream consumers can verify every artifact came from our trusted build system"
kubectl get taskruns -l slsa-demo=true -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[0].reason,SIGNED:.metadata.annotations.chains\.tekton\.dev/signed"
pause

# System validation
# SAY: "Final validation - all components are healthy and working together perfectly"
# SAY: "This system is production-ready for SLSA Level 2 compliance with minimal maintenance"
./scripts/validate-components.sh | tail -15
pause

echo "Part 3 complete. Run ./demo/4.sh to deploy application."