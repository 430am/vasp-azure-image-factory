#!/usr/bin/env bash
# Stage 2 (gpu): NC_A100_v4 hardware and platform software - GPUs, driver, CUDA.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

require_cmd lscpu
log "cpu topology:"
lscpu | sed 's/^/  /'

require_cmd nvidia-smi
nvidia-smi ||
    fail "NVIDIA driver" "nvidia-smi runs successfully" \
        "Verify the VM SKU exposes A100 GPUs and that the driver matches the running kernel."

gpu_count="$(nvidia-smi --list-gpus | wc -l)"
((gpu_count >= 1)) ||
    fail "GPU count" "at least one GPU visible" "Check the VM SKU and driver installation."

log "gpu count: ${gpu_count}"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv | sed 's/^/  /'

nvidia-smi --query-gpu=name --format=csv,noheader | grep -qiE 'A100|H100' ||
    warn "GPU model is neither A100 nor H100; this image targets NC_A100_v4 and ND_H100_v5 SKUs"

# The binary is compiled for a specific compute capability; a mismatch will not run.
compute_cap="cc$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d '.')"
target_cc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["toolchain"]["gpuTargetArch"] or "")' "$VASP_MANIFEST")"
log "device compute capability: ${compute_cap}, image built for: ${target_cc:-unknown}"
[[ -z "$target_cc" || ",${target_cc}," == *",${compute_cap},"* ]] ||
    fail "GPU compute capability" "image built for ${compute_cap}" \
        "This image targets ${target_cc}. Deploy it on a matching SKU, or rebuild with gpu_target_arch=${compute_cap}."

# The NVIDIA HPC SDK is exposed through the vasp module rather than the default PATH.
# shellcheck disable=SC1091
[[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh
module load vasp ||
    fail "environment module" "'module load vasp' succeeds" \
        "Check ${VASP_PREFIX}/modulefiles and the system MODULEPATH configuration."

for tool in nvfortran nvc nvc++ mpirun; do
    command -v "$tool" >/dev/null 2>&1 ||
        fail "NVIDIA HPC SDK" "${tool} on PATH after 'module load vasp'" \
            "The vasp modulefile must prepend the NVHPC compilers and comm_libs bin directories."
done

log "nvfortran: $(nvfortran --version 2>&1 | head -n2 | tr '\n' ' ')"
log "cuda toolkit: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cuda"]["toolkitVersion"])' "$VASP_MANIFEST")"

log "stage 2 (gpu) checks passed"
