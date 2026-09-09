#!/usr/bin/env bash
# Stage 1: operating system baseline.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

log "kernel: $(uname -a)"
[[ -r /etc/os-release ]] ||
    fail "/etc/os-release" "readable os-release file" "Unexpected base image; verify the marketplace image selection."
# shellcheck disable=SC1091
(. /etc/os-release && log "os: ${PRETTY_NAME}")

log "filesystem usage:"
df -hP / /var /opt 2>/dev/null | sed 's/^/  /'

root_free_gb="$(df -BG --output=avail / | tail -n1 | tr -dc '0-9')"
((root_free_gb >= 5)) ||
    fail "root filesystem" "at least 5 GB free on /" "Increase os_disk_size_gb or remove build artifacts before capture."

for cmd in bash python3 modulecmd numactl; do
    command -v "$cmd" >/dev/null 2>&1 || warn "expected command not found: ${cmd}"
done

require_cmd python3

[[ -f "$VASP_MANIFEST" ]] ||
    fail "build provenance" "${VASP_MANIFEST} present" "common/40-provenance.sh did not run. Check the Packer provisioner order."

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$VASP_MANIFEST" ||
    fail "build provenance" "valid JSON at ${VASP_MANIFEST}" "Inspect common/40-provenance.sh output."

log "stage 1 checks passed"
