#!/usr/bin/env bash
# Render build provenance to /opt/vasp/image-version.json from the facts recorded by the
# preceding provisioning scripts. Contains no licensed VASP material and no secrets.
set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
export SCRIPT_NAME
# shellcheck source=../lib/common.sh
source "${PROVISION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh"

require_cmd python3

record_component build_timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record_component git_sha "${GIT_SHA:-unknown}"
record_component image_definition "${IMAGE_DEFINITION:-unknown}"
record_component image_version "${IMAGE_VERSION:-unknown}"
record_component base_image "${BASE_IMAGE:-unknown}"
record_component build_type "${BUILD_TYPE:-unknown}"
record_component target_vm_size "${TARGET_VM_SIZE:-unknown}"
record_component vasp_version "${VASP_VERSION:-unknown}"

install -d -m 0755 "$VASP_PREFIX"

python3 - "$VASP_COMPONENTS_FILE" "$VASP_MANIFEST" <<'PY'
import json
import sys

components_file, manifest_file = sys.argv[1], sys.argv[2]

facts = {}
with open(components_file, encoding="utf-8") as handle:
    for line in handle:
        if "\t" not in line:
            continue
        key, value = line.rstrip("\n").split("\t", 1)
        facts[key] = value.strip()


def pop(key, default=None):
    return facts.pop(key, default)


manifest = {
    "schemaVersion": 1,
    "image": {
        "definition": pop("image_definition"),
        "version": pop("image_version"),
        "buildType": pop("build_type"),
        "targetVmSize": pop("target_vm_size"),
        "baseImage": pop("base_image"),
        "buildTimestamp": pop("build_timestamp"),
        "gitSha": pop("git_sha"),
    },
    "os": {
        "name": pop("os"),
        "kernel": pop("kernel"),
        "architecture": pop("architecture"),
    },
    "vasp": {
        "version": pop("vasp_version"),
        "installed": pop("vasp_installed", "false") == "true",
        "installDir": pop("vasp_install_dir"),
        "binaries": (pop("vasp_binaries") or "").split(),
        "archTemplate": pop("vasp_arch_template"),
        "targets": pop("vasp_targets"),
        "skipReason": pop("vasp_skip_reason"),
    },
    "toolchain": {
        "compiler": pop("compiler_toolchain"),
        "compilerVersion": pop("compiler_version"),
        "mpi": {
            "flavor": pop("mpi_flavor"),
            "version": pop("mpi_version"),
            "root": pop("mpi_root"),
        },
        "mathLibrary": pop("math_library"),
        "aoclVersion": pop("aocl_version"),
        "aoclRoot": pop("aocl_root"),
        "fftLibrary": pop("fft_library"),
        "hdf5Version": pop("hdf5_version"),
        "cpuTargetArch": pop("cpu_target_arch"),
        "gpuTargetArch": pop("gpu_target_arch"),
    },
    "hardware": {
        "cpuModel": pop("cpu_model"),
        "numaNodes": pop("numa_nodes"),
        "infinibandDevices": pop("infiniband_devices"),
        "ucxVersion": pop("ucx_version"),
        "gpuModel": pop("gpu_model"),
        "gpuCount": pop("gpu_count"),
        "gpuComputeCapability": pop("gpu_compute_capability"),
    },
    "cuda": {
        "driverVersion": pop("nvidia_driver_version"),
        "toolkitVersion": pop("cuda_toolkit_version"),
        "toolkitPath": pop("cuda_toolkit_path"),
        "driverApiVersion": pop("cuda_driver_api"),
        "nvhpcRoot": pop("nvhpc_root"),
    },
    "environmentModules": {
        "version": pop("environment_modules"),
        "modulefile": pop("modulefile"),
    },
}

# Anything not explicitly mapped is still recorded rather than silently dropped.
if facts:
    manifest["additional"] = facts

with open(manifest_file, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

chmod 0644 "$VASP_MANIFEST"
log "wrote provenance manifest to ${VASP_MANIFEST}"
cat "$VASP_MANIFEST"
