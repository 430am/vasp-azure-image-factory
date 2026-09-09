#!/usr/bin/env bash
# Emit the makefile.include override block appended to VASP's shipped
# arch/makefile.include.nvhpc_omp_acc template.
#
# The template hard-codes -gpu=cc60,cc70,cc80,cuda11.8 in CC/FC/FCL, so those three lines
# are restated verbatim with the compute capability and bundled CUDA version of this
# build. NVROOT is auto-detected by the template from nvfortran's location.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${GPU_TARGET_ARCH:?GPU_TARGET_ARCH must be set, e.g. cc80}"
: "${NVHPC_ROOT:?NVHPC_ROOT must be set by gpu/10-nvidia-stack.sh}"
: "${NVHPC_CUDA_VERSION:?NVHPC_CUDA_VERSION must be set by gpu/10-nvidia-stack.sh}"
: "${FFTW_LIB:?FFTW_LIB must be set by gpu/10-nvidia-stack.sh}"
: "${FFTW_INC:?FFTW_INC must be set by gpu/10-nvidia-stack.sh}"

gpu_flags="-acc -gpu=${GPU_TARGET_ARCH},cuda${NVHPC_CUDA_VERSION} -mp"

cat <<EOF

# ---- Azure VASP image factory overrides ----
VASP_TARGET_CPU = ${GPU_HOST_ARCH:--tp host}

# Pinned instead of derived from 'which nvfortran'.
NVROOT      = ${NVHPC_ROOT}

CC          = mpicc  ${gpu_flags}
FC          = mpif90 ${gpu_flags}
FCL         = mpif90 ${gpu_flags} -c++libs

# Host-side FFTW; cuFFT is linked by the template through -cudalib.
FFTW_ROOT   = $(dirname "$FFTW_INC")
LLIBS      += -L${FFTW_LIB} -lfftw3 -lfftw3_omp
INCS       += -I${FFTW_INC}
EOF
