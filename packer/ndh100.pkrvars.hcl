// GPU image: VASP on Standard_ND96isr_H100_v5 (NVIDIA H100 SXM, NVLink, InfiniBand).
// Identical toolchain to the A100 image; only the compute capability differs.
build_type     = "gpu"
target_vm_size = "Standard_ND96isr_H100_v5"

// TODO: pin the region where you hold ND H100 v5 quota, e.g. location = "centralus".
// Until then the build falls back to PKR_VAR_location.

image_definition = "vasp-ndh100"

os_publisher = "microsoft-dsvm"
os_offer     = "ubuntu-2204"
os_sku       = "2204-gen2"
os_version   = "25.06.18"

os_disk_size_gb = 256

vasp_version       = "6.4.3"
vasp_arch_template = "makefile.include.nvhpc_omp_acc"

compiler_toolchain = "nvhpc"
mpi_flavor         = "nvhpc"
math_library       = "nvhpc"
gpu_target_arch    = "cc90"
gpu_host_arch      = "-tp host"
hdf5_enabled       = false
