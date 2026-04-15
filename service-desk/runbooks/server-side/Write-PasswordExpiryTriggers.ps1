<#
.SYNOPSIS
    Azure Automation Runbook - Password Expiry Data Writer
.DESCRIPTION
    Runbook lato server (Azure Automation) che:
    1. Interroga Active Directory o Microsoft Graph per trovare utenti
       con password in scadenza entro ThresholdDays giorni.
    2. Scrive i dati in una Azure Table Storage, consultabile dai client
       tramite la Azure Function HTTP (pattern pull-based).

    I client Intune (detect.ps1) interrogano periodicamente l'endpoint
    per verificare se il proprio UPN ha un record di scadenza.

    Scheduling: giornaliero (Azure Automation Schedule)
    Prerequisiti:
      - Azure Automation Account con Managed Identity
      - Azure Table Storage (creata dal Bicep)
      - Moduli: Az.Storage, Microsoft.Graph.Authentication, Microsoft.Graph.Users
#>

#Requires -Modules Az.Storage, Microsoft.Graph.Authentication, Microsoft.Graph.Users

param(
    [int]$ThresholdDays = 10,
    [string]$StorageAccountName = "stintuneupsbdev",
    [string]$TableName = "PasswordExpiry"
)

$ErrorActionPreference = "Stop"

# Autenticazione tramite Managed Identity
Connect-MgGraph -Identity -NoWelcome
Connect-AzAccount -Identity | Out-Null

# Crea la tabella se non esiste
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-intuneup-dev" -Name $StorageAccountName).Context
$table = Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction SilentlyContinue
if (-not $table) {
    $table = New-AzStorageTable -Name $TableName -Context $ctx
}
$cloudTable = $table.CloudTable

# Pulisci vecchi record (quelli scritti >2 giorni fa)
$oldEntities = Get-AzTableRow -Table $cloudTable -PartitionKey "PasswordExpiry"
foreach ($entity in $oldEntities) {
    Remove-AzTableRow -Table $cloudTable -PartitionKey $entity.PartitionKey -RowKey $entity.RowKey -Confirm:$false | Out-Null
}
Write-Output "Cleaned $($oldEntities.Count) old records"

# Query utenti con password in scadenza
$today      = (Get-Date).ToUniversalTime()
$targetDate = $today.AddDays($ThresholdDays)

Write-Output "Querying users with password expiry before $($targetDate.ToString('yyyy-MM-dd'))"

$users = Get-MgUser -All `
    -Property "id,userPrincipalName,lastPasswordChangeDateTime" `
    -Filter "accountEnabled eq true" |
    Where-Object {
        if (-not $_.LastPasswordChangeDateTime) { return $false }
        # Calcola scadenza assumendo policy di 90 giorni (adattare al vostro ambiente)
        $passwordMaxAgeDays = 90  # TODO: leggere dalla policy reale
        $expiryDate = $_.LastPasswordChangeDateTime.AddDays($passwordMaxAgeDays)
        return $expiryDate -le $targetDate -and $expiryDate -gt $today
    }

Write-Output "Found $($users.Count) users with expiring passwords"

$written = 0
foreach ($user in $users) {
    $passwordMaxAgeDays = 90  # TODO: leggere dalla policy reale
    $expiryDate = $user.LastPasswordChangeDateTime.AddDays($passwordMaxAgeDays)
    $daysUntilExpiry = [math]::Round(($expiryDate - $today).TotalDays, 0)

    $props = @{
        DaysUntilExpiry = $daysUntilExpiry
        UserUPN         = $user.UserPrincipalName
        ExpiryDate      = $expiryDate.ToString("o")
        WrittenAt       = $today.ToString("o")
    }

    Add-AzTableRow -Table $cloudTable `
        -PartitionKey "PasswordExpiry" `
        -RowKey $user.UserPrincipalName.ToLower() `
        -Property $props | Out-Null

    $written++
}

Write-Output "Written $written records to table $TableName"
Disconnect-MgGraph