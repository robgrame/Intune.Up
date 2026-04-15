// ============================================================
// RBAC Assignments - grants Function App MIs access to KV, App Config, Service Bus
// Deployed AFTER Function Apps, KV, App Config and Service Bus exist.
// ============================================================

param keyVaultName string
param appConfigName string
param serviceBusNamespaceName string
param principalIds array
param httpFunctionPrincipalId string
param sbFunctionPrincipalId string

// ---- Key Vault Secrets User (both Functions) ----
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in principalIds: {
    name: guid(kv.id, principalId, kvSecretsUserRoleId)
    scope: kv
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

// ---- App Configuration Data Reader (both Functions) ----
var appConfigDataReaderRoleId = '516239f1-63e1-4d78-a4de-a74fb236a071'

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' existing = {
  name: appConfigName
}

resource appConfigRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in principalIds: {
    name: guid(appConfig.id, principalId, appConfigDataReaderRoleId)
    scope: appConfig
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigDataReaderRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

// ---- Service Bus Data Sender (HTTP Function sends messages) ----
var sbDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource sbSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, httpFunctionPrincipalId, sbDataSenderRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataSenderRoleId)
    principalId: httpFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Service Bus Data Receiver (SB Function consumes messages) ----
var sbDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource sbReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, sbFunctionPrincipalId, sbDataReceiverRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataReceiverRoleId)
    principalId: sbFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}
