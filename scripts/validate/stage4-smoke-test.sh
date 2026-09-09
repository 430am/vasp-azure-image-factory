#!/usr/bin/env bash
# Stage 4: scientific smoke test using a user-provided VASP test case.
#
# LICENSING: no VASP test material is distributed with this repository. The operator
# supplies a small licensed test case via VASP_SMOKE_TEST_DIR (or --smoke-test-dir).
#
# Runtime is recorded but is not a pass/fail criterion: correctness testing and
# performance benchmarking are deliberately separate concerns.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

TEST_DIR="${VASP_SMOKE_TEST_DIR:-}"

if [[ -z "$TEST_DIR" ]]; then
    warn "VASP_SMOKE_TEST_DIR not set - stage 4 skipped"
    warn "Provide a small licensed VASP test case to validate scientific correctness."
    exit 0
fi

[[ -d "$TEST_DIR" ]] ||
    fail "smoke test case" "readable directory at ${TEST_DIR}" "Point VASP_SMOKE_TEST_DIR at a directory containing INCAR, POSCAR, POTCAR and KPOINTS."

for required in INCAR POSCAR POTCAR KPOINTS; do
    [[ -f "${TEST_DIR}/${required}" ]] ||
        fail "smoke test case" "${required} present in ${TEST_DIR}" "Supply a complete VASP test case."
done

# shellcheck disable=SC1091
[[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh
module load vasp ||
    fail "environment module" "'module load vasp' succeeds" "Run stage 3 first to diagnose the module configuration."

: "${VASP_BINARY:=vasp_std}"
: "${VASP_SMOKE_RANKS:=2}"
: "${VASP_SMOKE_TIMEOUT:=1800}"

command -v "$VASP_BINARY" >/dev/null 2>&1 ||
    fail "$VASP_BINARY" "VASP binary on PATH after 'module load vasp'" "Set VASP_BINARY to a binary present in \$VASP_ROOT/bin."

# UNRESOLVED: rank/thread placement and affinity flags are job-level configuration and are
# finalised with the MPI implementation. Defaults here are intentionally conservative.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cp "${TEST_DIR}"/* "$workdir/"

log "running ${VASP_BINARY} on ${VASP_SMOKE_RANKS} rank(s)"
start="$(date +%s)"
if command -v mpirun >/dev/null 2>&1; then
    (cd "$workdir" && timeout "$VASP_SMOKE_TIMEOUT" mpirun -np "$VASP_SMOKE_RANKS" "$VASP_BINARY" >run.log 2>&1) ||
        fail "$VASP_BINARY" "successful completion of the smoke test" "Inspect ${workdir}/run.log (retained on failure by re-running with VASP_SMOKE_KEEP=1)."
else
    (cd "$workdir" && timeout "$VASP_SMOKE_TIMEOUT" "$VASP_BINARY" >run.log 2>&1) ||
        fail "$VASP_BINARY" "successful completion of the smoke test" "Inspect ${workdir}/run.log."
fi
elapsed=$(($(date +%s) - start))

grep -q 'General timing and accounting' "${workdir}/OUTCAR" 2>/dev/null ||
    fail "VASP run" "OUTCAR reports normal termination" "The calculation did not complete. Inspect ${workdir}/OUTCAR and run.log."

log "smoke test completed in ${elapsed}s (recorded, not a pass/fail gate)"
log "stage 4 checks passed"
