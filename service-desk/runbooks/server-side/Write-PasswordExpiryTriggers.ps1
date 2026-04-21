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

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users

param(
    [int]$ThresholdDays = 10,
    [string]$StorageAccountName,
    [string]$TableName = "PasswordExpiry"
)

$ErrorActionPreference = "Stop"

if (-not $StorageAccountName) {
    throw "StorageAccountName parameter is required. Set it in the Automation Account job schedule."
}

# Autenticazione tramite Managed Identity
Connect-MgGraph -Identity -NoWelcome
Connect-AzAccount -Identity | Out-Null

# Accedi al Table Storage tramite OAuth (allowSharedKeyAccess=false)
$token = (Get-AzAccessToken -ResourceUrl "https://storage.azure.com/").Token
$tableUrl = "https://$StorageAccountName.table.core.windows.net/$TableName"
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = 'application/json'
    'Accept'        = 'application/json;odata=nometadata'
    'x-ms-version'  = '2020-12-06'
}

# Crea la tabella se non esiste
try {
    Invoke-RestMethod -Uri "https://$StorageAccountName.table.core.windows.net/Tables" `
        -Method POST -Headers $headers `
        -Body (@{ TableName = $TableName } | ConvertTo-Json) -ErrorAction Stop | Out-Null
    Write-Output "Table '$TableName' created"
} catch {
    if ($_.Exception.Message -notmatch "TableAlreadyExists") {
        Write-Output "Table '$TableName' already exists"
    }
}

# Pulisci vecchi record
Write-Output "Cleaning old records..."
try {
    $existing = Invoke-RestMethod -Uri "$tableUrl()" -Method GET -Headers $headers
    foreach ($entity in $existing.value) {
        $deleteUrl = "$tableUrl(PartitionKey='$($entity.PartitionKey)',RowKey='$($entity.RowKey)')"
        $deleteHeaders = $headers.Clone()
        $deleteHeaders['If-Match'] = '*'
        Invoke-RestMethod -Uri $deleteUrl -Method DELETE -Headers $deleteHeaders -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Output "Cleaned $($existing.value.Count) old records"
} catch {
    Write-Output "No existing records to clean"
}

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

    $entity = @{
        PartitionKey    = "PasswordExpiry"
        RowKey          = $user.UserPrincipalName.ToLower()
        DaysUntilExpiry = $daysUntilExpiry
        UserUPN         = $user.UserPrincipalName
        ExpiryDate      = $expiryDate.ToString("yyyy-MM-dd")
        WrittenAt       = $today.ToString("o")
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $tableUrl -Method POST -Headers $headers -Body $entity -ErrorAction Stop | Out-Null
    } catch {
        # Entity may already exist — update it
        $entityUrl = "$tableUrl(PartitionKey='PasswordExpiry',RowKey='$($user.UserPrincipalName.ToLower())')"
        $updateHeaders = $headers.Clone()
        $updateHeaders['If-Match'] = '*'
        Invoke-RestMethod -Uri $entityUrl -Method PUT -Headers $updateHeaders -Body $entity | Out-Null
    }

    $written++
}

Write-Output "Written $written records to table $TableName"
Disconnect-MgGraph