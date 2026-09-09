#!/usr/bin/env bash
# Emit the makefile.include override block appended to VASP's shipped
# arch/makefile.include.gnu_ompi_aocl_omp template.
#
# Only variables that the template leaves as placeholders or as -march=native are
# overridden; nothing is invented. Later assignments win, and the template's LLIBS/INCS/
# CPP_OPTIONS are recursively expanded, so appending here is sufficient.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${AOCL_LIB:?AOCL_LIB must be set by cpu/10-hpc-toolchain.sh}"
: "${CPU_TARGET_ARCH:?CPU_TARGET_ARCH must be set, e.g. -march=znver3}"
: "${CC:?CC must be set}"
: "${CXX:?CXX must be set}"

aocl_prefix="$(dirname "$AOCL_LIB")"
aocl_include="${aocl_prefix}/include"

cat <<EOF

# ---- Azure VASP image factory overrides ----
VASP_TARGET_CPU = ${CPU_TARGET_ARCH}

CPP         = ${CC} -E -C -w \$*\$(FUFFIX) >\$*\$(SUFFIX) \$(CPP_OPTIONS)
CC_LIB      = ${CC}
CXX_PARS    = ${CXX}

# AMD AOCL: BLIS, libFLAME, ScaLAPACK and AOCL-FFTW. The *_ROOT assignments replace the
# template placeholders; the explicit -L covers AOCL layouts whose library directory is
# not named "lib".
AMDBLIS_ROOT      = ${aocl_prefix}
AMDLIBFLAME_ROOT  = ${aocl_prefix}
AMDSCALAPACK_ROOT = ${aocl_prefix}
AMDFFTW_ROOT      = ${aocl_prefix}

BLAS        = -L${AOCL_LIB} -lblis-mt
LAPACK      = -L${AOCL_LIB} -lflame
SCALAPACK   = -L${AOCL_LIB} -lscalapack
LLIBS      += -L${AOCL_LIB} -lfftw3 -lfftw3_omp
INCS       += -I${aocl_include}
EOF

if [[ "${HDF5_ENABLED:-false}" == "true" ]]; then
    : "${HDF5_LIB:?HDF5_LIB must be set when hdf5_enabled is true}"
    : "${HDF5_INCLUDE:?HDF5_INCLUDE must be set when hdf5_enabled is true}"
    cat <<EOF

CPP_OPTIONS+= -DVASP_HDF5
LLIBS      += -L${HDF5_LIB} -lhdf5_fortran -lhdf5
INCS       += -I${HDF5_INCLUDE}
EOF
fi
