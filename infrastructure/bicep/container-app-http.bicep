// ============================================================
// Azure Container App - HTTP Collector Function
// Serverless compute for device telemetry collection
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
        external: true
        targetPort: 7071
        transport: 'http'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: []
    }
    template: {
      serviceBinds: []
      containers: [
        {
          image: image
          name: 'http-collector'
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
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:7071'
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
        maxReplicas: 10
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Output
output principalId string = containerApp.identity.principalId
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
