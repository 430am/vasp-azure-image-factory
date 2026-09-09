source "azure-arm" "vasp" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id == "" ? null : var.client_id

  // Credentials are never stored in this repository. Use the signed-in az CLI identity
  // locally, or set use_azure_cli_auth = false to use managed identity / workload
  // identity federation (ARM_OIDC_* environment variables) in CI.
  use_azure_cli_auth = var.use_azure_cli_auth

  // The plugin rejects location and build_resource_group_name together: it derives the
  // region from the resource group when one is given. Exactly one is set here.
  location                            = var.build_resource_group == "" ? var.location : null
  build_resource_group_name           = var.build_resource_group == "" ? null : var.build_resource_group
  virtual_network_name                = var.build_virtual_network_name == "" ? null : var.build_virtual_network_name
  virtual_network_subnet_name         = var.build_virtual_network_subnet_name == "" ? null : var.build_virtual_network_subnet_name
  virtual_network_resource_group_name = var.build_virtual_network_resource_group_name == "" ? null : var.build_virtual_network_resource_group_name

  os_type         = "Linux"
  image_publisher = var.os_publisher
  image_offer     = var.os_offer
  image_sku       = var.os_sku
  image_version   = var.os_version

  vm_size         = var.target_vm_size
  os_disk_size_gb = var.os_disk_size_gb
  ssh_username    = var.ssh_username

  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.resource_group
    gallery_name         = var.gallery_name
    image_name           = var.image_definition
    image_version        = var.image_version
    replication_regions  = length(var.replication_regions) > 0 ? var.replication_regions : [var.location]
    storage_account_type = "Standard_LRS"
  }

  azure_tags = {
    workload     = "vasp"
    build_type   = var.build_type
    vasp_version = var.vasp_version
    base_image   = "${var.os_publisher}:${var.os_offer}:${var.os_sku}:${var.os_version}"
    git_sha      = var.git_sha
    managed_by   = "packer"
  }
}
