#!/usr/bin/env bash
# GPU toolchain for A100/H100: NVIDIA HPC SDK (nvfortran/nvc/nvc++, OpenACC, bundled CUDA,
# OpenMPI and BLAS/LAPACK/ScaLAPACK) on top of the driver shipped in the base image.
#
# The driver is never reinstalled: it is verified against the CUDA version bundled with
# the pinned HPC SDK, which is the pairing NVIDIA supports.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${NVHPC_VERSION:?NVHPC_VERSION must be set}"
: "${GPU_TARGET_ARCH:?GPU_TARGET_ARCH must be set, e.g. cc80 or cc90}"
export DEBIAN_FRONTEND=noninteractive

TOOLCHAIN_ENV="${VASP_STATE_DIR}/toolchain.env"
: >"$TOOLCHAIN_ENV"

command -v nvidia-smi >/dev/null 2>&1 ||
    fail "NVIDIA driver" "nvidia-smi present in the base image" \
        "The pinned base image does not ship an NVIDIA driver. Choose an image that does, or add a pinned driver installation."

nvidia-smi >/dev/null 2>&1 ||
    fail "NVIDIA driver" "nvidia-smi runs successfully on ${TARGET_VM_SIZE:-the build VM}" \
        "Check that the build VM SKU exposes GPUs and that the driver matches the running kernel."

driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"
gpu_count="$(nvidia-smi --list-gpus | wc -l)"

if [[ -n "${NVIDIA_DRIVER_VERSION:-}" && "$driver" != "$NVIDIA_DRIVER_VERSION"* ]]; then
    fail "NVIDIA driver" "driver ${NVIDIA_DRIVER_VERSION} as pinned by nvidia_driver_version" \
        "The base image ships driver ${driver}. Update nvidia_driver_version, or pin a base image version that ships the expected driver."
fi

record_component nvidia_driver_version "$driver"
record_component gpu_model "$gpu_name"
record_component gpu_count "$gpu_count"
record_component gpu_target_arch "$GPU_TARGET_ARCH"

# Compute capability must match the requested -gpu=ccXX target.
compute_cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d '.')"
record_component gpu_compute_capability "cc${compute_cap}"
[[ ",${GPU_TARGET_ARCH}," == *",cc${compute_cap},"* ]] ||
    warn "build VM reports cc${compute_cap} but gpu_target_arch is ${GPU_TARGET_ARCH}; the binary will not run on this SKU"

# NVIDIA HPC SDK from the official apt repository.
nvhpc_package="nvhpc-${NVHPC_VERSION//./-}"
if dpkg-query --show "$nvhpc_package" >/dev/null 2>&1; then
    log "${nvhpc_package} already installed"
else
    log "installing ${nvhpc_package}"
    install -d -m 0755 /usr/share/keyrings
    curl --fail --silent --show-error --location "$NVHPC_GPG_KEY_URI" |
        gpg --dearmor --yes -o /usr/share/keyrings/nvidia-hpcsdk-archive-keyring.gpg ||
        fail "NVIDIA HPC SDK repository key" "GPG key downloaded from ${NVHPC_GPG_KEY_URI}" \
            "Check egress from the build subnet to developer.download.nvidia.com."

    printf 'deb [signed-by=/usr/share/keyrings/nvidia-hpcsdk-archive-keyring.gpg] %s /\n' \
        "$NVHPC_APT_REPO" >/etc/apt/sources.list.d/nvhpc.list
    apt-get update -qq

    apt-get install -y --no-install-recommends "$nvhpc_package" || {
        available="$(apt-cache search --names-only '^nvhpc-[0-9]' | awk '{print $1}' | tr '\n' ' ')"
        fail "NVIDIA HPC SDK" "package ${nvhpc_package} installable from ${NVHPC_APT_REPO}" \
            "Set nvhpc_version to one of the available packages: ${available:-none found}."
    }
fi

NVHPC_ROOT="$(find /opt/nvidia/hpc_sdk/Linux_x86_64 -maxdepth 1 -mindepth 1 -type d -name '2*' | sort -V | tail -n1)"
[[ -n "$NVHPC_ROOT" && -x "${NVHPC_ROOT}/compilers/bin/nvfortran" ]] ||
    fail "NVIDIA HPC SDK" "nvfortran under /opt/nvidia/hpc_sdk/Linux_x86_64/<version>" \
        "The package installed but the expected layout is missing. Inspect /opt/nvidia/hpc_sdk."

log "NVHPC root: ${NVHPC_ROOT}"

# CUDA and OpenMPI bundled with the SDK. The CUDA version is required verbatim by the
# VASP arch template's -gpu=...,cudaXX.Y flag.
cuda_bundled="$("${NVHPC_ROOT}/compilers/bin/nvfortran" --version | awk '/cuda/{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+$/) v=$i} END{print v}')"
if [[ -z "$cuda_bundled" ]]; then
    cuda_bundled="$(find "${NVHPC_ROOT}/cuda" -maxdepth 1 -mindepth 1 -type d -regex '.*/[0-9]+\.[0-9]+' -printf '%f\n' | sort -V | tail -n1)"
fi
[[ -n "$cuda_bundled" ]] ||
    fail "bundled CUDA" "a CUDA version under ${NVHPC_ROOT}/cuda" \
        "Could not determine the CUDA version bundled with NVHPC ${NVHPC_VERSION}. Set cuda_version explicitly."

if [[ -n "${CUDA_VERSION:-}" && "$CUDA_VERSION" != "$cuda_bundled" ]]; then
    fail "CUDA toolkit" "CUDA ${CUDA_VERSION} as pinned by cuda_version" \
        "NVHPC ${NVHPC_VERSION} bundles CUDA ${cuda_bundled}. Align cuda_version with the SDK, or pin a different nvhpc_version."
fi

mpi_root="$(find "${NVHPC_ROOT}/comm_libs" -maxdepth 2 -type d -name 'openmpi*' | sort -V | tail -n1)"
[[ -z "$mpi_root" ]] && mpi_root="${NVHPC_ROOT}/comm_libs/mpi"
[[ -x "${mpi_root}/bin/mpif90" ]] ||
    fail "NVHPC OpenMPI" "mpif90 under ${NVHPC_ROOT}/comm_libs" \
        "The HPC SDK MPI layout is unexpected. Inspect ${NVHPC_ROOT}/comm_libs."

record_component compiler_toolchain "nvhpc"
record_component compiler_version "$NVHPC_VERSION"
record_component nvhpc_root "$NVHPC_ROOT"
record_component cuda_toolkit_version "$cuda_bundled"
record_component cuda_toolkit_path "${NVHPC_ROOT}/cuda/${cuda_bundled}"
record_component math_library "nvhpc"
record_component mpi_flavor "nvhpc-openmpi"
record_component mpi_root "$mpi_root"
record_component mpi_version "$(version_of "${mpi_root}/bin/mpirun" --version)"
record_component cuda_driver_api "$(nvidia-smi --query --display=COMPUTE 2>/dev/null | awk -F': ' '/CUDA Version/{print $2; exit}')"

# Host FFTW for the CPU-side FFTs; cuFFT is linked via -cudalib by the arch template.
fftw_lib="$(dirname "$(find "${NVHPC_ROOT}/compilers" -name 'libfftw3.*' 2>/dev/null | head -n1)" 2>/dev/null || true)"
fftw_inc="${NVHPC_ROOT}/compilers/include"
if [[ -z "$fftw_lib" || "$fftw_lib" == "." ]]; then
    log "NVHPC does not provide FFTW; installing the distribution package"
    apt-get update -qq
    apt-get install -y --no-install-recommends libfftw3-dev ||
        fail "FFTW" "libfftw3-dev installable" "Provide an FFTW build and set FFTW_LIB/FFTW_INC in the toolchain environment."
    fftw_lib="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
    fftw_inc="/usr/include"
fi

[[ -n "$(find "$fftw_lib" -maxdepth 1 -name 'libfftw3_omp.*' | head -n1)" ]] ||
    fail "FFTW OpenMP support" "libfftw3_omp under ${fftw_lib}" \
        "The VASP arch template links -lfftw3_omp. Install an FFTW build with OpenMP support."

record_component fft_library "cuFFT (NVHPC) + FFTW ${fftw_lib}"

# Consumed by 20-environment-modules.sh and 31-vasp-build.sh.
cat >"$TOOLCHAIN_ENV" <<EOF
NVHPC_ROOT=${NVHPC_ROOT}
NVHPC_CUDA_VERSION=${cuda_bundled}
MPI_BIN=${mpi_root}/bin
MPI_LIB=${mpi_root}/lib
COMPILER_BIN=${NVHPC_ROOT}/compilers/bin
COMPILER_LIB=${NVHPC_ROOT}/compilers/lib
CUDA_LIB=${NVHPC_ROOT}/cuda/${cuda_bundled}/lib64
MATH_LIB=${NVHPC_ROOT}/math_libs/lib64
FFTW_LIB=${fftw_lib}
FFTW_INC=${fftw_inc}
EOF

record_component cpu_model "$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)"
