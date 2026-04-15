// ============================================================
// Private Endpoints for all backend resources
// Only the HTTP Function remains internet-facing (mTLS).
// All other resources are accessible only via VNet.
// ============================================================

param location string
param tags object = {}
param privateEndpointSubnetId string
param privateDnsZoneIds object

// ---- Service Bus ----
param serviceBusId string
param serviceBusName string

resource peServiceBus 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${serviceBusName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${serviceBusName}'
        properties: {
          privateLinkServiceId: serviceBusId
          groupIds: ['namespace']
        }
      }
    ]
  }
}

resource peDnsServiceBus 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peServiceBus
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.serviceBus } }
    ]
  }
}

// ---- Key Vault ----
param keyVaultId string
param keyVaultName string

resource peKeyVault 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${keyVaultName}'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource peDnsKeyVault 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peKeyVault
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.keyVault } }
    ]
  }
}

// ---- App Configuration ----
param appConfigId string
param appConfigName string

resource peAppConfig 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${appConfigName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${appConfigName}'
        properties: {
          privateLinkServiceId: appConfigId
          groupIds: ['configurationStores']
        }
      }
    ]
  }
}

resource peDnsAppConfig 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peAppConfig
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.appConfig } }
    ]
  }
}

// ---- Storage Accounts (HTTP + SB Function storage) ----
param storageAccountHttpId string
param storageAccountHttpName string
param storageAccountSbId string
param storageAccountSbName string

resource peStorageHttpBlob 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storageAccountHttpName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountHttpName}-blob'
        properties: {
          privateLinkServiceId: storageAccountHttpId
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource peDnsStorageHttpBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peStorageHttpBlob
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.blob } }
    ]
  }
}

resource peStorageSbBlob 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storageAccountSbName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountSbName}-blob'
        properties: {
          privateLinkServiceId: storageAccountSbId
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource peDnsStorageSbBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peStorageSbBlob
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.blob } }
    ]
  }
}

resource peStorageSbTable 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storageAccountSbName}-table'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountSbName}-table'
        properties: {
          privateLinkServiceId: storageAccountSbId
          groupIds: ['table']
        }
      }
    ]
  }
}

resource peDnsStorageSbTable 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peStorageSbTable
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config', properties: { privateDnsZoneId: privateDnsZoneIds.table } }
    ]
  }
}
