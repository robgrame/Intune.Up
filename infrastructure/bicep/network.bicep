// ============================================================
// Virtual Network + Subnets for IntuneUp
// - Function App VNet Integration subnet
// - Private Endpoints subnet
// ============================================================

param name string
param location string
param tags object = {}

param addressPrefix string = '192.168.0.0/24'
param functionSubnetPrefix string = '192.168.0.0/27'
param privateEndpointSubnetPrefix string = '192.168.0.32/27'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: 'snet-functions'
        properties: {
          addressPrefix: functionSubnetPrefix
          delegations: [
            {
              name: 'delegation-functions'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
        }
      }
    ]
  }
}

resource privateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource privateDnsZoneTable 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.table.${az.environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource privateDnsZoneServiceBus 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.servicebus.windows.net'
  location: 'global'
  tags: tags
}

resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource privateDnsZoneAppConfig 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azconfig.io'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLogAnalytics 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
  tags: tags
}

// Link DNS zones to VNet
resource linkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneBlob
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource linkTable 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneTable
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource linkServiceBus 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneServiceBus
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource linkKeyVault 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneKeyVault
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource linkAppConfig 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneAppConfig
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource linkLogAnalytics 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneLogAnalytics
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output functionSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output privateDnsZoneIds object = {
  blob: privateDnsZoneBlob.id
  table: privateDnsZoneTable.id
  serviceBus: privateDnsZoneServiceBus.id
  keyVault: privateDnsZoneKeyVault.id
  appConfig: privateDnsZoneAppConfig.id
  logAnalytics: privateDnsZoneLogAnalytics.id
}
