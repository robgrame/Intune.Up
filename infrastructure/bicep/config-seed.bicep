// ============================================================
// Seed Key Vault secrets and App Configuration key-values
// ============================================================

param keyVaultName string
param appConfigName string

param logAnalyticsWorkspaceId string
param serviceBusQueueName string
param logTablePrefix string = 'IntuneUp'
param claimCheckStorageAccountName string
param passwordExpiryStorageAccountName string

@description('Data Collection Endpoint (DCE) logs ingestion URL')
param dceEndpoint string

@description('Default DCR Immutable ID – used when no per-use-case DCR is configured')
param dcrImmutableId string

@description('Per-use-case DCR immutable IDs to seed in App Configuration')
param dcrUseCases array = []

@secure()
param allowedIssuerThumbprints string = ''

// ---- Key Vault secrets ----
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
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

resource cfgDceEndpoint 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:DceEndpoint'
  properties: { value: dceEndpoint }
}

resource cfgDcrImmutableId 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:DcrImmutableId'
  properties: { value: dcrImmutableId }
}

resource cfgDcrUseCases 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for dcr in dcrUseCases: {
  parent: appConfig
  name: 'IntuneUp:LogAnalytics:Dcr:${dcr.useCase}:ImmutableId'
  properties: { value: dcr.immutableId }
}]

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
