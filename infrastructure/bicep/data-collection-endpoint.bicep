// ============================================================
// Data Collection Endpoint (DCE)
// Required by the Logs Ingestion API (replaces HTTP Data Collector API).
// The DCE provides the ingestion endpoint URL used by LogsIngestionClient.
// ============================================================

param name string
param location string
param tags object = {}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

output dceEndpoint string = dce.properties.logsIngestion.endpoint
output dceResourceId string = dce.id
