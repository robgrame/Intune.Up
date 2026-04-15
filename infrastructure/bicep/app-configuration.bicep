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
    name: 'standard'
  }
  properties: {
    disableLocalAuth: false
    enablePurgeProtection: false
    // publicNetworkAccess stays Enabled during deployment for ARM to seed config values.
    // Disable manually after deployment or via a post-deploy script:
    //   az appconfig update --name appcs-intuneup-dev --resource-group rg-intuneup-dev --enable-public-network false
  }
}

output appConfigName string = appConfig.name
output appConfigEndpoint string = appConfig.properties.endpoint
output appConfigId string = appConfig.id
