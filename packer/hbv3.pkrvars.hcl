// CPU image: VASP on Standard_HB120rs_v3 (AMD EPYC Milan-X, InfiniBand/RDMA).
// Identity, gallery and version values come from PKR_VAR_* environment variables.
build_type     = "cpu"
target_vm_size = "Standard_HB120rs_v3"

// TODO: pin the region where you hold HBv3 quota, e.g. location = "southcentralus".
// Until then the build falls back to PKR_VAR_location.

image_definition = "vasp-hbv3"

// Azure HPC-optimised Ubuntu: ships the Azure InfiniBand/RDMA stack, UCX and HPC-X,
// which the GPU-oriented DSVM image does not.
os_publisher = "microsoft-dsvm"
os_offer     = "ubuntu-hpc"
os_sku       = "2204"
// UNRESOLVED: pin to an explicit marketplace version for reproducible builds.
os_version = "latest"

os_disk_size_gb = 256

vasp_version       = "6.4.3"
vasp_arch_template = "makefile.include.gnu_ompi_aocl_omp"

// GCC + HPC-X OpenMPI + UCX/InfiniBand + AMD AOCL (BLIS, libFLAME, ScaLAPACK, FFTW).
compiler_toolchain = "gcc"
gcc_version        = "11"
mpi_flavor         = "hpcx"
math_library       = "aocl"
cpu_target_arch    = "-march=znver3"
hdf5_enabled       = true
