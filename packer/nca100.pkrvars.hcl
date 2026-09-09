// GPU image: VASP on Standard_NC{24,48,96}ads_A100_v4 (NVIDIA A100 80GB PCIe).
// Identity, gallery and version values come from PKR_VAR_* environment variables.
build_type = "gpu"
// Smallest SKU in the family; the resulting image supports NC24/NC48/NC96 ads_A100_v4.
target_vm_size = "Standard_NC24ads_A100_v4"

// A100 quota is in Central US. The build VM runs here and the image version is
// replicated here by default.
location = "centralus"

image_definition = "vasp-nca100"

// Pinned DSVM Ubuntu 22.04 Gen2 image (NVIDIA driver preinstalled).
os_publisher = "microsoft-dsvm"
os_offer     = "ubuntu-2204"
os_sku       = "2204-gen2"
os_version   = "25.06.18"

os_disk_size_gb = 256

vasp_version = "6.4.3"
// OpenACC GPU port with OpenMP host threading, using NVHPC's own BLAS/LAPACK/ScaLAPACK.
vasp_arch_template = "makefile.include.nvhpc_omp_acc"

// NVIDIA HPC SDK supplies nvfortran/nvc/nvc++, CUDA, OpenMPI and the math libraries.
compiler_toolchain = "nvhpc"
mpi_flavor         = "nvhpc"
math_library       = "nvhpc"
gpu_target_arch    = "cc80"
gpu_host_arch      = "-tp host"
hdf5_enabled       = false
