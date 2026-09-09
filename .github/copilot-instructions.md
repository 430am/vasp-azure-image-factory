# GitHub Copilot Instructions: Azure VASP HPC Image Factory

## Project objective

This repository builds, validates, versions, and publishes optimized Azure VM images for running VASP on Microsoft Azure.

The primary compute targets are:

CPU / MPI:
- Standard_HB120rs_v3
- AMD EPYC Milan-X
- Azure InfiniBand / RDMA
- Multi-node MPI workloads

GPU:
- Standard_NC24ads_A100_v4
- Standard_NC48ads_A100_v4
- Standard_NC96ads_A100_v4
- NVIDIA A100 80-GB PCIe GPUs
- VASP GPU acceleration using the supported NVIDIA/CUDA toolchain

The output must be repeatable infrastructure and image-building code.

Do not design this repository around manual installation procedures.

---

# Architecture principles

Use:

- HashiCorp Packer for immutable VM image creation
- Azure Compute Gallery for image distribution
- Azure CLI for deployment automation
- Bicep for Azure infrastructure
- Bash for OS configuration
- GitHub Actions for CI/CD
- Environment Modules for VASP runtime configuration

Prefer Microsoft Azure HPC marketplace images where technically compatible.

For HBv3, prefer an Azure HPC optimized Ubuntu image.

For NC_A100_v4, validate compatibility of the Azure HPC image before assuming support. If it is unsuitable, use a supported Ubuntu Gen2 image and explicitly install and validate the required NVIDIA software stack.

Do not assume the same image optimization is appropriate for both CPU and GPU targets.

---

# VASP licensing constraints

VASP is commercial software.

NEVER:

- download VASP source code from public repositories
- commit VASP source code
- upload VASP source code as a GitHub artifact
- embed VASP source inside the image repository
- publish VASP binaries to a public image gallery
- expose VASP source or binaries in GitHub Actions logs

The build pipeline must obtain VASP source from an authorized private location supplied by the user.

Supported patterns may include:

- private Azure Blob Storage
- restricted storage using managed identity
- an internal artifact repository

Secrets must come from:

- Azure Key Vault
- GitHub Actions secrets
- workload identity federation

Never hard-code credentials.

---

# Image strategy

Build two image variants.

## vasp-hbv3

Target:

Standard_HB120rs_v3

Purpose:

CPU-based VASP running across one or more HBv3 nodes.

Optimize for:

- AMD EPYC Milan-X
- NUMA locality
- CPU binding
- process affinity
- RDMA
- InfiniBand
- MPI
- OpenMP
- memory bandwidth

The build must verify:

- InfiniBand device detection
- RDMA libraries
- MPI availability
- compiler availability
- BLAS/LAPACK/ScaLAPACK
- FFT libraries
- VASP binary execution

Do not configure VASP assuming Intel CPUs.

---

## vasp-nca100

Targets:

Standard_NC24ads_A100_v4
Standard_NC48ads_A100_v4
Standard_NC96ads_A100_v4

Purpose:

GPU-accelerated VASP calculations.

Optimize for:

- NVIDIA A100 PCIe
- CUDA
- NVIDIA driver compatibility
- GPU memory
- CPU/GPU affinity
- VASP GPU execution

The image must verify:

nvidia-smi

and verify that CUDA runtime/compiler requirements match the VASP build requirements.

Do not blindly install the newest CUDA version.

Compiler, CUDA toolkit, NVIDIA driver, math libraries and VASP versions must be treated as a compatibility matrix.

---

# Packer

Use HCL2 Packer configuration.

Do not create JSON-based Packer templates.

Required variables:

subscription_id
tenant_id
location
resource_group
build_resource_group
gallery_name
image_definition
image_version
target_vm_size
os_offer
os_sku
os_version
vasp_version
build_type

Supported build_type values:

cpu
gpu

The build must support:

packer init
packer validate
packer build

The build must be noninteractive.

Do not require SSH interaction during normal image construction.

Provide a troubleshooting option that allows the temporary build VM to be retained after failure.

---

# Azure Compute Gallery

Publish successful images into Azure Compute Gallery.

Maintain separate image definitions:

vasp-hbv3
vasp-nca100

Use semantic-style image versions.

Example:

1.0.0
1.0.1
1.1.0

Never overwrite an existing image version.

Build metadata should record:

- VASP version
- operating system
- kernel version
- compiler version
- MPI implementation/version
- CUDA version when applicable
- NVIDIA driver version when applicable
- Packer build timestamp
- git commit SHA

Write installed-component information to:

/opt/vasp/image-version.json

---

# VASP installation location

Install VASP under:

/opt/vasp/<version>/

Example:

/opt/vasp/6.x.x/

Use symlink:

/opt/vasp/current

Never distribute source files outside the protected build context.

After compilation, remove temporary source/build artifacts unless they are explicitly required at runtime and permitted by the VASP license.

---

# Environment Modules

Create an environment module:

module load vasp

The module should configure only what is required to run VASP.

Do not globally modify user shell startup scripts unnecessarily.

Example runtime commands should eventually support:

module load vasp

and the applicable VASP executable.

---

# CPU build requirements

Before implementing the CPU build, determine:

- supported VASP compiler toolchains
- MPI implementation
- BLAS/LAPACK implementation
- ScaLAPACK implementation
- FFT implementation
- OpenMP configuration
- compiler optimization flags

Optimization flags must be appropriate for AMD EPYC Milan-X.

Never introduce architecture-specific compiler flags unless their compatibility has been verified.

Favor portability and reproducibility over speculative optimization.

Document performance-specific options separately from required build flags.

---

# MPI

MPI selection must be explicit.

Do not accidentally link VASP against headers from one MPI implementation and libraries from another.

Validation must report:

which mpirun
mpirun --version

and VASP's linked libraries.

Use:

ldd

or equivalent tooling to validate runtime linkage.

For HBv3, preserve Azure RDMA/InfiniBand compatibility.

---

# HBv3 topology

Do not assume CPU numbering.

Discover topology using:

lscpu
numactl --hardware

Expose recommended process placement through runtime examples.

Separate image configuration from job-level MPI affinity configuration.

Do not hard-code node counts into the image.

---

# GPU build requirements

Before compiling GPU VASP, validate:

nvidia-smi

and CUDA availability.

Capture:

GPU model
driver version
CUDA runtime compatibility
CUDA toolkit version

Build VASP using the officially supported VASP GPU build approach for the requested VASP version.

Do not invent compiler flags.

Do not assume a CUDA/toolkit combination without verifying compatibility.

---

# Build provenance

Every build must produce a manifest containing:

OS
kernel
VASP version
compiler
compiler version
MPI
MPI version
CUDA version
NVIDIA driver
math libraries
git SHA
build timestamp
image version

Store the manifest at:

/opt/vasp/image-version.json

---

# Validation

Every image build requires validation before gallery publication.

Validation should have four stages.

## Stage 1: OS

Check:

uname -a
/etc/os-release
kernel
filesystem
required packages

## Stage 2: hardware/software

HBv3:

lscpu
numactl --hardware
ibv_devinfo or equivalent
MPI version

NC_A100:

lscpu
nvidia-smi
CUDA version
GPU count
GPU model

## Stage 3: VASP

Check:

VASP executable exists
shared library dependencies resolve
module load succeeds
binary launches successfully

## Stage 4: scientific smoke test

Execute a small user-provided VASP test case.

Do not distribute licensed VASP test material unless explicitly authorized.

Validate successful completion.

Where appropriate record execution time, but do not initially make performance a pass/fail gate.

---

# Performance testing

Separate correctness testing from performance benchmarking.

Correctness tests answer:

"Does the image work?"

Performance tests answer:

"Does the image perform as expected?"

Performance results must not initially block image publication unless a baseline has been explicitly defined.

For HBv3 capture:

MPI configuration
MPI ranks
OpenMP threads
CPU affinity
NUMA placement
runtime

For NC_A100 capture:

GPU count
GPU utilization
GPU memory usage
CPU utilization
runtime

---

# Security

Never store:

passwords
storage account keys
Azure credentials
SSH private keys
VASP credentials

inside the repository.

Prefer Azure workload identity federation from GitHub Actions.

Prefer managed identity from Azure VMs where possible.

Run image security validation before publication.

Avoid unnecessary packages.

Remove build-only credentials and temporary files before image capture.

---

# CI/CD

GitHub Actions must have separate stages:

lint
packer-validate
infrastructure-validate
image-build
image-test
image-publish

Pull requests should execute inexpensive validation only.

Do not create HBv3 or A100 VMs for every pull request.

Actual VM/image builds should run:

- manually using workflow_dispatch
- on release tags
- through an explicitly authorized workflow

This prevents accidental Azure HPC/GPU spending.

---

# Cost controls

HPC and GPU VM creation must never occur implicitly.

Any workflow that provisions HBv3 or NC_A100 resources must:

- clearly identify the target VM SKU
- clearly identify Azure region
- support automatic teardown
- destroy resources after testing
- use timeout protection
- clean resources after failures

Use GitHub concurrency controls to prevent duplicate image builds.

---

# Infrastructure as Code

All persistent Azure infrastructure must be represented in Bicep.

This includes:

- Azure Compute Gallery
- image definitions
- managed identities
- Key Vault integration if required
- build networking when required

Do not require Portal configuration.

---

# Idempotency

Provisioning scripts must be safe to rerun whenever practical.

Before installing software:

- detect current state
- detect existing versions
- fail clearly on incompatible state

Scripts must use:

set -euo pipefail

unless there is a documented reason not to.

---

# Logging

Scripts must log major actions.

Never log secrets.

Failures should clearly indicate:

- command
- component
- expected state
- remediation guidance

---

# Documentation

README.md must contain:

Architecture
Prerequisites
VASP licensing requirements
Azure prerequisites
Repository structure
How CPU images are built
How GPU images are built
How validation works
How images are published
How to deploy test VMs
How to load VASP
How to run smoke tests
Troubleshooting
Cost controls
Security considerations

---

# Development behavior for GitHub Copilot

When asked to implement a feature:

1. Inspect the repository first.
2. Explain the proposed change briefly.
3. Identify affected files.
4. Implement the smallest coherent change.
5. Validate syntax.
6. Add or update tests.
7. Update documentation when behavior changes.

Do not replace established architecture without explaining why.

Do not silently change compiler, MPI, CUDA, driver or OS versions.

Treat these as pinned dependencies.

When dependency versions change, update:

/opt/vasp/image-version.json generation
README documentation
tests
Packer configuration

---

# Definition of Done

The project is complete when a user can execute a documented workflow that:

1. authenticates securely to Azure
2. retrieves authorized VASP source
3. builds an HBv3 image
4. validates VASP
5. publishes it to Azure Compute Gallery
6. builds an NC_A100 image
7. validates GPU functionality
8. validates VASP
9. publishes it to Azure Compute Gallery
10. deploys a VM from either image
11. loads VASP using environment modules
12. executes a small VASP smoke test
13. destroys all temporary build/test infrastructure

All steps must be reproducible from source control.