// ============================================================
// Azure Automation Account + Runbook for server-side jobs
// ============================================================

param name string
param location string
param tags object = {}

@description('Name of the password expiry runbook')
param runbookName string = 'Write-PasswordExpiryTriggers'

param baseTime string = utcNow()

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
}

// Runbook placeholder (code deployed separately via az automation runbook replace-content)
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Queries AD/Entra for users with expiring passwords and writes data to Azure Table Storage for client pull-based detection.'
    logProgress: true
    logVerbose: false
  }
}

// Daily schedule (link to runbook after publishing the runbook code separately)
// To publish: az automation runbook replace-content --resource-group rg-intuneup-dev \
//   --automation-account-name aa-intuneup-dev --name Write-PasswordExpiryTriggers \
//   --content @service-desk/runbooks/server-side/Write-PasswordExpiryTriggers.ps1
// Then: az automation runbook publish --resource-group rg-intuneup-dev \
//   --automation-account-name aa-intuneup-dev --name Write-PasswordExpiryTriggers

output automationAccountName string = automationAccount.name
output principalId string = automationAccount.identity.principalId
