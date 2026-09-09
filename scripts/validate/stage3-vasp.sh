#!/usr/bin/env bash
# Stage 3: VASP installation - binaries present, dynamic linkage resolves, module loads.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

require_cmd python3

installed="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["vasp"]["installed"])' "$VASP_MANIFEST")"

if [[ "$installed" != "True" ]]; then
    reason="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["vasp"].get("skipReason") or "unknown")' "$VASP_MANIFEST")"
    warn "VASP is not installed in this image (reason: ${reason}) - stage 3 skipped"
    warn "This image is a toolchain-only image and must not be published as a VASP image."
    exit 0
fi

[[ -L "${VASP_PREFIX}/current" ]] ||
    fail "${VASP_PREFIX}/current" "symlink to the installed VASP version" "Check common/31-vasp-build.sh installation step."

mapfile -t binaries < <(find "${VASP_PREFIX}/current/bin" -maxdepth 1 -type f -perm -u+x)
((${#binaries[@]} > 0)) ||
    fail "VASP binaries" "at least one executable in ${VASP_PREFIX}/current/bin" "Check that the build installed its binaries."

for binary in "${binaries[@]}"; do
    log "checking ${binary}"
    ldd "$binary" | sed 's/^/  /'
    ! ldd "$binary" | grep -q 'not found' ||
        fail "$(basename "$binary")" "all shared libraries resolve" \
            "A runtime dependency is missing from the image. Ensure the libraries used at build time (MPI, math, CUDA) are installed in the image, not only in the build environment."
done

# shellcheck disable=SC1091
[[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh
if command -v module >/dev/null 2>&1; then
    module load vasp ||
        fail "environment module" "'module load vasp' succeeds" "Check ${VASP_PREFIX}/modulefiles and the system MODULEPATH configuration."
    log "module load vasp: OK (VASP_ROOT=${VASP_ROOT:-unset})"
else
    fail "environment-modules" "'module' function available" "Install environment-modules and ensure /etc/profile.d/modules.sh is present."
fi

# A bare launch without INCAR/POSCAR is expected to exit non-zero; it proves the binary
# loads and starts, which is all stage 3 asserts. Scientific correctness is stage 4.
primary="${binaries[0]}"
launch_dir="$(mktemp -d)"
trap 'rm -rf "$launch_dir"' EXIT
(cd "$launch_dir" && timeout 60 "$primary" >launch.log 2>&1) || true
grep -qiE 'error|vasp' "${launch_dir}/launch.log" ||
    warn "no recognisable output from ${primary##*/}; inspect manually"
log "binary launch check complete for ${primary##*/}"

log "stage 3 checks passed"
