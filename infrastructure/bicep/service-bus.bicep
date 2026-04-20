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
    disableLocalAuth: true          // Enforce Managed Identity only (no shared keys)
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

output namespaceName string = namespace.name
output namespaceId string = namespace.id
output queueName string = queue.name
