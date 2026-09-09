#!/usr/bin/env bash
# Install the "vasp" environment module. The modulefile configures only what VASP needs;
# user shell startup files are left untouched.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${VASP_VERSION:?VASP_VERSION must be set}"

MODULEFILE_DIR="${VASP_PREFIX}/modulefiles/vasp"
install -d -m 0755 "$MODULEFILE_DIR"

TOOLCHAIN_ENV="${VASP_STATE_DIR}/toolchain.env"
[[ -f "$TOOLCHAIN_ENV" ]] ||
    fail "toolchain environment" "${TOOLCHAIN_ENV} written by the ${BUILD_TYPE:-} toolchain script" \
        "Run the 10-* toolchain provisioning step before installing the module."

set -a
# shellcheck disable=SC1090
source "$TOOLCHAIN_ENV"
set +a

# The module exposes exactly the toolchain VASP was linked against, and nothing else.
runtime_paths=""
for dir in "${COMPILER_BIN:-}" "${MPI_BIN:-}"; do
    [[ -n "$dir" && -d "$dir" ]] && runtime_paths+="prepend-path PATH ${dir}"$'\n'
done
for dir in "${MPI_LIB:-}" "${AOCL_LIB:-}" "${COMPILER_LIB:-}" "${CUDA_LIB:-}" "${MATH_LIB:-}" "${HDF5_LIB:-}"; do
    [[ -n "$dir" && -d "$dir" ]] && runtime_paths+="prepend-path LD_LIBRARY_PATH ${dir}"$'\n'
done

cat >"${MODULEFILE_DIR}/${VASP_VERSION}" <<EOF
#%Module1.0
## VASP ${VASP_VERSION} (${BUILD_TYPE:-unknown} image)
proc ModulesHelp { } {
    puts stderr "Loads VASP ${VASP_VERSION} from ${VASP_PREFIX}/${VASP_VERSION}."
}
module-whatis "VASP ${VASP_VERSION} (${BUILD_TYPE:-unknown}, ${COMPILER_TOOLCHAIN:-unknown} toolchain)"

set vasp_root ${VASP_PREFIX}/${VASP_VERSION}

if { ![file isdirectory \$vasp_root] } {
    puts stderr "VASP is not installed at \$vasp_root"
}

${runtime_paths}prepend-path PATH \$vasp_root/bin
setenv VASP_ROOT \$vasp_root
setenv VASP_VERSION ${VASP_VERSION}
EOF

ln -sfn "$VASP_VERSION" "${MODULEFILE_DIR}/default" 2>/dev/null || true

# Make the modulefile discoverable system-wide without editing user dotfiles.
MODULESPATH_FILE=/etc/environment-modules/modulespath
if [[ -f "$MODULESPATH_FILE" ]]; then
    grep -qxF "${VASP_PREFIX}/modulefiles" "$MODULESPATH_FILE" ||
        printf '%s\n' "${VASP_PREFIX}/modulefiles" >>"$MODULESPATH_FILE"
else
    warn "$MODULESPATH_FILE not found; falling back to /etc/profile.d/vasp-modulepath.sh"
    printf 'export MODULEPATH="%s/modulefiles:${MODULEPATH}"\n' "$VASP_PREFIX" >/etc/profile.d/vasp-modulepath.sh
    chmod 0644 /etc/profile.d/vasp-modulepath.sh
fi

record_component environment_modules "$(version_of modulecmd --version 2>/dev/null || echo present)"
record_component modulefile "${MODULEFILE_DIR}/${VASP_VERSION}"
log "environment module installed: module load vasp"
