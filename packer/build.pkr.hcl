locals {
  provision_dir = "/tmp/vasp-provision"
  scripts_dir   = "${path.root}/../scripts"

  // Local paths: the shell provisioner uploads and executes each script. Shared helpers,
  // validation stages and makefile.include files come from the uploaded tree instead.
  build_scripts = concat(
    ["${path.root}/../scripts/common/00-base-packages.sh"],
    var.build_type == "cpu"
    ? ["${path.root}/../scripts/cpu/10-hpc-toolchain.sh"]
    : ["${path.root}/../scripts/gpu/10-nvidia-stack.sh"],
    [
      "${path.root}/../scripts/common/20-environment-modules.sh",
      "${path.root}/../scripts/common/30-vasp-install.sh",
      "${path.root}/../scripts/common/31-vasp-build.sh",
      "${path.root}/../scripts/common/40-provenance.sh",
    ],
  )

  // Values consumed by every provisioning script. Nothing here is secret except the SAS
  // token, which Packer redacts from build output because the variable is marked sensitive.
  provision_env = [
    "BUILD_TYPE=${var.build_type}",
    "TARGET_VM_SIZE=${var.target_vm_size}",
    "IMAGE_DEFINITION=${var.image_definition}",
    "IMAGE_VERSION=${var.image_version}",
    "GIT_SHA=${var.git_sha}",
    "BASE_IMAGE=${var.os_publisher}:${var.os_offer}:${var.os_sku}:${var.os_version}",
    "VASP_VERSION=${var.vasp_version}",
    "VASP_SOURCE_URI=${var.vasp_source_uri}",
    "VASP_SOURCE_SAS_TOKEN=${var.vasp_source_sas_token}",
    "VASP_ARCH_TEMPLATE=${var.vasp_arch_template}",
    "VASP_TARGETS=${var.vasp_targets}",
    "VASP_MAKE_ARGS=${var.vasp_make_args}",
    "COMPILER_TOOLCHAIN=${var.compiler_toolchain}",
    "GCC_VERSION=${var.gcc_version}",
    "MPI_FLAVOR=${var.mpi_flavor}",
    "MATH_LIBRARY=${var.math_library}",
    "CPU_TARGET_ARCH=${var.cpu_target_arch}",
    "GPU_TARGET_ARCH=${var.gpu_target_arch}",
    "GPU_HOST_ARCH=${var.gpu_host_arch}",
    "AOCL_VERSION=${var.aocl_version}",
    "AOCL_DOWNLOAD_URI=${var.aocl_download_uri}",
    "NVHPC_VERSION=${var.nvhpc_version}",
    "NVHPC_APT_REPO=${var.nvhpc_apt_repo}",
    "NVHPC_GPG_KEY_URI=${var.nvhpc_gpg_key_uri}",
    "CUDA_VERSION=${var.cuda_version}",
    "NVIDIA_DRIVER_VERSION=${var.nvidia_driver_version}",
    "HDF5_ENABLED=${var.hdf5_enabled}",
    "PROVISION_DIR=${local.provision_dir}",
  ]
}

build {
  name    = "vasp"
  sources = ["source.azure-arm.vasp"]

  provisioner "file" {
    source      = local.scripts_dir
    destination = "/tmp/vasp-provision-upload"
  }

  provisioner "shell" {
    inline = [
      "sudo rm -rf ${local.provision_dir}",
      "sudo mv /tmp/vasp-provision-upload ${local.provision_dir}",
      "sudo chown -R root:root ${local.provision_dir}",
      "sudo find ${local.provision_dir} -name '*.sh' -exec chmod 0755 {} +",
    ]
  }

  provisioner "shell" {
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = local.provision_env
    scripts          = local.build_scripts
    remote_folder    = "/tmp"
  }

  // In-image validation stages 1-3. Stage 4 (scientific smoke test) runs post-deployment
  // against a user-provided test case; licensed test material is never baked in.
  provisioner "shell" {
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = local.provision_env
    inline           = ["${local.provision_dir}/validate/run-validation.sh --stages 1,2,3 --build-type ${var.build_type}"]
  }

  provisioner "shell" {
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = local.provision_env
    scripts          = ["${path.root}/../scripts/common/90-cleanup.sh"]
    remote_folder    = "/tmp"
  }

  // Required by Azure before capture. Must be the final provisioner.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline          = ["/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"]
    inline_shebang  = "/bin/sh -x"
  }

  post-processor "manifest" {
    output     = "${path.root}/../manifest.json"
    strip_path = true

    custom_data = {
      build_type   = var.build_type
      vasp_version = var.vasp_version
      git_sha      = var.git_sha
      base_image   = "${var.os_publisher}:${var.os_offer}:${var.os_sku}:${var.os_version}"
    }
  }
}
