#!/usr/bin/env bash
# CPU toolchain for HBv3/HBv4: GCC, HPC-X OpenMPI over UCX/InfiniBand, AMD AOCL
# (BLIS, libFLAME, ScaLAPACK, FFTW) and optional HDF5.
#
# The Azure HPC base image already provides the InfiniBand/RDMA stack, UCX and HPC-X;
# those are verified and recorded, never reinstalled.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${GCC_VERSION:?GCC_VERSION must be set}"
export DEBIAN_FRONTEND=noninteractive

TOOLCHAIN_ENV="${VASP_STATE_DIR}/toolchain.env"
: >"$TOOLCHAIN_ENV"

# InfiniBand / RDMA. The build VM is an HBv3/HBv4 node, so devices must be visible here.
command -v ibv_devinfo >/dev/null 2>&1 ||
    fail "rdma-core" "ibv_devinfo available" \
        "Use an Azure HPC base image (microsoft-dsvm:ubuntu-hpc:2204) that includes the InfiniBand user-space stack."

ibv_devinfo >/dev/null 2>&1 ||
    fail "InfiniBand" "ibv_devinfo reports at least one HCA on ${TARGET_VM_SIZE:-the build VM}" \
        "Confirm the build VM SKU is RDMA-capable and that the Azure IB stack in the base image is intact."

record_component infiniband_devices "$(ibv_devinfo 2>/dev/null | awk '/hca_id/{printf "%s ", $2}')"
record_component ucx_version "$(version_of ucx_info -v)"

# HPC-X OpenMPI, shipped with the Azure HPC image under /opt.
HPCX_DIR="$(find /opt -maxdepth 1 -name 'hpcx*' -type d | sort | tail -n1)"
[[ -n "$HPCX_DIR" && -x "${HPCX_DIR}/ompi/bin/mpif90" ]] ||
    fail "HPC-X OpenMPI" "an HPC-X installation with ompi/bin/mpif90 under /opt" \
        "The base image does not provide HPC-X. Use microsoft-dsvm:ubuntu-hpc:2204, or set mpi_flavor to an implementation this script installs."

log "using HPC-X at ${HPCX_DIR}"
record_component mpi_flavor "hpcx"
record_component mpi_root "$HPCX_DIR"
record_component mpi_version "$(version_of "${HPCX_DIR}/ompi/bin/mpirun" --version)"

# GCC. The compiler is selected explicitly rather than by changing system alternatives.
gcc_packages=("gcc-${GCC_VERSION}" "g++-${GCC_VERSION}" "gfortran-${GCC_VERSION}")
apt-get update -qq
apt-get install -y --no-install-recommends "${gcc_packages[@]}" ||
    fail "GCC ${GCC_VERSION}" "packages ${gcc_packages[*]} installable" \
        "GCC ${GCC_VERSION} is not available in this base image. Choose a version packaged for Ubuntu 22.04 (11 or 12)."

CC="$(command -v "gcc-${GCC_VERSION}")"
CXX="$(command -v "g++-${GCC_VERSION}")"
FC="$(command -v "gfortran-${GCC_VERSION}")"
record_component compiler_toolchain "gcc"
record_component compiler_version "$(version_of "$CC" -dumpfullversion)"

# AOCL. Prefer an installation already present in the base image; otherwise install from
# the operator-supplied URI. AOCL is EULA-gated and is never fetched from a guessed URL.
find_aocl_root() {
    local candidate
    for candidate in "${AOCL_ROOT:-}" /opt/aocl /opt/AMD/aocl/aocl-linux-gcc-*; do
        [[ -n "$candidate" && -d "$candidate" ]] || continue
        [[ -n "$(find "$candidate" -name 'libblis-mt.so*' -o -name 'libblis-mt.a' 2>/dev/null | head -n1)" ]] || continue
        printf '%s' "$candidate"
        return 0
    done
    return 1
}

if aocl_root="$(find_aocl_root)"; then
    log "using AOCL already present at ${aocl_root}"
else
    [[ -n "${AOCL_DOWNLOAD_URI:-}" ]] ||
        fail "AMD AOCL ${AOCL_VERSION:-}" \
            "AOCL present in the base image, or aocl_download_uri set" \
            "AOCL is EULA-gated and cannot be downloaded automatically. Download AOCL ${AOCL_VERSION:-} from AMD, host it privately, and set aocl_download_uri to the .deb or tarball."

    log "installing AOCL from the operator-supplied URI"
    workdir="$(mktemp -d)"
    archive="${workdir}/$(basename "${AOCL_DOWNLOAD_URI%%\?*}")"
    curl --fail --silent --show-error --location --retry 3 --output "$archive" "$AOCL_DOWNLOAD_URI" ||
        fail "AOCL download" "archive downloaded from aocl_download_uri" \
            "Check the URI, egress from the build subnet, and any credential the location requires."

    case "$archive" in
    *.deb) apt-get install -y "$archive" ;;
    *.tar.gz | *.tgz) install -d /opt/aocl && tar -xf "$archive" -C /opt/aocl --strip-components=1 ;;
    *) fail "AOCL archive" "a .deb or .tar.gz archive" "Unsupported archive format: ${archive##*/}." ;;
    esac
    rm -rf "$workdir"

    aocl_root="$(find_aocl_root)" ||
        fail "AMD AOCL" "AOCL libraries present after installation" \
            "The archive did not produce libblis-mt under a known prefix. Set AOCL_ROOT explicitly."
fi

aocl_lib="$(dirname "$(find "$aocl_root" -name 'libblis-mt.so*' -o -name 'libblis-mt.a' | head -n1)")"
aocl_prefix="$(dirname "$aocl_lib")"

for lib in libflame libscalapack libfftw3; do
    [[ -n "$(find "$aocl_prefix" -name "${lib}.*" | head -n1)" ]] ||
        fail "AOCL ${lib}" "${lib} present under ${aocl_prefix}" \
            "Install the full AOCL bundle (BLIS, libFLAME, ScaLAPACK, FFTW), not a single component."
done

log "AOCL prefix: ${aocl_prefix}"
record_component math_library "aocl"
record_component aocl_version "${AOCL_VERSION:-unknown}"
record_component aocl_root "$aocl_prefix"

# HDF5. The distribution package is built with gfortran, so its .mod files must match the
# GCC major version used for VASP.
hdf5_lib=""
hdf5_include=""
if [[ "${HDF5_ENABLED:-false}" == "true" ]]; then
    apt-get install -y --no-install-recommends libhdf5-dev ||
        fail "HDF5" "libhdf5-dev installable" "Disable hdf5_enabled or provide an HDF5 build for this image."

    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
    hdf5_lib="/usr/lib/${multiarch}/hdf5/serial"
    hdf5_include="/usr/include/hdf5/serial"

    [[ -f "${hdf5_lib}/libhdf5_fortran.so" || -f "${hdf5_lib}/libhdf5_fortran.a" ]] ||
        fail "HDF5 Fortran bindings" "libhdf5_fortran under ${hdf5_lib}" \
            "The distribution HDF5 layout has changed. Set the HDF5 paths explicitly in cpu/makefile-overrides.sh."

    record_component hdf5_version "$(version_of dpkg-query --showformat='${Version}' --show libhdf5-dev)"
    record_component hdf5_root "$hdf5_lib"
else
    record_component hdf5_version "disabled"
fi

# Consumed by 20-environment-modules.sh and 31-vasp-build.sh.
cat >"$TOOLCHAIN_ENV" <<EOF
HPCX_DIR=${HPCX_DIR}
MPI_BIN=${HPCX_DIR}/ompi/bin
MPI_LIB=${HPCX_DIR}/ompi/lib
AOCL_PREFIX=${aocl_prefix}
AOCL_LIB=${aocl_lib}
HDF5_LIB=${hdf5_lib}
HDF5_INCLUDE=${hdf5_include}
CC=${CC}
CXX=${CXX}
FC=${FC}
OMPI_CC=${CC}
OMPI_CXX=${CXX}
OMPI_FC=${FC}
EOF

record_component numa_nodes "$(numactl --hardware 2>/dev/null | awk '/^available:/{print $2}')"
record_component cpu_model "$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)"
record_component cpu_target_arch "${CPU_TARGET_ARCH:-unset}"
