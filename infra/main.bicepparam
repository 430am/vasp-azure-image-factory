using './main.bicep'

// Non-secret deployment values. Subscription and tenant IDs are never stored here:
// they are supplied by the deploying identity (az account / workload identity federation).
param galleryName = readEnvironmentVariable('VASP_GALLERY_NAME', 'galVaspImages')
param location = readEnvironmentVariable('VASP_LOCATION', 'centralus')
param publisher = readEnvironmentVariable('VASP_IMAGE_PUBLISHER', 'internal')

// Object ID of the person or pipeline that uploads the VASP archive. Without it, blob
// writes are denied: shared-key access is disabled, so control-plane roles are not enough.
param uploaderPrincipalId = readEnvironmentVariable('VASP_UPLOADER_PRINCIPAL_ID', '')
param uploaderPrincipalType = readEnvironmentVariable('VASP_UPLOADER_PRINCIPAL_TYPE', 'User')
