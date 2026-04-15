// ============================================================
// Log Analytics Workspace
// ============================================================

param name string
param location string
param retentionDays int = 90
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.properties.customerId
output workspaceResourceId string = workspace.id
output primarySharedKey string = workspace.listKeys().primarySharedKey
