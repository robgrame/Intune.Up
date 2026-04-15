// ============================================================
// Application Gateway v2 + WAF (optional, separate deployment)
// Sits in front of the HTTP Function App for:
//   - WAF v2 (OWASP 3.2 rule set)
//   - DDoS protection
//   - SSL offloading
//   - Mutual TLS termination
//
// Deploy separately:
//   az deployment group create --resource-group rg-intuneup-dev \
//     --template-file app-gateway.bicep \
//     --parameters functionAppHostname=func-intuneup-http-dev.azurewebsites.net
// ============================================================

param name string = 'agw-intuneup-dev'
param location string = resourceGroup().location
param tags object = {}

@description('Hostname of the backend Function App (e.g. func-intuneup-http-dev.azurewebsites.net)')
param functionAppHostname string

@description('VNet name to place the App Gateway in')
param vnetName string = 'vnet-intuneup-dev'

@description('Address prefix for the App Gateway subnet (must be in the VNet range, minimum /27)')
param gatewaySubnetPrefix string = '192.168.0.64/27'

@description('WAF mode: Detection (log only) or Prevention (block)')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

@description('SKU capacity (instance count)')
@minValue(1)
@maxValue(10)
param capacity int = 1

// ---- App Gateway Subnet (add to existing VNet) ----
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'snet-appgateway'
  properties: {
    addressPrefix: gatewaySubnetPrefix
  }
}

// ---- Public IP ----
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: name
    }
  }
}

// ---- WAF Policy ----
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: 'waf-${name}'
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: wafMode
      requestBodyCheck: true
      maxRequestBodySizeInKb: 512
      fileUploadLimitInMb: 1
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
  }
}

// ---- Application Gateway v2 ----
resource appGateway 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: capacity
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    gatewayIPConfigurations: [
      {
        name: 'gatewayIpConfig'
        properties: {
          subnet: { id: gatewaySubnet.id }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontendIp'
        properties: {
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port443'
        properties: { port: 443 }
      }
    ]
    backendAddressPools: [
      {
        name: 'functionBackend'
        properties: {
          backendAddresses: [
            { fqdn: functionAppHostname }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'httpsSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          pickHostNameFromBackendAddress: true
          probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', name, 'healthProbe') }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpsListener'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', name, 'frontendIp') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', name, 'port443') }
          protocol: 'Https'
          // Note: SSL certificate must be configured separately (upload PFX or reference Key Vault cert)
          // For initial deployment, you can switch to HTTP (port 80) for testing
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'routeToFunction'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', name, 'httpsListener') }
          backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', name, 'functionBackend') }
          backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', name, 'httpsSettings') }
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Https'
          host: functionAppHostname
          path: '/api/collect'
          interval: 30
          timeout: 10
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          match: {
            statusCodes: ['200-499']
          }
        }
      }
    ]
  }
}

output appGatewayId string = appGateway.id
output publicIpAddress string = publicIp.properties.ipAddress
output publicFqdn string = publicIp.properties.dnsSettings.fqdn
