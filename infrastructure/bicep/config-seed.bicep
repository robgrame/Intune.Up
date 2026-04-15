// ============================================================
// Seed Key Vault secrets and App Configuration key-values
// ============================================================

param keyVaultName string
param appConfigName string

@secure()
param serviceBusConnectionString string
@secure()
param logAnalyticsSharedKey string
param logAnalyticsWorkspaceId string
param serviceBusQueueName string
param logTablePrefix string = 'IntuneUp'

@secure()
param allowedIssuerThumbprints string = ''

// ---- Key Vault secrets ----
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secretSbConn 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'ServiceBusConnection'
  properties: { value: serviceBusConnectionString }
}

resource secretLaKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'LogAnalyticsSharedKey'
  properties: { value: logAnalyticsSharedKey }
}

resource secretIssuerThumbs 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'AllowedIssuerThumbprints'
  properties: { value: allowedIssuerThumbprints }
}

// ---- App Configuration key-values ----
resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' existing = {
  name: appConfigName
}

resource cfgQueueName 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:ServiceBus:QueueName'
  properties: { value: serviceBusQueueName }
}

resource cfgWorkspaceId 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:WorkspaceId'
  properties: { value: logAnalyticsWorkspaceId }
}

resource cfgTablePrefix 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:TablePrefix'
  properties: { value: logTablePrefix }
}

// Key Vault references in App Configuration (so Functions can read everything from App Config)
resource cfgRefSbConn 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:ServiceBus:ConnectionString'
  properties: {
    value: '{"uri":"${secretSbConn.properties.secretUri}"}'
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
  }
}

resource cfgRefLaKey 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:SharedKey'
  properties: {
    value: '{"uri":"${secretLaKey.properties.secretUri}"}'
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
  }
}

resource cfgRefIssuerThumbs 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:Security:AllowedIssuerThumbprints'
  properties: {
    value: '{"uri":"${secretIssuerThumbs.properties.secretUri}"}'
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
  }
}
