// ============================================================
// Intune.Up - Main Bicep deployment
// Deploys: Log Analytics, Service Bus, Key Vault, App Config,
//          Azure Functions (HTTP + SB trigger), RBAC, Seed config
//
// Deploy order (handled by implicit dependencies):
//   1. Log Analytics, Service Bus, Key Vault, App Config
//   2. Function Apps (get MI + KV URI)
//   3. RBAC assignments (MI -> KV + App Config)
//   4. Config seed (secrets -> KV, values -> App Config)
// ============================================================

targetScope = 'resourceGroup'

@description('Base name used to derive all resource names')
param baseName string = 'intuneup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag: dev, dev2, test, prod')
@allowed(['dev', 'dev2', 'test', 'prod'])
param environment string = 'dev'

@description('Log Analytics retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Comma-separated list of allowed issuer/CA certificate thumbprints (any cert signed by these CAs is accepted)')
@secure()
param allowedIssuerThumbprints string = ''

@description('Deploy API Management gateway in front of HTTP Function')
param deployApim bool = true

@description('Deploy Azure Automation Account (legacy runbook approach)')
param deployAutomationAccount bool = true

@description('Deploy Timer Function for password expiry job (replaces Automation runbook)')
param deployTimerFunction bool = true

var tags = {
  project: 'IntuneUp'
  environment: environment
  managedBy: 'bicep'
}

// ---- Step 1: Core resources ----
// Note: VNet + Private Endpoints available in network.bicep + private-endpoints.bicep
// for enterprise/production deployments (requires SB Premium + AppConfig Standard).
// App Gateway WAF v2 available in app-gateway.bicep (separate deploy).

module logAnalytics 'log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: 'law-${baseName}-${environment}'
    location: location
    retentionDays: logRetentionDays
    tags: tags
  }
}

module serviceBus 'service-bus.bicep' = {
  name: 'service-bus'
  params: {
    namespaceName: 'sb-${baseName}-${environment}'
    queueName: 'device-telemetry'
    location: location
    tags: tags
  }
}

module keyVault 'key-vault.bicep' = {
  name: 'key-vault'
  params: {
    name: 'kv-${baseName}-${environment}'
    location: location
    tags: tags
  }
}

module appConfig 'app-configuration.bicep' = {
  name: 'app-configuration'
  params: {
    name: 'appcs-${baseName}-${environment}'
    location: location
    tags: tags
  }
}

module automationAccount 'automation-account.bicep' = if (deployAutomationAccount) {
  name: 'automation-account'
  params: {
    name: 'aa-${baseName}-${environment}'
    location: location
    tags: tags
  }
}

module appInsights 'app-insights.bicep' = {
  name: 'app-insights'
  params: {
    name: 'appi-${baseName}-${environment}'
    location: location
    workspaceId: logAnalytics.outputs.workspaceResourceId
    tags: tags
  }
}

// ---- Data Collection Endpoint (Logs Ingestion API) ----
module dce 'data-collection-endpoint.bicep' = {
  name: 'data-collection-endpoint'
  params: {
    name: 'dce-${baseName}-${environment}'
    location: location
    tags: tags
  }
}

// ---- Data Collection Rules – one per use case ----
// Each DCR's immutableId is stored in App Config under
// IntuneUp:LogAnalytics:Dcr:{UseCase}:ImmutableId.
// The first DCR (LoginInformation) is also the default (IntuneUp:LogAnalytics:DcrImmutableId).
module dcrLoginInformation 'data-collection-rule.bicep' = {
  name: 'dcr-login-information'
  params: {
    name: 'dcr-${baseName}-LoginInformation-${environment}'
    location: location
    dceResourceId: dce.outputs.dceResourceId
    workspaceResourceId: logAnalytics.outputs.workspaceResourceId
    tablePrefix: 'IntuneUp'
    useCase: 'LoginInformation'
    retentionDays: logRetentionDays
    tags: tags
  }
}

module dcrPasswordExpiryTrigger 'data-collection-rule.bicep' = {
  name: 'dcr-password-expiry-trigger'
  params: {
    name: 'dcr-${baseName}-PasswordExpiryTrigger-${environment}'
    location: location
    dceResourceId: dce.outputs.dceResourceId
    workspaceResourceId: logAnalytics.outputs.workspaceResourceId
    tablePrefix: 'IntuneUp'
    useCase: 'PasswordExpiryTrigger'
    retentionDays: logRetentionDays
    tags: tags
  }
}

// ---- Supporting storage accounts (for claim-check, password-expiry) ----
// Keep names short to stay within 24-character limit
resource stClaimCheck 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${baseName}cc${environment}'
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

resource stPwdExp 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${baseName}pe${environment}'
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

// ---- Step 2: Function Apps (depend on KV for URI in app settings) ----

module functionHttp 'function-app.bicep' = {
  name: 'function-http'
  params: {
    name: 'func-${baseName}-http-${environment}'
    storageAccountName: 'st${baseName}http${environment}'
    location: location
    tags: tags
    keyVaultUri: keyVault.outputs.keyVaultUri
    clientCertEnabled: false    // Enable after deployment if mTLS is needed
    extraAppSettings: [
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
      }
      {
        name: 'IntuneUp__ServiceBus__Namespace'
        value: '${serviceBus.outputs.namespaceName}.servicebus.windows.net'
      }
      {
        name: 'IntuneUp__ServiceBus__QueueName'
        value: serviceBus.outputs.queueName
      }
      {
        name: 'IntuneUp__PasswordExpiry__StorageAccountName'
        value: 'st${baseName}pe${environment}'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: appInsights.outputs.connectionString
      }
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
    ]
  }
}

module functionSb 'function-app.bicep' = {
  name: 'function-sb'
  params: {
    name: 'func-${baseName}-sb-${environment}'
    storageAccountName: 'st${baseName}sb${environment}'
    location: location
    tags: tags
    keyVaultUri: keyVault.outputs.keyVaultUri
    extraAppSettings: [
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
      }
      {
        // Identity-based Service Bus connection for trigger binding (disableLocalAuth=true)
        name: 'ServiceBusConnection__fullyQualifiedNamespace'
        value: '${serviceBus.outputs.namespaceName}.servicebus.windows.net'
      }
      {
        name: 'ServiceBusQueueName'
        value: serviceBus.outputs.queueName
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: appInsights.outputs.connectionString
      }
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
    ]
  }
}

// ---- Step 2b: API Management (gateway in front of HTTP Function) ----

module apim 'api-management.bicep' = if (deployApim) {
  name: 'api-management'
  params: {
    name: 'apim-${baseName}-${environment}'
    location: location
    tags: tags
    publisherEmail: 'admin@intune-up.local'
    publisherName: 'IntuneUp'
    backendFunctionHostname: functionHttp.outputs.functionAppName == '' ? '' : '${functionHttp.outputs.functionAppName}.azurewebsites.net'
  }
}

// ---- Step 2c: Timer Function (replaces Automation runbook for password expiry) ----

module functionTimer 'function-app.bicep' = if (deployTimerFunction) {
  name: 'function-timer'
  params: {
    name: 'func-${baseName}-timer-${environment}'
    storageAccountName: 'st${baseName}tmr${environment}'
    location: location
    tags: tags
    keyVaultUri: keyVault.outputs.keyVaultUri
    extraAppSettings: [
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
      }
      {
        name: 'IntuneUp__PasswordExpiry__StorageAccountName'
        value: 'st${baseName}pe${environment}'
      }
      {
        name: 'IntuneUp__PasswordExpiry__TableName'
        value: 'PasswordExpiry'
      }
      {
        name: 'IntuneUp__PasswordExpiry__MaxAgeDays'
        value: '90'
      }
      {
        name: 'IntuneUp__PasswordExpiry__ThresholdDays'
        value: '10'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: appInsights.outputs.connectionString
      }
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
    ]
  }
}

// ---- Step 3: RBAC (Function App MIs + Automation Account -> KV + App Config + Service Bus + Storage + DCR) ----

module rbac 'rbac-assignments.bicep' = {
  name: 'rbac-assignments'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    appConfigName: appConfig.outputs.appConfigName
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    logAnalyticsWorkspaceName: 'law-${baseName}-${environment}'
    principalIds: concat([
      functionHttp.outputs.principalId
      functionSb.outputs.principalId
    ], deployAutomationAccount ? [automationAccount.outputs.principalId] : [], deployTimerFunction ? [functionTimer.outputs.principalId] : [])
    httpFunctionPrincipalId: functionHttp.outputs.principalId
    sbFunctionPrincipalId: functionSb.outputs.principalId
    automationAccountPrincipalId: deployAutomationAccount ? automationAccount.outputs.principalId : ''
    httpStorageAccountName: 'st${baseName}http${environment}'
    passwordExpiryStorageAccountName: 'st${baseName}pe${environment}'
    dcrResourceIds: [
      dcrLoginInformation.outputs.dcrResourceId
      dcrPasswordExpiryTrigger.outputs.dcrResourceId
    ]
    timerFunctionPrincipalId: deployTimerFunction ? functionTimer.outputs.principalId : ''
  }
}

// ---- Step 4: Seed secrets and config ----

module configSeed 'config-seed.bicep' = {
  name: 'config-seed'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    appConfigName: appConfig.outputs.appConfigName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    serviceBusQueueName: serviceBus.outputs.queueName
    claimCheckStorageAccountName: 'st${baseName}cc${environment}'
    passwordExpiryStorageAccountName: 'st${baseName}pe${environment}'
    allowedIssuerThumbprints: allowedIssuerThumbprints
    dceEndpoint: dce.outputs.dceEndpoint
    dcrImmutableId: dcrLoginInformation.outputs.dcrImmutableId
    dcrUseCases: [
      { useCase: 'PasswordExpiryTrigger', immutableId: dcrPasswordExpiryTrigger.outputs.dcrImmutableId }
    ]
  }
}

// ---- Outputs ----
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output httpFunctionUrl string = functionHttp.outputs.functionUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output keyVaultName string = keyVault.outputs.keyVaultName
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint
output automationAccountName string = deployAutomationAccount ? automationAccount.outputs.automationAccountName : ''
output appInsightsName string = appInsights.outputs.appInsightsName
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey
output dceEndpoint string = dce.outputs.dceEndpoint
output dcrLoginInformationImmutableId string = dcrLoginInformation.outputs.dcrImmutableId
output dcrPasswordExpiryTriggerImmutableId string = dcrPasswordExpiryTrigger.outputs.dcrImmutableId
output apimGatewayUrl string = deployApim ? apim.outputs.apimGatewayUrl : ''
output timerFunctionName string = deployTimerFunction ? functionTimer.outputs.functionAppName : ''