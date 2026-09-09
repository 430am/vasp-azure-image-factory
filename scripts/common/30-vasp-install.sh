#!/usr/bin/env bash
# Stage the licensed VASP source from an authorized private location.
#
# LICENSING: VASP source is commercial. It is fetched at build time from a private
# location supplied by the operator, is never committed to this repository, never leaves
# the build VM, and is removed by common/90-cleanup.sh before image capture.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

: "${VASP_VERSION:?VASP_VERSION must be set}"

SRC_DIR="/usr/local/src/vasp"
STAGED_MARKER="${VASP_STATE_DIR}/vasp-source-staged"

if [[ -z "${VASP_SOURCE_URI:-}" ]]; then
    warn "VASP_SOURCE_URI is empty - skipping VASP source staging and build."
    warn "The image will be published without VASP. Set vasp_source_uri to an authorized private archive."
    record_component vasp_installed "false"
    record_component vasp_skip_reason "vasp_source_uri not provided"
    exit 0
fi

install -d -m 0700 "$SRC_DIR"

archive="${SRC_DIR}/$(basename "${VASP_SOURCE_URI%%\?*}")"

if [[ -f "$STAGED_MARKER" && -f "$archive" ]]; then
    log "VASP source already staged at ${archive}"
else
    log "downloading VASP source archive (URI and credentials are not logged)"

    # curl reads its configuration from stdin so that neither the SAS token nor a bearer
    # token appears in the process list or in build output.
    {
        printf 'url = "%s%s"\n' "$VASP_SOURCE_URI" "${VASP_SOURCE_SAS_TOKEN:-}"
        printf 'output = "%s"\n' "$archive"
        printf 'fail\nsilent\nshow-error\nlocation\nretry = 3\n'
        if [[ -z "${VASP_SOURCE_SAS_TOKEN:-}" && "$VASP_SOURCE_URI" == *".blob.core.windows.net/"* ]]; then
            # Managed identity is the preferred credential path on an Azure build VM.
            token="$(curl -s -H 'Metadata: true' \
                'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' |
                python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')" ||
                fail "managed identity" "an access token for storage.azure.com" \
                    "Assign a managed identity with Storage Blob Data Reader to the build VM, or supply vasp_source_sas_token."
            printf 'header = "Authorization: Bearer %s"\n' "$token"
            printf 'header = "x-ms-version: 2021-08-06"\n'
        fi
    } | curl --config - ||
        fail "VASP source download" "archive downloaded to ${archive}" \
            "Verify vasp_source_uri, network egress from the build subnet, and the build VM credential (managed identity or SAS)."

    if [[ -n "${VASP_SOURCE_SHA256:-}" ]]; then
        printf '%s  %s\n' "$VASP_SOURCE_SHA256" "$archive" | sha256sum --check --status ||
            fail "VASP source integrity" "sha256 matches VASP_SOURCE_SHA256" \
                "The downloaded archive does not match the expected checksum. Do not build from it."
        log "source archive checksum verified"
    else
        warn "VASP_SOURCE_SHA256 not set - archive integrity is unverified"
    fi

    tar -xf "$archive" -C "$SRC_DIR" ||
        fail "VASP source archive" "readable tar archive" "Confirm the archive format and that the download completed."
    : >"$STAGED_MARKER"
fi

srcroot="$(find "$SRC_DIR" -maxdepth 1 -mindepth 1 -type d | head -n1)"
[[ -n "$srcroot" ]] ||
    fail "VASP source tree" "an extracted source directory under ${SRC_DIR}" "Check the archive layout."

printf '%s\n' "$srcroot" >"${VASP_STATE_DIR}/vasp-source-root"
chmod -R go-rwx "$SRC_DIR"
log "VASP source staged (contents intentionally not listed)"
record_component vasp_source_staged "true"
