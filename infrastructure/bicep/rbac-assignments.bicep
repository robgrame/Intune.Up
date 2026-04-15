// ============================================================
// RBAC Assignments - grants MIs access to KV, App Config, Service Bus, Storage
// Deployed AFTER Function Apps, Automation Account, KV, App Config and Service Bus exist.
// ============================================================

param keyVaultName string
param appConfigName string
param serviceBusNamespaceName string
param principalIds array
param httpFunctionPrincipalId string
param sbFunctionPrincipalId string
param automationAccountPrincipalId string = ''
param httpStorageAccountName string = ''

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

// ---- Log Analytics Contributor (SB Function writes telemetry data) ----
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'

param logAnalyticsWorkspaceName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource laContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalytics.id, sbFunctionPrincipalId, logAnalyticsContributorRoleId)
  scope: logAnalytics
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsContributorRoleId)
    principalId: sbFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Storage Table Data Contributor (Automation Account writes password expiry data) ----
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource httpStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(httpStorageAccountName)) {
  name: httpStorageAccountName
}

resource tableContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(automationAccountPrincipalId) && !empty(httpStorageAccountName)) {
  name: guid(httpStorage.id, automationAccountPrincipalId, storageTableDataContributorRoleId)
  scope: httpStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
  }
}
