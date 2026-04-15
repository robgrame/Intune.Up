// ============================================================
// Azure Function App (Consumption plan, PowerShell runtime)
// ============================================================

param name string
param location string
param tags object = {}
param serviceBusConnectionString string
param queueName string
param appSettings object = {}

var storageAccountName = replace(toLower('st${name}'), '-', '')

// Storage Account (required by Azure Functions)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(storageAccountName, 24)
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// App Service Plan (Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'asp-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

// Merge base app settings with caller-provided settings
var baseAppSettings = {
  AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  WEBSITE_CONTENTSHARE: toLower(name)
  FUNCTIONS_EXTENSION_VERSION: '~4'
  FUNCTIONS_WORKER_RUNTIME: 'powershell'
  WEBSITE_RUN_FROM_PACKAGE: '1'
  SERVICEBUS_CONNECTION: serviceBusConnectionString
  SERVICEBUS_QUEUE_NAME: queueName
}

// Merge settings: base + caller-provided (caller overrides base)
var mergedSettings = union(baseAppSettings, appSettings)

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [for setting in objectKeys(mergedSettings): {
        name: setting
        value: mergedSettings[setting]
      }]
    }
  }
}

output functionAppName string = functionApp.name
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api/collect'
