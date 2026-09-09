#!/usr/bin/env bash
# Remove build-only material before image capture: licensed VASP source, credentials,
# provisioning scripts, package caches and logs.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

# Licensed source and intermediate build artifacts must never reach a published image.
rm -rf /usr/local/src/vasp

rm -rf /root/.azure /home/*/.azure
rm -f /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys
rm -rf /root/.bash_history /home/*/.bash_history

if command -v apt-get >/dev/null 2>&1; then
    apt-get -y autoremove --purge >/dev/null
    apt-get -y clean
    rm -rf /var/lib/apt/lists/*
fi

find /var/log -type f -name '*.log' -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /tmp/vasp-provision-upload "${VASP_STATE_DIR}"

# Keep the manifest; drop everything else that was staged for the build.
rm -rf "${PROVISION_DIR:-/tmp/vasp-provision}"

[[ ! -d /usr/local/src/vasp ]] ||
    fail "cleanup" "VASP source tree removed" "Remove /usr/local/src/vasp before capture; licensed source must not be published."

log "build artifacts and credentials removed"
