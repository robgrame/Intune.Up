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
param logAnalyticsWorkspaceName string

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
// ---- Service Bus Data Owner (full control for identity-based connections) ----
var sbDataOwnerRoleId = '090c5cfd-751d-490a-894a-3ce6f1109419'

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

resource sbOwnerRoleHttp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, httpFunctionPrincipalId, sbDataOwnerRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataOwnerRoleId)
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

resource sbOwnerRoleSb 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, sbFunctionPrincipalId, sbDataOwnerRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataOwnerRoleId)
    principalId: sbFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Log Analytics Contributor (SB Function – workspace-level operations) ----
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'

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

// ---- Monitoring Metrics Publisher on DCR (SB Function writes via Logs Ingestion API) ----
// Required for the Logs Ingestion API (DCE + DCR), replacing the deprecated HTTP Data Collector API.
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

param dcrResourceId string = ''

resource dcrMetricsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dcrResourceId)) {
  name: guid(dcrResourceId, sbFunctionPrincipalId, monitoringMetricsPublisherRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: sbFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Storage Table Data Contributor (Automation Account writes password expiry data) ----
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

param passwordExpiryStorageAccountName string = ''

resource pwdExpiryStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(passwordExpiryStorageAccountName)) {
  name: passwordExpiryStorageAccountName
}

// Automation Account → Table Storage (writes expiry records)
resource tableContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(automationAccountPrincipalId) && !empty(passwordExpiryStorageAccountName)) {
  name: guid(pwdExpiryStorage.id, automationAccountPrincipalId, storageTableDataContributorRoleId)
  scope: pwdExpiryStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// HTTP Function → Table Storage (reads/deletes expiry records for password-expiry and webhook endpoints)
resource httpFuncTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(passwordExpiryStorageAccountName)) {
  name: guid(pwdExpiryStorage.id, httpFunctionPrincipalId, storageTableDataContributorRoleId)
  scope: pwdExpiryStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: httpFunctionPrincipalId
    principalType: 'ServicePrincipal'
  }
}
