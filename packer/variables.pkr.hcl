// Azure identity and placement. Never hard-code subscription data: supply these via
// PKR_VAR_* environment variables or a local (git-ignored) *.pkrvars.local.hcl file.
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID used for the build and the destination gallery."
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID."
}

variable "client_id" {
  type        = string
  description = "Optional service principal / user-assigned identity client ID. Empty uses az CLI or MSI auth."
  default     = ""
}

variable "use_azure_cli_auth" {
  type        = bool
  description = "Authenticate as the signed-in az CLI identity. Set false to use managed identity or workload identity federation."
  default     = true
}

variable "build_identity_id" {
  type        = string
  description = "Resource ID of the user-assigned managed identity attached to the build VM (output buildIdentityResourceId from infra/main.bicep). Lets the build read the VASP archive from private blob storage with no secret."
  default     = ""
}

// Each image variant targets exactly one region and one VM SKU, because HPC and GPU
// quota is granted per region and per SKU family. Pin this in the variant's pkrvars file.
variable "location" {
  type        = string
  description = "Azure region for this image variant: where the build VM runs and, by default, where the image version is replicated."
}

variable "resource_group" {
  type        = string
  description = "Resource group containing the Azure Compute Gallery (destination)."
}

variable "build_resource_group" {
  type        = string
  description = "Optional pre-existing resource group for build resources. WARNING: when set, the build region is the region of THIS resource group and var.location no longer controls where the build VM runs. Leave empty to have Packer create and delete a temporary resource group in var.location."
  default     = ""
}

variable "build_virtual_network_name" {
  type        = string
  description = "Optional existing VNet for the build VM (no public IP when set)."
  default     = ""
}

variable "build_virtual_network_subnet_name" {
  type        = string
  description = "Subnet within build_virtual_network_name."
  default     = ""
}

variable "build_virtual_network_resource_group_name" {
  type        = string
  description = "Resource group of build_virtual_network_name."
  default     = ""
}

// Destination gallery
variable "gallery_name" {
  type        = string
  description = "Azure Compute Gallery name."
}

variable "image_definition" {
  type        = string
  description = "Gallery image definition name (vasp-hbv3 or vasp-nca100)."
}

variable "image_version" {
  type        = string
  description = "Semantic image version (major.minor.patch). Never reuse an existing version."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "The image_version value must be major.minor.patch, e.g. 1.0.0."
  }
}

variable "replication_regions" {
  type        = list(string)
  description = "Gallery replication target regions."
  default     = []
}

// Build target
variable "target_vm_size" {
  type        = string
  description = "VM size used to build the image. Should match the runtime SKU family."
}

variable "build_type" {
  type        = string
  description = "cpu or gpu. Selects the provisioning and validation script set."

  validation {
    condition     = contains(["cpu", "gpu"], var.build_type)
    error_message = "The build_type value must be either 'cpu' or 'gpu'."
  }
}

// Base marketplace image
variable "os_publisher" {
  type        = string
  description = "Marketplace image publisher."
}

variable "os_offer" {
  type        = string
  description = "Marketplace image offer."
}

variable "os_sku" {
  type        = string
  description = "Marketplace image SKU."
}

variable "os_version" {
  type        = string
  description = "Marketplace image version. Pin explicitly for reproducible builds; 'latest' is not reproducible."
  default     = "latest"
}

// VASP. The source is fetched at build time from an authorized private location.
// Nothing about VASP source or binaries may leave the build VM.
variable "vasp_version" {
  type        = string
  description = "VASP version being installed, e.g. 6.4.3. Installed under /opt/vasp/<version>."
}

variable "vasp_source_uri" {
  type        = string
  description = "URI of the authorized private VASP source archive (e.g. private blob storage)."
  default     = ""
}

variable "vasp_source_sas_token" {
  type        = string
  description = "Optional SAS token for vasp_source_uri. Prefer managed identity. Sourced from Key Vault or GitHub secrets."
  default     = ""
  sensitive   = true
}

variable "vasp_arch_template" {
  type        = string
  description = "Name of the VASP-shipped arch/makefile.include.* template to build from. Upstream templates are used rather than hand-written build configuration."
}

variable "vasp_targets" {
  type        = string
  description = "VASP make targets to build and install."
  default     = "std gam ncl"
}

variable "vasp_make_args" {
  type        = string
  description = "Extra arguments passed to make. DEPS=1 enables VASP's dependency-based parallel build."
  default     = "DEPS=1"
}

// Toolchain. CPU: GCC + HPC-X OpenMPI + UCX + AMD AOCL. GPU: NVIDIA HPC SDK (OpenACC,
// bundled CUDA, OpenMPI and BLAS/LAPACK/ScaLAPACK) + cuFFT.
variable "compiler_toolchain" {
  type        = string
  description = "gcc (cpu) or nvhpc (gpu)."

  validation {
    condition     = contains(["gcc", "nvhpc"], var.compiler_toolchain)
    error_message = "The compiler_toolchain value must be either 'gcc' or 'nvhpc'."
  }
}

variable "gcc_version" {
  type        = string
  description = "GCC major version for the CPU build. 11 is the Ubuntu 22.04 default and matches the distribution HDF5 Fortran modules; 12 requires HDF5 to be rebuilt."
  default     = "11"
}

variable "mpi_flavor" {
  type        = string
  description = "MPI implementation: hpcx (CPU, from the Azure HPC image) or nvhpc (GPU, bundled with the HPC SDK)."
  default     = ""
}

variable "math_library" {
  type        = string
  description = "BLAS/LAPACK/ScaLAPACK/FFT provider: aocl (CPU) or nvhpc (GPU)."
  default     = ""
}

variable "cpu_target_arch" {
  type        = string
  description = "Value of VASP_TARGET_CPU for the CPU build, e.g. -march=znver3 (HBv3) or -march=znver4 (HBv4)."
  default     = ""
}

variable "gpu_target_arch" {
  type        = string
  description = "NVHPC GPU compute capability, e.g. cc80 (A100) or cc90 (H100). Comma-separated values produce a fat binary."
  default     = ""
}

variable "gpu_host_arch" {
  type        = string
  description = "NVHPC host CPU target. '-tp host' is correct because the image is built on the target SKU."
  default     = "-tp host"
}

// AOCL is EULA-gated and cannot be fetched from a public URL by this repository. The CPU
// script uses an AOCL already present in the base image, otherwise this URI.
variable "aocl_version" {
  type        = string
  description = "AMD AOCL version recorded in the manifest. CONFIRM before production use."
  default     = "5.0.0"
}

variable "aocl_download_uri" {
  type        = string
  description = "URI of an AOCL .deb or tarball you have downloaded under AMD's EULA and hosted privately. Only used when the base image does not already provide AOCL."
  default     = ""
}

// NVIDIA HPC SDK. Supplies nvfortran/nvc/nvc++, CUDA, OpenMPI, BLAS/LAPACK/ScaLAPACK.
variable "nvhpc_version" {
  type        = string
  description = "NVIDIA HPC SDK version, e.g. 25.1. Determines the apt package nvhpc-<major>-<minor>. CONFIRM before production use."
  default     = "25.1"
}

variable "nvhpc_apt_repo" {
  type        = string
  description = "NVIDIA HPC SDK apt repository."
  default     = "https://developer.download.nvidia.com/hpc-sdk/ubuntu/amd64"
}

variable "nvhpc_gpg_key_uri" {
  type        = string
  description = "GPG key for the NVIDIA HPC SDK apt repository."
  default     = "https://developer.download.nvidia.com/hpc-sdk/ubuntu/DEB-GPG-KEY-NVIDIA-HPC-SDK"
}

variable "cuda_version" {
  type        = string
  description = "Expected CUDA version. Empty uses the version bundled with the pinned NVIDIA HPC SDK; a non-empty value is asserted against it."
  default     = ""
}

variable "nvidia_driver_version" {
  type        = string
  description = "Expected NVIDIA driver version. Empty accepts the driver shipped in the pinned base image; a non-empty value is asserted against it."
  default     = ""
}

variable "hdf5_enabled" {
  type        = bool
  description = "Build VASP with HDF5 support. CPU only: the distribution HDF5 Fortran modules are gfortran-specific and are not usable by nvfortran."
  default     = false
}

// Provenance
variable "git_sha" {
  type        = string
  description = "Git commit SHA of the repository state that produced the image."
  default     = "unknown"
}

variable "os_disk_size_gb" {
  type        = number
  description = "Build VM OS disk size. Must hold the VASP source tree and build artifacts."
  default     = 128
}

variable "ssh_username" {
  type        = string
  description = "Build-time SSH user. Removed by Azure deprovision at capture time."
  default     = "packer"
}
