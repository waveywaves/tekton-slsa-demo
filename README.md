# Tekton SLSA Demo: Supply Chain Security Made Real

Ever wondered how to actually implement supply chain security in your CI/CD pipelines? This demo walks you through building SLSA-compliant pipelines using Tekton, from basic automation to advanced hermetic builds.

## What You'll Learn

This hands-on demo takes you through each SLSA level with working examples:

- **SLSA Level 1**: Get started with automated builds and basic provenance
- **SLSA Level 2**: Add cryptographic signatures and tamper-proof build records  
- **SLSA Level 3**: Implement trusted resources and non-falsifiable attestations
- **SLSA Level 4**: Experiment with hermetic builds (cutting-edge stuff!)
- **Bonus**: Sign your Tekton Tasks and Pipelines for ultimate trust

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenSSF SLSA Framework                      │
├─────────────────────────────────────────────────────────────────┤
│  Level 4: Hermetic + Reproducible (Hermekton)                 │
│  Level 3: Non-falsifiable Provenance (SPIFFE/SPIRE + Sigstore) │
│  Level 2: Authenticated Provenance (Tekton Chains + Signing)   │
│  Level 1: Basic Security Practices (Tekton Pipelines)          │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Kind Cluster    │
                    │   (with OIDC)     │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐   ┌────────▼────────┐   ┌───────▼────────┐
│ Tekton         │   │ Tekton Chains   │   │ Sigstore       │
│ Pipelines      │   │ (Attestations)  │   │ (Keyless Sign) │
└────────────────┘   └─────────────────┘   └────────────────┘
```

## Prerequisites

- Docker
- kubectl
- Kind (Kubernetes in Docker)
- Cosign CLI
- Tekton CLI

## How This Demo Works

### Start Here: Basic Setup (15 minutes)
- `00-prerequisites.sh` - Install the tools you need (kubectl, kind, cosign, etc.)
- `01-setup-kind-cluster-with-oidc.sh` - Spin up a local Kubernetes cluster
- `02-install-tekton-pipelines.sh` - Get Tekton running on your cluster

### Level Up: Add Supply Chain Security (20 minutes)  
- `03-install-tekton-chains.sh` - This is where the magic happens - automatic attestation generation!
- `04a-configure-keyless-signing.sh` - Modern approach using Sigstore (internet required)
- `04b-configure-key-signing.sh` - Traditional key-based signing (works offline)
- `05-deploy-sample-go-app.sh` - Build and deploy our demo Go application

### Advanced Features: Push the Boundaries (30 minutes)
- `06-setup-trusted-resources.sh` - Sign your Tekton Tasks and Pipelines themselves
- `07-enable-hermetic-mode.sh` - Try experimental hermetic builds (completely isolated)

### Put It All Together: Full Demo (10 minutes)
- `08-run-complete-slsa-pipeline.sh` - Run the full SLSA compliance pipeline  
- `09-verify-slsa-compliance.sh` - Verify everything worked and check your SLSA level

## Quick Start

Want to see it all in action? Here's the fastest way:

```bash
# Make scripts executable  
chmod +x scripts/*.sh run-demo.sh

# Option 1: Interactive demo (recommended for presentations)
./run-demo.sh

# Option 2: Full automated setup
./scripts/00-prerequisites.sh
./scripts/01-setup-kind-cluster-with-oidc.sh  
./scripts/02-install-tekton-pipelines.sh
./scripts/03-install-tekton-chains.sh
./scripts/04b-configure-key-signing.sh  # Start with key-based signing
./scripts/05-deploy-sample-go-app.sh
./scripts/08-run-complete-slsa-pipeline.sh
./scripts/09-verify-slsa-compliance.sh
```

**Pro tip**: Start with key-based signing (`04b`) rather than keyless (`04a`) - it's more reliable for local demos.

## What Actually Works (Honest Assessment)

### ✅ Rock Solid - Use in Production
- **SLSA Level 1-2**: Fully working, battle-tested features
- **Tekton Chains**: Generates real SLSA v1.0 provenance automatically  
- **Cryptographic Signing**: Both keyless (Sigstore) and key-based methods work
- **Real Container Builds**: Actually builds and pushes your Go app to a registry

### ⚠️ Cool Demo Features - Handle with Care
- **Trusted Resources**: Alpha feature, works but APIs may change
- **Hermetic Builds**: Experimental, shows the concept but has limitations
- **SLSA Level 3**: Most pieces work, but not all edge cases covered
- **Local Registry**: Works great for demos, you'll want a real registry for production

### 🚧 Coming Soon (But Not Today)
- **Full SPIFFE/SPIRE**: Tekton Chains support is still being developed
- **Production Hermetic Builds**: The feature exists but needs more work
- **Complete Policy Enforcement**: Some verification policies are still alpha

## SLSA Levels Demonstrated

### Level 1: Basic Security Practices
- ✅ Fully scripted/automated build process
- ✅ Provenance generation and availability
- ✅ Version-controlled Pipeline definitions

### Level 2: Source Integrity & Authenticated Provenance  
- ✅ Version control for source code
- ✅ Hosted build service (Kubernetes/Tekton)
- ✅ Cryptographically signed provenance
- ✅ Tamper-resistant build provenance

### Level 3: Auditable Build Pipelines & Hardened Builds
- ⚠️ Isolated, tamper-proof build environments (via containers)
- ⚠️ Restricted access to signing material (via Sigstore)
- 🔄 Non-falsifiable provenance (SPIFFE/SPIRE integration pending)
- ✅ Trusted Resources with signed Task/Pipeline definitions

### Level 4: Reproducible, Automated Builds & Two-Person Review
- ⚠️ Hermetic, reproducible build process (experimental Hermekton)
- 📋 Two-person review (organizational best practice - not technical)
- ⚠️ Fully isolated build dependencies

## Verification

The demo includes verification at each SLSA level:

```bash
# Verify SLSA Level 2 compliance
cosign verify-attestation --key cosign.pub --type slsaprovenance $IMAGE

# Verify Tekton Pipeline signatures  
tkn task verify --key cosign.pub task-name

# Check hermetic execution
kubectl logs -l app=hermetic-build -c step-build
```

## Sample Application

The demo uses a simple Go web application that demonstrates:
- Secure build processes with dependency scanning
- Container image generation with SBOMs
- Attestation generation and verification
- Supply chain security validation

## Architecture Components

### Tekton Ecosystem
- **Tekton Pipelines**: Core CI/CD engine
- **Tekton Chains**: Supply chain security manager
- **Tekton CLI**: Command-line tools for signing and verification

### Security Stack
- **Sigstore**: Keyless signing infrastructure
- **Cosign**: Container signing and verification
- **in-toto**: Supply chain attestation framework
- **SLSA**: Supply chain security framework

### Kubernetes Integration
- **Kind**: Local Kubernetes for development
- **OIDC Issuer**: Workload identity for keyless signing
- **Service Account Tokens**: JWT-based authentication

## Demo Flow for Presentation

1. **Introduction** (2 minutes)
   - Show supply chain threats landscape
   - Introduce SLSA framework progression

2. **Level 1-2 Demo** (8 minutes)
   - Live installation of Tekton components
   - Run basic pipeline with attestation generation
   - Show signed provenance and SBOM

3. **Level 3-4 Demo** (8 minutes)
   - Enable Trusted Resources and hermetic mode
   - Demonstrate advanced security features
   - Show verification at each level

4. **Q&A and Discussion** (7 minutes)
   - Address current limitations honestly
   - Discuss roadmap for full Level 4 compliance
   - Enterprise adoption considerations

## Troubleshooting

### Common Issues

1. **Kind cluster connectivity**: Ensure Docker is running and ports are available
2. **OIDC token issues**: Check Kind cluster OIDC configuration
3. **Keyless signing failures**: Fall back to key-based signing approach
4. **Resource constraints**: Adjust Kind cluster resource limits

### Debug Commands

```bash
# Check Tekton installation
kubectl get pods -n tekton-pipelines

# Verify Chains configuration  
kubectl get configmap chains-config -n tekton-chains -o yaml

# Check OIDC endpoints
curl -k https://localhost:6443/.well-known/openid-configuration
```

## Contributing

This demo is designed for educational and demonstration purposes. Contributions welcome for:
- Additional SLSA compliance checks
- Enhanced verification scripts  
- Documentation improvements
- Bug fixes and reliability improvements

## License

MIT License

## References

- [SLSA Framework](https://slsa.dev/)
- [Tekton Documentation](https://tekton.dev/)
- [Sigstore Project](https://sigstore.dev/)
- [Supply-chain Levels for Software Artifacts](https://slsa.dev/spec/)
- [in-toto Attestation Framework](https://in-toto.io/)