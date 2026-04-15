// ============================================================
// Azure Service Bus – Namespace + Queue
// ============================================================

param namespaceName string
param queueName string = 'device-telemetry'
param location string
param tags object = {}

resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: queueName
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P1D'     // 1 day TTL
    lockDuration: 'PT5M'
    enablePartitioning: false
  }
}

// Shared Access Policy con Send + Listen per le Functions
resource authRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: namespace
  name: 'IntuneUpFunctions'
  properties: {
    rights: ['Send', 'Listen']
  }
}

output namespaceName string = namespace.name
output namespaceId string = namespace.id
output queueName string = queue.name

#disable-next-line outputs-should-not-contain-secrets
output connectionString string = authRule.listKeys().primaryConnectionString
