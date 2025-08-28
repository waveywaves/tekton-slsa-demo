#!/bin/bash
# Demo Part 2: Execute Build

set -x

pause() {
    read -p "Press Enter to continue..."
}

# Setup build environment  
# SAY: "First, let me set up our build environment - creating storage for the build workspace"
kubectl apply -f k8s/workspace-pvc.yaml
pause

# SAY: "Now deploying our enhanced build task - this is a standard Tekton Task with no special security configuration"
kubectl apply -f k8s/enhanced-build-task.yaml
pause

# Create timestamped build
# SAY: "Here's where SLSA comes alive. I'm creating a TaskRun with a unique timestamp - this proves it's a fresh, live build"
# SAY: "The moment this completes, Tekton Chains will automatically generate SLSA provenance and sign it cryptographically"
TIMESTAMP=$(date +%s)
kubectl apply -f - << EOF
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: demo-build-$TIMESTAMP
  labels:
    slsa-demo: "true"
spec:
  taskRef:
    name: enhanced-build-sign
  params:
  - name: IMAGE_NAME
    value: "ttl.sh/tekton-slsa-demo"
  - name: IMAGE_TAG
    value: "demo-$TIMESTAMP"
  workspaces:
  - name: source
    persistentVolumeClaim:
      claimName: demo-workspace-pvc
EOF
pause

# Save TaskRun name for part 3
echo "demo-build-$TIMESTAMP" > /tmp/current-demo-taskrun

# Watch build logs
# SAY: "Now let's watch the live build execution with real-time logs"
# SAY: "You'll see source code being cloned, tests running, container being built, and pushed to registry"
# SAY: "While this builds, Tekton Chains is monitoring in the background, waiting for completion"
# SAY: "The moment this completes successfully, Chains will inject cryptographic signatures automatically"
echo "Following build logs: demo-build-$TIMESTAMP"
tkn tr logs demo-build-$TIMESTAMP -f