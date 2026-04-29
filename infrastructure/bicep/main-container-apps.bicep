// ============================================================
// Intune.Up - Main Bicep deployment with Container Apps
// Deploys: Log Analytics, Service Bus, Key Vault, App Config,
//          Azure Container Apps (HTTP + SB processor), RBAC, Seed config
//
// Deploy order (handled by implicit dependencies):
//   1. Log Analytics, Service Bus, Key Vault, App Config
//   2. Container Registry
//   3. Container App Environment
//   4. Container Apps (get MI + KV URI)
//   5. RBAC assignments (MI -> KV + App Config + Service Bus)
//   6. Config seed (secrets -> KV, values -> App Config)
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

@description('Container image for HTTP collector (full registry path)')
param httpContainerImage string = ''

@description('Container image for Service Bus processor (full registry path)')
param sbContainerImage string = ''

@description('Comma-separated list of allowed issuer/CA certificate thumbprints')
@secure()
param allowedIssuerThumbprints string = ''

var tags = {
  project: 'IntuneUp'
  environment: environment
  managedBy: 'bicep'
}

// ---- Step 1: Core resources ----

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

// ---- Data Collection Rule – LoginInformation use case (sample) ----
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

// Supporting storage accounts (for claim-check, password-expiry)
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

// ---- Step 2: Container Apps Infrastructure ----

// Container Registry (for storing container images)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'cr${replace(baseName, '-', '')}${environment}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// Container App Environment (managed Kubernetes)
module caEnvironment 'container-app-env.bicep' = {
  name: 'ca-environment'
  params: {
    name: 'cae-${baseName}-${environment}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceResourceId
  }
}

// HTTP Collector Container App
module httpContainerApp 'container-app-http.bicep' = {
  name: 'ca-http'
  params: {
    name: 'ca-${baseName}-http-${environment}'
    location: location
    tags: tags
    environmentId: caEnvironment.outputs.environmentId
    image: httpContainerImage != '' ? httpContainerImage : 'mcr.microsoft.com/azuredocs/azure-cli:latest'
    keyVaultUri: keyVault.outputs.keyVaultUri
    appConfigEndpoint: appConfig.outputs.appConfigEndpoint
    serviceBusQueueName: serviceBus.outputs.queueName
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
  }
}

// Service Bus Processor Container App
module sbContainerApp 'container-app-sb.bicep' = {
  name: 'ca-sb'
  params: {
    name: 'ca-${baseName}-sb-${environment}'
    location: location
    tags: tags
    environmentId: caEnvironment.outputs.environmentId
    image: sbContainerImage != '' ? sbContainerImage : 'mcr.microsoft.com/azuredocs/azure-cli:latest'
    keyVaultUri: keyVault.outputs.keyVaultUri
    appConfigEndpoint: appConfig.outputs.appConfigEndpoint
    serviceBusQueueName: serviceBus.outputs.queueName
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
  }
}

// ---- Step 3: RBAC (Container App MIs -> KV + App Config + Service Bus + DCR) ----

module rbac 'rbac-assignments.bicep' = {
  name: 'rbac-assignments'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    appConfigName: appConfig.outputs.appConfigName
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    logAnalyticsWorkspaceName: 'law-${baseName}-${environment}'
    principalIds: [
      httpContainerApp.outputs.principalId
      sbContainerApp.outputs.principalId
    ]
    httpFunctionPrincipalId: httpContainerApp.outputs.principalId
    sbFunctionPrincipalId: sbContainerApp.outputs.principalId
    automationAccountPrincipalId: ''
    httpStorageAccountName: 'st${baseName}cc${environment}'
    dcrResourceId: dcrLoginInformation.outputs.dcrResourceId
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
  }
}

// ---- Outputs ----
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output httpContainerAppUrl string = httpContainerApp.outputs.containerAppUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output keyVaultName string = keyVault.outputs.keyVaultName
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint
output appInsightsName string = appInsights.outputs.appInsightsName
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output httpContainerAppPrincipalId string = httpContainerApp.outputs.principalId
output sbContainerAppPrincipalId string = sbContainerApp.outputs.principalId
output dceEndpoint string = dce.outputs.dceEndpoint
output dcrLoginInformationImmutableId string = dcrLoginInformation.outputs.dcrImmutableId
