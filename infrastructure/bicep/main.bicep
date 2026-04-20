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

@description('Environment tag: dev, test, prod')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Log Analytics retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Comma-separated list of allowed issuer/CA certificate thumbprints (any cert signed by these CAs is accepted)')
@secure()
param allowedIssuerThumbprints string = ''

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

module automationAccount 'automation-account.bicep' = {
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
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
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
    clientCertEnabled: true
    extraAppSettings: [
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: 'InstrumentationKey=${appInsights.outputs.instrumentationKey}'
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
        // Required at runtime startup for SB trigger binding (before DI/AppConfig loads)
        name: 'IntuneUp__ServiceBus__Connection'
        value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/ServiceBusConnection)'
      }
      {
        // Required at runtime startup for SB trigger binding
        name: 'IntuneUp__ServiceBus__QueueName'
        value: serviceBus.outputs.queueName
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: 'InstrumentationKey=${appInsights.outputs.instrumentationKey}'
      }
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
    ]
  }
}

// ---- Step 3: RBAC (Function App MIs + Automation Account -> KV + App Config + Service Bus + Storage) ----

module rbac 'rbac-assignments.bicep' = {
  name: 'rbac-assignments'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    appConfigName: appConfig.outputs.appConfigName
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    logAnalyticsWorkspaceName: 'law-${baseName}-${environment}'
    principalIds: [
      functionHttp.outputs.principalId
      functionSb.outputs.principalId
      automationAccount.outputs.principalId
    ]
    httpFunctionPrincipalId: functionHttp.outputs.principalId
    sbFunctionPrincipalId: functionSb.outputs.principalId
    automationAccountPrincipalId: automationAccount.outputs.principalId
    httpStorageAccountName: 'st${baseName}http${environment}'
  }
}

// ---- Step 4: Seed secrets and config ----

module configSeed 'config-seed.bicep' = {
  name: 'config-seed'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    appConfigName: appConfig.outputs.appConfigName
    serviceBusConnectionString: serviceBus.outputs.connectionString
    logAnalyticsSharedKey: logAnalytics.outputs.primarySharedKey
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    serviceBusQueueName: serviceBus.outputs.queueName
    allowedIssuerThumbprints: allowedIssuerThumbprints
  }
}

// ---- Outputs ----
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output httpFunctionUrl string = functionHttp.outputs.functionUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output keyVaultName string = keyVault.outputs.keyVaultName
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint
output automationAccountName string = automationAccount.outputs.automationAccountName
output appInsightsName string = appInsights.outputs.appInsightsName
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey