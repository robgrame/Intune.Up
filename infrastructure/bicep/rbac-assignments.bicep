// ============================================================
// RBAC Assignments - grants Function App MIs access to KV + App Config
// Deployed AFTER Function Apps, KV and App Config exist.
// ============================================================

param keyVaultName string
param appConfigName string
param principalIds array

// ---- Key Vault Secrets User ----
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

// ---- App Configuration Data Reader ----
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
