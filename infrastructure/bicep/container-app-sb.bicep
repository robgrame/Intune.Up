// ============================================================
// Azure Container App - Service Bus Processor Function
// Serverless compute for message processing
// ============================================================

param name string
param location string
param tags object = {}
param environmentId string
param image string
@secure()
param keyVaultUri string
param appConfigEndpoint string
param serviceBusQueueName string
param appInsightsInstrumentationKey string

// System-assigned Managed Identity for RBAC
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      ingress: {
        external: false
        targetPort: 7071
      }
      registries: []
    }
    template: {
      serviceBinds: []
      containers: [
        {
          image: image
          name: 'sb-processor'
          env: [
            {
              name: 'APPCONFIG_ENDPOINT'
              value: appConfigEndpoint
            }
            {
              name: 'KeyVaultUri'
              value: keyVaultUri
            }
            {
              name: 'IntuneUp__ServiceBus__QueueName'
              value: serviceBusQueueName
            }
            {
              name: 'APPLICATIONINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsightsInstrumentationKey
            }
          ]
          resources: {
            cpu: '0.25'
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
      }
    }
  }
}

// Output
output principalId string = containerApp.identity.principalId
