metadata description = 'Azure Compute Gallery and image definitions for the VASP HPC image factory.'

@description('Azure Compute Gallery name. Must be unique within the subscription.')
param galleryName string

@description('Location for the gallery. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Gallery description shown in the portal.')
param galleryDescription string = 'Validated VASP HPC images for Azure HBv3 and NC_A100_v4.'

@description('Publisher/offer identifiers applied to every image definition in this gallery.')
param publisher string = 'internal'

@description('Optional user-assigned managed identity used by the image build pipeline. Empty skips the role assignment.')
param buildIdentityPrincipalId string = ''

@description('Tags applied to all resources.')
param tags object = {
  workload: 'vasp'
  managedBy: 'bicep'
}

type imageDefinitionConfig = {
  @description('Image definition name, e.g. vasp-hbv3.')
  name: string

  @description('SKU segment of the image identifier.')
  sku: string

  @description('Human-readable description of the target hardware.')
  description: string

  @description('Recommended vCPU range for VMs created from this image.')
  vCpuRange: { min: int, max: int }

  @description('Recommended memory range in GB for VMs created from this image.')
  memoryRange: { min: int, max: int }
}

// HBv3: 120 vCPU / 448 GB. HBv4: 176 vCPU / 768 GB.
// NC_A100_v4: 24-96 vCPU / 220-880 GB. ND_H100_v5: 96 vCPU / 1900 GB.
var imageDefinitions imageDefinitionConfig[] = [
  {
    name: 'vasp-hbv3'
    sku: 'vasp-hbv3-ubuntu-2204'
    description: 'VASP CPU image for Standard_HB120rs_v3 (AMD EPYC Milan-X, znver3, HPC-X, AOCL).'
    vCpuRange: { min: 120, max: 120 }
    memoryRange: { min: 448, max: 448 }
  }
  {
    name: 'vasp-hbv4'
    sku: 'vasp-hbv4-ubuntu-2204'
    description: 'VASP CPU image for Standard_HB176rs_v4 (AMD EPYC Genoa-X, znver4, HPC-X, AOCL).'
    vCpuRange: { min: 176, max: 176 }
    memoryRange: { min: 768, max: 768 }
  }
  {
    name: 'vasp-nca100'
    sku: 'vasp-nca100-ubuntu-2204'
    description: 'VASP GPU image for Standard_NC24/48/96ads_A100_v4 (A100 80GB PCIe, NVHPC OpenACC cc80).'
    vCpuRange: { min: 24, max: 96 }
    memoryRange: { min: 220, max: 880 }
  }
  {
    name: 'vasp-ndh100'
    sku: 'vasp-ndh100-ubuntu-2204'
    description: 'VASP GPU image for Standard_ND96isr_H100_v5 (H100 SXM, NVHPC OpenACC cc90).'
    vCpuRange: { min: 96, max: 96 }
    memoryRange: { min: 1900, max: 1900 }
  }
]

resource gallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: galleryName
  location: location
  tags: tags
  properties: {
    description: galleryDescription
  }
}

// Gen2 Linux images. Accelerated networking is required for HBv3 RDMA workloads.
resource definitions 'Microsoft.Compute/galleries/images@2023-07-03' = [
  for definition in imageDefinitions: {
    parent: gallery
    name: definition.name
    location: location
    tags: tags
    properties: {
      description: definition.description
      osType: 'Linux'
      osState: 'Generalized'
      hyperVGeneration: 'V2'
      architecture: 'x64'
      identifier: {
        publisher: publisher
        offer: definition.name
        sku: definition.sku
      }
      recommended: {
        vCPUs: definition.vCpuRange
        memory: definition.memoryRange
      }
      features: [
        {
          name: 'IsAcceleratedNetworkSupported'
          value: 'True'
        }
      ]
    }
  }
]

// The Packer build identity needs to read the gallery and publish new image versions.
var imageContributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor

resource buildIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(buildIdentityPrincipalId)) {
  scope: gallery
  name: guid(gallery.id, buildIdentityPrincipalId, imageContributorRoleId)
  properties: {
    principalId: buildIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', imageContributorRoleId)
  }
}

@description('Resource ID of the compute gallery.')
output galleryId string = gallery.id

@description('Gallery name, for use as the Packer gallery_name variable.')
output galleryNameOut string = gallery.name

@description('Names of the created image definitions.')
output imageDefinitionNames string[] = [for (definition, i) in imageDefinitions: definitions[i].name]
