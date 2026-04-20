// ============================================================
// Azure Container Apps Environment
// Provides the managed Kubernetes environment for containers
// ============================================================

param name string
param location string
param tags object = {}
param logAnalyticsWorkspaceId string

// Container App Environment
resource caEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
  }
}

// Outputs
output environmentId string = caEnvironment.id
output environmentName string = caEnvironment.name
