#!/usr/bin/env bash
# Stage 2 (cpu): HBv3 hardware and platform software - topology, NUMA, InfiniBand, MPI.
# CPU numbering and NUMA layout are discovered, never assumed.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

require_cmd lscpu
log "cpu topology:"
lscpu | sed 's/^/  /'

require_cmd numactl
log "numa topology:"
numactl --hardware | sed 's/^/  /'

numa_nodes="$(numactl --hardware | awk '/^available:/{print $2}')"
((numa_nodes >= 1)) ||
    fail "NUMA" "at least one NUMA node reported by numactl" "Check that numactl is installed and the VM SKU exposes NUMA topology."

if command -v ibv_devinfo >/dev/null 2>&1; then
    ibv_devinfo >/dev/null 2>&1 ||
        fail "InfiniBand" "ibv_devinfo reports an active HCA" \
            "Confirm the VM SKU is RDMA-capable (HBv3) and the IB stack from the Azure HPC image is intact."
    log "infiniband devices:"
    ibv_devinfo -l | sed 's/^/  /'
else
    fail "rdma-core" "ibv_devinfo available" "Install libibverbs-utils/rdma-core or use an Azure HPC base image."
fi

if command -v ucx_info >/dev/null 2>&1; then
    log "ucx: $(ucx_info -v 2>&1 | head -n1)"
else
    warn "ucx_info not available; UCX transport selection cannot be verified here"
fi

# HPC-X OpenMPI is exposed through the vasp module rather than the default PATH.
# shellcheck disable=SC1091
[[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh
module load vasp ||
    fail "environment module" "'module load vasp' succeeds" \
        "Check ${VASP_PREFIX}/modulefiles and the system MODULEPATH configuration."

command -v mpirun >/dev/null 2>&1 ||
    fail "HPC-X OpenMPI" "mpirun on PATH after 'module load vasp'" \
        "The vasp modulefile must prepend the HPC-X ompi/bin directory. Re-check cpu/10-hpc-toolchain.sh."

log "mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n2 | sed 's/^/  /'

case "$(command -v mpirun)" in
*hpcx*) log "MPI provider: HPC-X" ;;
*) fail "MPI provider" "mpirun resolved from the HPC-X installation" \
    "A different MPI is taking precedence on PATH. VASP must run with the implementation it was linked against." ;;
esac

log "stage 2 (cpu) checks passed"
