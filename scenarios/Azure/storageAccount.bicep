// scope
targetScope = 'resourceGroup'

// parameters
@minLength(3)
@maxLength(18)
param name string

@allowed([
  'StorageV2'
])
param kind string = 'Standard_LRS'
param storageSKU string = 'Standard_LRS'

// resource definition
resource stg 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: name
  location: metadata.location
  tags: tags
  kind: kind
  sku: {
    name: storageSKU
    tier: 'Standard'
  }
  properties: {
    accessTier: 'Hot'    
    supportsHttpsTrafficOnly: false
    minimumTlsVersion: 'TLS1_0'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
  }
}

resource stgcontainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = {
  name: 'securehats2022cth'
  parent: stg
  properties: {
    publicAccess: 'string'
  }
}

output endpoint object = stg.properties.primaryEndpoints
output id string = stg.id
