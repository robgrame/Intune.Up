// ============================================================
// Application Insights for telemetry and diagnostics
// ============================================================

param name string
param location string
param workspaceId string
param tags object

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: workspaceId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
