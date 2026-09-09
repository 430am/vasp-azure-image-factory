metadata description = 'Persistent Azure infrastructure for the VASP HPC image factory: Compute Gallery, image definitions and the private VASP source storage account.'

@description('Azure Compute Gallery name. Must be unique within the subscription.')
param galleryName string

@description('Location for the gallery. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Gallery description shown in the portal.')
param galleryDescription string = 'Validated VASP HPC images for Azure HBv3 and NC_A100_v4.'

@description('Publisher/offer identifiers applied to every image definition in this gallery.')
param publisher string = 'internal'

@description('User-assigned managed identity attached to the Packer build VM.')
param buildIdentityName string = 'id-vasp-image-builder'

@description('Storage account holding the licensed VASP source archive. Globally unique, 3-24 lowercase alphanumeric characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stvasp${uniqueString(resourceGroup().id)}'

@description('Private blob container holding the licensed VASP source archive.')
param vaspContainerName string = 'vasp-source'

@description('Optional principal that uploads the VASP archive. Granted Storage Blob Data Contributor. Required because shared-key access is disabled, so control-plane roles alone cannot write blobs.')
param uploaderPrincipalId string = ''

@description('Principal type of uploaderPrincipalId.')
@allowed(['User', 'Group', 'ServicePrincipal'])
param uploaderPrincipalType string = 'User'

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

// Attached to the temporary build VM so it can read the VASP archive without any secret.
resource buildIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: buildIdentityName
  location: location
  tags: tags
}

// The Packer build identity needs to read the gallery and publish new image versions.
var imageContributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor

resource buildIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: gallery
  name: guid(gallery.id, buildIdentity.id, imageContributorRoleId)
  properties: {
    principalId: buildIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', imageContributorRoleId)
  }
}

// Private storage for the licensed VASP source archive. Shared-key access is disabled so
// the only way in is Entra ID: the build VM reads with its managed identity, and nothing
// is reachable anonymously.
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
      }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource vaspContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: vaspContainerName
  properties: {
    publicAccess: 'None'
  }
}

var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Read-only, and scoped to the container rather than the account.
resource buildIdentityBlobRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vaspContainer
  name: guid(vaspContainer.id, buildIdentity.id, storageBlobDataReaderRoleId)
  properties: {
    principalId: buildIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
  }
}

resource uploaderBlobWrite 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(uploaderPrincipalId)) {
  scope: vaspContainer
  name: guid(vaspContainer.id, uploaderPrincipalId, storageBlobDataContributorRoleId)
  properties: {
    principalId: uploaderPrincipalId
    principalType: uploaderPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
  }
}

@description('Resource ID of the compute gallery.')
output galleryId string = gallery.id

@description('Gallery name, for use as the Packer gallery_name variable.')
output galleryNameOut string = gallery.name

@description('Names of the created image definitions.')
output imageDefinitionNames string[] = [for (definition, i) in imageDefinitions: definitions[i].name]

@description('Storage account holding the licensed VASP source archive.')
output vaspStorageAccountName string = storage.name

@description('Private container for the VASP source archive.')
output vaspContainerNameOut string = vaspContainer.name

@description('Base URI of the container. Append the archive file name to build vasp_source_uri.')
output vaspContainerUri string = '${storage.properties.primaryEndpoints.blob}${vaspContainer.name}/'

@description('Resource ID of the build identity, for the Packer build_identity_id variable.')
output buildIdentityResourceId string = buildIdentity.id

@description('Principal ID of the build identity.')
output buildIdentityPrincipalId string = buildIdentity.properties.principalId
