# Demo Scripts - Command-Only Flow

## Overview
Clean command-only demo scripts with press-Enter-to-continue flow. No explanatory text - just the commands you need to show.

## Prerequisites 
Run these setup scripts first:
```bash
./scripts/00-prerequisites.sh
./scripts/01-setup-kind-cluster-with-oidc.sh
./scripts/02-install-tekton-pipelines.sh  
./scripts/03-install-tekton-chains.sh
echo "y" | ./scripts/04b-configure-key-signing.sh
```

## Demo Flow

### 1. System Overview (2 min)
```bash
./demo/1.sh
```
Shows: cluster status, chains config, application, build task

### 2. Execute Build (3 min)  
```bash
./demo/2.sh
```  
Shows: build setup, TaskRun creation, live build monitoring

### 3. Verify Signing (3 min)
```bash
./demo/3.sh
```
Shows: signing verification, attestations, public key, system validation

### 4. Deploy Application (5 min)
```bash
./demo/4.sh
```
Runs: `./scripts/05-deploy-sample-go-app.sh` + shows deployment status

### 5. Trusted Resources (5 min)  
```bash
./demo/5.sh
```
Runs: `./scripts/06-setup-trusted-resources.sh` + shows SLSA Level 3+ features

## Usage
- Each command waits for Enter key
- You provide all speaking/explanation
- Can skip sections or run individually
- Scripts work in tandem with 05/06 scripts