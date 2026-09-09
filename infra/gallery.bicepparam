using './gallery.bicep'

// Non-secret deployment values. Subscription and tenant IDs are never stored here:
// they are supplied by the deploying identity (az account / workload identity federation).
param galleryName = readEnvironmentVariable('VASP_GALLERY_NAME', 'galVaspImages')
param location = readEnvironmentVariable('VASP_LOCATION', 'centralus')
param publisher = readEnvironmentVariable('VASP_IMAGE_PUBLISHER', 'internal')
param buildIdentityPrincipalId = readEnvironmentVariable('VASP_BUILD_IDENTITY_PRINCIPAL_ID', '')
