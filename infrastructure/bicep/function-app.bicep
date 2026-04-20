// ============================================================
// Azure Function App (Consumption plan, PowerShell runtime)
// Uses System-Assigned Managed Identity for all connections:
//   - Storage: identity-based (no shared key)
//   - Key Vault: KV references in app settings
// ============================================================

param name string
param location string
param tags object = {}

@description('Key Vault URI for secret references')
param keyVaultUri string

@description('Extra app settings (name/value pairs)')
param extraAppSettings array = []

@description('Require client certificates (mutual TLS). Enable for HTTP entry point.')
param clientCertEnabled bool = false

@description('Subnet ID for VNet integration (outbound traffic goes through VNet)')
param vnetIntegrationSubnetId string = ''

@minLength(3)
@maxLength(24)
param storageAccountName string = take(replace(replace(toLower('st${name}'), '-', ''), '_', ''), 24)

// Storage Account (required by Azure Functions)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}

// Storage Blob Data Owner for the Function App MI
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
// Storage Account Contributor (needed for file share creation)
var storageAccountContributorRoleId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
// Storage Queue Data Contributor
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
// Storage File Data Privileged Contributor  
var storageFileDataPrivContribRoleId = '69566ab7-960f-475b-8e7c-b3118f30c6bd'

resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountContribRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageAccountContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageFileRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageFileDataPrivContribRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageFileDataPrivContribRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// App Service Plan (Basic B1 - quota available in this subscription)
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'asp-${name}'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    clientCertEnabled: clientCertEnabled
    virtualNetworkSubnetId: !empty(vnetIntegrationSubnetId) ? vnetIntegrationSubnetId : null
    vnetRouteAllEnabled: !empty(vnetIntegrationSubnetId)
    siteConfig: {
      netFrameworkVersion: 'v10.0'
      use32BitWorkerProcess: false
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat([
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'KEYVAULT_URI'
          value: keyVaultUri
        }
      ], extraAppSettings)
    }
  }
}

output functionAppName string = functionApp.name
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api/collect'
output principalId string = functionApp.identity.principalId
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
