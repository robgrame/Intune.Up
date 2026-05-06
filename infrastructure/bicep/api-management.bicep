// ============================================================
// Azure API Management - Consumption tier
// Provides API gateway in front of the HTTP Function App:
//   - Rate limiting, CORS, subscription key validation
//   - Backend points to existing Function App
// ============================================================

param name string
param location string
param tags object = {}

@description('Publisher email for APIM')
param publisherEmail string = 'noreply@intune-up.local'

@description('Publisher name for APIM')
param publisherName string = 'IntuneUp'

@description('Backend Function App hostname (e.g. func-intuneup-http-dev.azurewebsites.net)')
param backendFunctionHostname string

@description('Function App resource ID for Managed Identity auth to backend')
param backendFunctionAppResourceId string = ''

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ---- Backend: HTTP Function App ----
resource backend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'func-http-backend'
  properties: {
    protocol: 'http'
    url: 'https://${backendFunctionHostname}/api'
    description: 'IntuneUp HTTP Collector Function'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// ---- API definition ----
resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'intuneup-collector'
  properties: {
    displayName: 'IntuneUp Collector'
    path: 'intuneup'
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'X-Api-Key'
      query: 'api-key'
    }
  }
}

// ---- Operation: POST /collect ----
resource collectOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: api
  name: 'post-collect'
  properties: {
    displayName: 'Collect Telemetry'
    method: 'POST'
    urlTemplate: '/collect'
    description: 'Receives device telemetry payload and routes to Service Bus'
  }
}

// ---- API-level policy: rate limit + backend routing + CORS ----
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins><origin>*</origin></allowed-origins>
      <allowed-methods><method>POST</method></allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
    </cors>
    <rate-limit calls="100" renewal-period="60" />
    <set-backend-service backend-id="func-http-backend" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>'''
  }
}

// ---- Outputs ----
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
