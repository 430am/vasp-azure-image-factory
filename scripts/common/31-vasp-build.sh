#!/usr/bin/env bash
# Build and install VASP into ${VASP_PREFIX}/<version>.
#
# The build configuration starts from a VASP-shipped arch/makefile.include.* template and
# appends a generated override block, so no build flags are invented here. See
# cpu/makefile-overrides.sh and gpu/makefile-overrides.sh.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${VASP_VERSION:?VASP_VERSION must be set}"
: "${BUILD_TYPE:?BUILD_TYPE must be set}"
: "${VASP_ARCH_TEMPLATE:?VASP_ARCH_TEMPLATE must be set}"

SRC_ROOT_FILE="${VASP_STATE_DIR}/vasp-source-root"
TOOLCHAIN_ENV="${VASP_STATE_DIR}/toolchain.env"

if [[ ! -f "$SRC_ROOT_FILE" ]]; then
    warn "no staged VASP source - skipping build"
    record_component vasp_installed "false"
    exit 0
fi

[[ -f "$TOOLCHAIN_ENV" ]] ||
    fail "toolchain environment" "${TOOLCHAIN_ENV} written by the ${BUILD_TYPE} toolchain script" \
        "Run the 10-* toolchain provisioning step before building VASP."

set -a
# shellcheck disable=SC1090
source "$TOOLCHAIN_ENV"
set +a

src_root="$(cat "$SRC_ROOT_FILE")"
template="${src_root}/arch/${VASP_ARCH_TEMPLATE}"

[[ -f "$template" ]] ||
    fail "VASP arch template" "${VASP_ARCH_TEMPLATE} in ${src_root}/arch" \
        "Set vasp_arch_template to one of: $(find "${src_root}/arch" -maxdepth 1 -name 'makefile.include.*' -printf '%f ' 2>/dev/null)"

log "building VASP ${VASP_VERSION} (${BUILD_TYPE}) from ${VASP_ARCH_TEMPLATE}"
install -m 0644 "$template" "${src_root}/makefile.include"
"${PROVISION_DIR:-/tmp/vasp-provision}/${BUILD_TYPE}/makefile-overrides.sh" >>"${src_root}/makefile.include" ||
    fail "makefile.include overrides" "override block generated for ${BUILD_TYPE}" \
        "Check that the 10-* toolchain script exported every value the override script requires."

export PATH="${COMPILER_BIN:+${COMPILER_BIN}:}${MPI_BIN}:${PATH}"
export LD_LIBRARY_PATH="${MPI_LIB}:${AOCL_LIB:-}:${COMPILER_LIB:-}:${CUDA_LIB:-}:${MATH_LIB:-}:${LD_LIBRARY_PATH:-}"

command -v mpif90 >/dev/null 2>&1 ||
    fail "mpif90" "MPI compiler wrapper on PATH" "MPI_BIN=${MPI_BIN} does not contain mpif90."

# shellcheck disable=SC2086
make -C "$src_root" ${VASP_MAKE_ARGS:-} -j "$(nproc)" ${VASP_TARGETS:-std gam ncl} ||
    fail "VASP compilation" "make completes for targets '${VASP_TARGETS:-std gam ncl}'" \
        "Inspect the build log above. Change the toolchain in source control and rebuild; never patch makefile.include on the build VM."

install_dir="${VASP_PREFIX}/${VASP_VERSION}"
install -d -m 0755 "${install_dir}/bin"
find "${src_root}/bin" -maxdepth 1 -type f -perm -u+x -exec install -m 0755 {} "${install_dir}/bin/" \;
install -m 0644 "${src_root}/makefile.include" "${install_dir}/makefile.include"
ln -sfn "$VASP_VERSION" "${VASP_PREFIX}/current"

binaries="$(find "${install_dir}/bin" -maxdepth 1 -type f -printf '%f ')"
[[ -n "$binaries" ]] ||
    fail "VASP binaries" "at least one binary installed into ${install_dir}/bin" \
        "make reported success but produced no binaries. Check the requested targets."

record_component vasp_installed "true"
record_component vasp_install_dir "$install_dir"
record_component vasp_binaries "$binaries"
record_component vasp_arch_template "$VASP_ARCH_TEMPLATE"
record_component vasp_targets "${VASP_TARGETS:-std gam ncl}"
