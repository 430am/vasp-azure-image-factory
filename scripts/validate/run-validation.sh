#!/usr/bin/env bash
# Four-stage image validation. Runs inside the image, both during the Packer build
# (stages 1-3) and after deployment from the gallery (stages 1-4).
#
#   Stage 1  operating system
#   Stage 2  hardware and platform software (InfiniBand/RDMA or NVIDIA/CUDA)
#   Stage 3  VASP installation
#   Stage 4  scientific smoke test against a user-provided test case
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(dirname "$SCRIPT_DIR")}/lib/common.sh"

STAGES="1,2,3,4"
BUILD_TYPE="${BUILD_TYPE:-}"

usage() {
    cat <<'EOF'
Usage: run-validation.sh [--stages 1,2,3,4] [--build-type cpu|gpu] [--smoke-test-dir DIR]

  --stages          Comma-separated stages to run. Default: 1,2,3,4
  --build-type      cpu or gpu. Defaults to $BUILD_TYPE, then to the image manifest.
  --smoke-test-dir  Directory holding a user-provided VASP test case (stage 4).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --stages)
        STAGES="$2"
        shift 2
        ;;
    --build-type)
        BUILD_TYPE="$2"
        shift 2
        ;;
    --smoke-test-dir)
        export VASP_SMOKE_TEST_DIR="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
    esac
done

if [[ -z "$BUILD_TYPE" && -f "$VASP_MANIFEST" ]]; then
    BUILD_TYPE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["buildType"] or "")' "$VASP_MANIFEST" 2>/dev/null || true)"
fi

[[ "$BUILD_TYPE" == "cpu" || "$BUILD_TYPE" == "gpu" ]] ||
    fail "build type" "cpu or gpu" "Pass --build-type, or set BUILD_TYPE in the environment."

export BUILD_TYPE

run_stage() {
    local stage="$1" script="$2"
    [[ -x "$script" ]] || chmod +x "$script" 2>/dev/null || true
    log "=== stage ${stage}: ${script##*/} ==="
    bash "$script"
    log "=== stage ${stage}: PASS ==="
}

IFS=',' read -r -a requested <<<"$STAGES"
for stage in "${requested[@]}"; do
    case "$stage" in
    1) run_stage 1 "${SCRIPT_DIR}/stage1-os.sh" ;;
    2) run_stage 2 "${SCRIPT_DIR}/stage2-hardware-${BUILD_TYPE}.sh" ;;
    3) run_stage 3 "${SCRIPT_DIR}/stage3-vasp.sh" ;;
    4) run_stage 4 "${SCRIPT_DIR}/stage4-smoke-test.sh" ;;
    *) fail "stage selection" "stage in 1,2,3,4" "Got '${stage}'. Correct the --stages argument." ;;
    esac
done

log "validation complete for stages ${STAGES} (${BUILD_TYPE})"
