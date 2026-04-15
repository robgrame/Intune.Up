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

@description('Comma-separated list of allowed client certificate thumbprints (configure before production use)')
@secure()
param allowedCertThumbprints string = ''

var tags = {
  project: 'IntuneUp'
  environment: environment
  managedBy: 'bicep'
}

// ---- Step 1: Core resources (no dependencies between them) ----

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

// ---- Step 2: Function Apps (depend on KV for URI in app settings) ----

module functionHttp 'function-app.bicep' = {
  name: 'function-http'
  params: {
    name: 'func-${baseName}-http-${environment}'
    storageAccountName: 'st${baseName}http${environment}'
    location: location
    tags: tags
    keyVaultUri: keyVault.outputs.keyVaultUri
    extraAppSettings: [
      {
        name: 'ALLOWED_CERT_THUMBPRINTS'
        value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/AllowedCertThumbprints)'
      }
      {
        name: 'SERVICEBUS_CONNECTION'
        value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/ServiceBusConnection)'
      }
      {
        name: 'SERVICEBUS_QUEUE_NAME'
        value: serviceBus.outputs.queueName
      }
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
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
        name: 'LOG_ANALYTICS_WORKSPACE_ID'
        value: logAnalytics.outputs.workspaceId
      }
      {
        name: 'LOG_ANALYTICS_SHARED_KEY'
        value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/LogAnalyticsSharedKey)'
      }
      {
        name: 'LOG_TABLE_PREFIX'
        value: 'IntuneUp'
      }
      {
        name: 'SERVICEBUS_CONNECTION'
        value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/ServiceBusConnection)'
      }
      {
        name: 'SERVICEBUS_QUEUE_NAME'
        value: serviceBus.outputs.queueName
      }
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appConfig.outputs.appConfigEndpoint
      }
    ]
  }
}

// ---- Step 3: RBAC (Function App MIs -> KV + App Config + Service Bus) ----

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
    ]
    httpFunctionPrincipalId: functionHttp.outputs.principalId
    sbFunctionPrincipalId: functionSb.outputs.principalId
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
    allowedCertThumbprints: allowedCertThumbprints
  }
}

// ---- Outputs ----
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output httpFunctionUrl string = functionHttp.outputs.functionUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output keyVaultName string = keyVault.outputs.keyVaultName
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint