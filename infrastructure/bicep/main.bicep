// ============================================================
// Intune.Up – Main Bicep deployment
// Deploys: Log Analytics Workspace, Service Bus, Azure Functions
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

@description('Comma-separated list of allowed client certificate thumbprints')
@secure()
param allowedCertThumbprints string

var tags = {
  project: 'IntuneUp'
  environment: environment
  managedBy: 'bicep'
}

// Log Analytics Workspace
module logAnalytics 'log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: 'law-${baseName}-${environment}'
    location: location
    retentionDays: logRetentionDays
    tags: tags
  }
}

// Service Bus
module serviceBus 'service-bus.bicep' = {
  name: 'service-bus'
  params: {
    namespaceName: 'sb-${baseName}-${environment}'
    queueName: 'device-telemetry'
    location: location
    tags: tags
  }
}

// Azure Function – HTTP trigger (entry point)
module functionHttp 'function-app.bicep' = {
  name: 'function-http'
  params: {
    name: 'func-${baseName}-http-${environment}'
    location: location
    tags: tags
    serviceBusConnectionString: serviceBus.outputs.connectionString
    queueName: serviceBus.outputs.queueName
    appSettings: {
      ALLOWED_CERT_THUMBPRINTS: allowedCertThumbprints
      SERVICEBUS_QUEUE_NAME: serviceBus.outputs.queueName
    }
  }
}

// Azure Function – Service Bus trigger (processor)
module functionSb 'function-app.bicep' = {
  name: 'function-sb'
  params: {
    name: 'func-${baseName}-sb-${environment}'
    location: location
    tags: tags
    serviceBusConnectionString: serviceBus.outputs.connectionString
    queueName: serviceBus.outputs.queueName
    appSettings: {
      LOG_ANALYTICS_WORKSPACE_ID: logAnalytics.outputs.workspaceId
      LOG_ANALYTICS_SHARED_KEY: logAnalytics.outputs.primarySharedKey
      LOG_TABLE_PREFIX: 'IntuneUp'
      SERVICEBUS_QUEUE_NAME: serviceBus.outputs.queueName
    }
  }
}

// Outputs
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output httpFunctionUrl string = functionHttp.outputs.functionUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
