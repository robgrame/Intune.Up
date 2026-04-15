// ============================================================
// Azure App Configuration - centralized config for IntuneUp
// ============================================================

param name string
param location string
param tags object = {}

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'free'
  }
  properties: {
    disableLocalAuth: false
    enablePurgeProtection: false
  }
}

output appConfigName string = appConfig.name
output appConfigEndpoint string = appConfig.properties.endpoint
output appConfigId string = appConfig.id
