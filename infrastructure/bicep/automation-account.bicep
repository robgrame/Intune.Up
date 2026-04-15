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

// Daily schedule
resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: '${runbookName}-Daily'
  properties: {
    frequency: 'Day'
    interval: 1
    startTime: dateTimeAdd(baseTime, 'P1D') // starts tomorrow
    timeZone: 'UTC'
    description: 'Daily execution of password expiry trigger writer'
  }
}

// Link schedule to runbook
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbook.name, schedule.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: schedule.name
    }
  }
}

output automationAccountName string = automationAccount.name
output principalId string = automationAccount.identity.principalId
