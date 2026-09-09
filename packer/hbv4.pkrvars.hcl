// CPU image: VASP on Standard_HB176rs_v4 (AMD EPYC Genoa-X, InfiniBand/RDMA).
// Identical toolchain to HBv3; only the target architecture flag differs.
build_type     = "cpu"
target_vm_size = "Standard_HB176rs_v4"

image_definition = "vasp-hbv4"

os_publisher = "microsoft-dsvm"
os_offer     = "ubuntu-hpc"
os_sku       = "2204"
// UNRESOLVED: pin to an explicit marketplace version for reproducible builds.
os_version = "latest"

os_disk_size_gb = 256

vasp_version       = "6.4.3"
vasp_arch_template = "makefile.include.gnu_ompi_aocl_omp"

compiler_toolchain = "gcc"
gcc_version        = "11"
mpi_flavor         = "hpcx"
math_library       = "aocl"
cpu_target_arch    = "-march=znver4"
hdf5_enabled       = true
