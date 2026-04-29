// ============================================================
// Seed Key Vault secrets and App Configuration key-values
// ============================================================

param keyVaultName string
param appConfigName string

@secure()
param logAnalyticsSharedKey string
param logAnalyticsWorkspaceId string

param logsIngestionDceUri string
param logsIngestionDcrImmutableId string
param logsIngestionStreamName string = 'Custom-IntuneUp'
param serviceBusQueueName string
param logTablePrefix string = 'IntuneUp'
param claimCheckStorageAccountName string
param passwordExpiryStorageAccountName string

@secure()
param allowedIssuerThumbprints string = ''

// ---- Key Vault secrets ----
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
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

resource cfgDceUri 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogsIngestion:DceUri'
  properties: { value: logsIngestionDceUri }
}

resource cfgDcrId 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogsIngestion:DcrImmutableId'
  properties: { value: logsIngestionDcrImmutableId }
}

resource cfgStreamName 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogsIngestion:StreamName'
  properties: { value: logsIngestionStreamName }
}

resource cfgClaimCheckContainer 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:ClaimCheck:ContainerName'
  properties: { value: 'claim-check' }
}

resource cfgClaimCheckStorage 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:ClaimCheck:StorageAccountName'
  properties: { value: claimCheckStorageAccountName }
}

resource cfgPwdExpiryTable 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:PasswordExpiry:TableName'
  properties: { value: 'PasswordExpiry' }
}

resource cfgPwdExpiryStorage 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:PasswordExpiry:StorageAccountName'
  properties: { value: passwordExpiryStorageAccountName }
}

// Key Vault references in App Configuration (so Functions can read everything from App Config)
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

// Non-secret security config (plain values in App Config)
resource cfgCheckRevocation 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:Security:CheckCertRevocation'
  properties: { value: 'false' }
}

resource cfgRequiredCertSubject 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:Security:RequiredCertSubject'
  properties: { value: '' }
}

resource cfgRequiredChainSubjects 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:Security:RequiredChainSubjects'
  properties: { value: '' }
}
