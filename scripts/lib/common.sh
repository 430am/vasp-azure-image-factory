#!/usr/bin/env bash
# Shared helpers for VASP image provisioning and validation scripts.
# Source this file; do not execute it.

set -euo pipefail

readonly VASP_STATE_DIR="${VASP_STATE_DIR:-/var/lib/vasp-image}"
readonly VASP_COMPONENTS_FILE="${VASP_STATE_DIR}/components.tsv"
readonly VASP_PREFIX="${VASP_PREFIX:-/opt/vasp}"
readonly VASP_MANIFEST="${VASP_PREFIX}/image-version.json"

log() { printf '[%s] [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SCRIPT_NAME:-vasp}" "$*"; }
warn() { log "WARNING: $*" >&2; }

# fail <component> <expected state> <remediation>
fail() {
    local component="$1" expected="$2" remediation="$3"
    {
        printf '\n'
        printf 'FAILED    : %s\n' "${SCRIPT_NAME:-unknown script}"
        printf 'COMPONENT : %s\n' "$component"
        printf 'EXPECTED  : %s\n' "$expected"
        printf 'REMEDIATE : %s\n' "$remediation"
        printf '\n'
    } >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 ||
        fail "$cmd" "'$cmd' available on PATH" "Install the package providing '$cmd' in the base image or an earlier provisioning step."
}

# Record a build-provenance fact. Consumed by common/40-provenance.sh.
record_component() {
    local key="$1"
    shift
    mkdir -p "$VASP_STATE_DIR"
    printf '%s\t%s\n' "$key" "$*" >>"$VASP_COMPONENTS_FILE"
    log "recorded ${key}=$*"
}

# First line of a version command, or "unknown" if the command is absent/fails.
version_of() {
    local out
    out="$("$@" 2>&1 | head -n1)" || out=""
    printf '%s' "${out:-unknown}"
}
