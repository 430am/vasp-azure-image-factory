#!/usr/bin/env bash
# Host-side image test: deploy a VM from a gallery image version, run the in-image
# validation stages, then destroy everything.
#
# COST CONTROL: this script creates an HBv3 or A100 VM. It never runs implicitly - it
# prints the SKU, region and estimated lifetime and requires explicit approval. All
# resources are created in a dedicated resource group that is deleted on exit, including
# on failure, unless KEEP_TEST_VM=1 is set for troubleshooting.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

BUILD_TYPE="${1:-}"
[[ "$BUILD_TYPE" == "cpu" || "$BUILD_TYPE" == "gpu" ]] ||
    fail "arguments" "usage: image-smoke-test.sh <cpu|gpu>" "Pass the build type to test."

for required in SUBSCRIPTION_ID LOCATION GALLERY_RESOURCE_GROUP GALLERY_NAME IMAGE_VERSION; do
    [[ -n "${!required:-}" ]] ||
        fail "$required" "environment variable ${required} set" "Export ${required} (see README, 'Deploying a test VM'). Subscription data is never hard-coded in this repository."
done

if [[ "$BUILD_TYPE" == "cpu" ]]; then
    : "${IMAGE_DEFINITION:=vasp-hbv3}"
    : "${TEST_VM_SIZE:=Standard_HB120rs_v3}"
else
    : "${IMAGE_DEFINITION:=vasp-nca100}"
    : "${TEST_VM_SIZE:=Standard_NC24ads_A100_v4}"
fi

: "${TEST_TIMEOUT:=3600}"
: "${VALIDATION_STAGES:=1,2,3}"

require_cmd az

suffix="$(date -u +%Y%m%d%H%M%S)"
rg="${TEST_RESOURCE_GROUP:-rg-vasp-imagetest-${BUILD_TYPE}-${suffix}}"
vm="vm-vasp-${BUILD_TYPE}-${suffix}"
image_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${GALLERY_RESOURCE_GROUP}/providers/Microsoft.Compute/galleries/${GALLERY_NAME}/images/${IMAGE_DEFINITION}/versions/${IMAGE_VERSION}"

cat <<EOF

About to create billable Azure compute:

  subscription   : ${SUBSCRIPTION_ID}
  region         : ${LOCATION}
  resource group : ${rg}  (deleted on exit)
  vm size        : ${TEST_VM_SIZE}
  image version  : ${IMAGE_DEFINITION}/${IMAGE_VERSION}
  max lifetime   : ${TEST_TIMEOUT}s

EOF

if [[ "${AUTO_APPROVE:-0}" != "1" ]]; then
    read -r -p "Type 'yes' to continue: " reply
    [[ "$reply" == "yes" ]] || fail "approval" "explicit approval to create compute" "Re-run with AUTO_APPROVE=1 in an authorised automated context."
fi

teardown() {
    local code=$?
    if [[ "${KEEP_TEST_VM:-0}" == "1" ]]; then
        warn "KEEP_TEST_VM=1 - resource group ${rg} retained. Delete it manually: az group delete -n ${rg} --yes"
    else
        log "deleting resource group ${rg}"
        az group delete --name "$rg" --yes --no-wait --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 || true
    fi
    exit "$code"
}
trap teardown EXIT

az group create --name "$rg" --location "$LOCATION" --subscription "$SUBSCRIPTION_ID" \
    --tags workload=vasp purpose=image-test ephemeral=true >/dev/null

log "creating ${TEST_VM_SIZE} from ${IMAGE_DEFINITION}/${IMAGE_VERSION}"
timeout "$TEST_TIMEOUT" az vm create \
    --resource-group "$rg" \
    --name "$vm" \
    --image "$image_id" \
    --size "$TEST_VM_SIZE" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address "" \
    --subscription "$SUBSCRIPTION_ID" >/dev/null ||
    fail "az vm create" "VM ${vm} created from ${image_id}" \
        "Check SKU quota and regional availability for ${TEST_VM_SIZE} in ${LOCATION}, and that the image version exists."

log "running in-image validation stages ${VALIDATION_STAGES}"
# UNRESOLVED: run-command truncates long output. Stage 4 needs the licensed test case to
# be present on the VM; uploading it is deferred until the test-data source is decided.
output="$(timeout "$TEST_TIMEOUT" az vm run-command invoke \
    --resource-group "$rg" \
    --name "$vm" \
    --command-id RunShellScript \
    --subscription "$SUBSCRIPTION_ID" \
    --scripts "sudo /opt/vasp/validate/run-validation.sh --stages ${VALIDATION_STAGES} --build-type ${BUILD_TYPE}" \
    --query 'value[0].message' -o tsv)" ||
    fail "az vm run-command" "run-command completes on ${vm}" \
        "Check the VM agent status and that the VM finished provisioning."

printf '%s\n' "$output"

# run-command always exits 0, so the validation result is read from its output.
! grep -q '^FAILED' <<<"$output" ||
    fail "image validation" "all requested validation stages pass on ${TEST_VM_SIZE}" \
        "Review the FAILED block above, then re-run with KEEP_TEST_VM=1 to inspect the VM."

grep -q 'validation complete' <<<"$output" ||
    fail "image validation" "run-validation.sh reaches completion" \
        "Validation output is incomplete or truncated. Re-run with KEEP_TEST_VM=1 and inspect the VM directly."

log "image test passed: ${IMAGE_DEFINITION}/${IMAGE_VERSION} on ${TEST_VM_SIZE}"
