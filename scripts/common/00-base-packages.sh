#!/usr/bin/env bash
# Minimal base packages required by later provisioning and validation steps.
# Deliberately small: every extra package is extra attack surface in the image.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

PACKAGES=(
    ca-certificates
    curl
    environment-modules
    numactl
    pciutils
    python3
)

command -v apt-get >/dev/null 2>&1 ||
    fail "package manager" "apt-get present (Ubuntu base image)" "Use an Ubuntu base image or extend this script for the target distribution."

missing=()
for pkg in "${PACKAGES[@]}"; do
    dpkg-query --show --showformat='${db:Status-Status}\n' "$pkg" 2>/dev/null | grep -qx installed || missing+=("$pkg")
done

if ((${#missing[@]} == 0)); then
    log "all base packages already installed"
else
    log "installing: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends "${missing[@]}"
fi

install -d -m 0755 "$VASP_STATE_DIR" "$VASP_PREFIX"

# Validation stages and shared helpers stay in the image so a deployed VM can be
# re-validated. They contain no licensed VASP material and no secrets.
if [[ -n "${PROVISION_DIR:-}" && -d "${PROVISION_DIR}/validate" ]]; then
    cp -r "${PROVISION_DIR}/validate" "${PROVISION_DIR}/lib" "$VASP_PREFIX/"
    chmod -R go-w "${VASP_PREFIX}/validate" "${VASP_PREFIX}/lib"
    log "validation scripts installed to ${VASP_PREFIX}/validate"
fi

record_component os "$(. /etc/os-release && printf '%s %s' "$NAME" "$VERSION_ID")"
record_component kernel "$(uname -r)"
record_component architecture "$(uname -m)"
