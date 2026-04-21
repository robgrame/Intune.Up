<#
.SYNOPSIS
    Azure Automation Runbook: Populate Password Expiry Table
    Queries Entra ID (Microsoft Graph) for users with expiring passwords
    and writes records to Azure Table Storage.

.DESCRIPTION
    This runbook runs daily via Azure Automation.
    It queries Microsoft Graph for users whose passwords expire within
    the configured threshold (default: 14 days) and upserts records
    into the PasswordExpiry table in Azure Table Storage.

    The PasswordExpiryFunction (HTTP GET /api/password-expiry) reads from this table
    to let endpoint scripts check if a user's password is expiring.

.NOTES
    Requirements:
    - Azure Automation Account with System-Assigned Managed Identity
    - MI needs: Microsoft Graph "User.Read.All" app permission
    - MI needs: "Storage Table Data Contributor" on the storage account
    - Storage account with Table Storage enabled

.PARAMETER StorageAccountName
    Name of the Azure Storage Account containing the PasswordExpiry table.

.PARAMETER TableName
    Name of the table (default: PasswordExpiry).

.PARAMETER ExpiryThresholdDays
    Number of days before expiry to flag a user (default: 14).

.PARAMETER MaxPasswordAgeDays
    Maximum password age in days from your Entra ID policy (default: 90).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [string]$TableName = 'PasswordExpiry',

    [int]$ExpiryThresholdDays = 14,

    [int]$MaxPasswordAgeDays = 90
)

$ErrorActionPreference = 'Stop'

Write-Output "=========================================="
Write-Output " Password Expiry Runbook"
Write-Output " Storage: $StorageAccountName"
Write-Output " Table:   $TableName"
Write-Output " Threshold: $ExpiryThresholdDays days"
Write-Output " Max Password Age: $MaxPasswordAgeDays days"
Write-Output "=========================================="

# ---- Authenticate with Managed Identity ----
Write-Output "Authenticating with Managed Identity..."
Connect-AzAccount -Identity | Out-Null

# Get access token for Microsoft Graph
$graphToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

$headers = @{
    'Authorization' = "Bearer $graphToken"
    'Content-Type'  = 'application/json'
}

# ---- Query users from Microsoft Graph ----
Write-Output "Querying users from Microsoft Graph..."

# Get users with passwordLastSet, filtering for enabled accounts with passwords
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=userPrincipalName,displayName,lastPasswordChangeDateTime,accountEnabled&`$filter=accountEnabled eq true&`$top=999"

$allUsers = @()
$nextLink = $usersUrl

while ($nextLink) {
    $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method GET
    $allUsers += $response.value
    $nextLink = $response.'@odata.nextLink'
}

Write-Output "  Found $($allUsers.Count) enabled users"

# ---- Calculate expiring passwords ----
$today = Get-Date
$expiringUsers = @()

foreach ($user in $allUsers) {
    if (-not $user.lastPasswordChangeDateTime) { continue }

    $lastChange = [DateTime]::Parse($user.lastPasswordChangeDateTime)
    $expiryDate = $lastChange.AddDays($MaxPasswordAgeDays)
    $daysUntilExpiry = ($expiryDate - $today).Days

    if ($daysUntilExpiry -le $ExpiryThresholdDays -and $daysUntilExpiry -ge 0) {
        $expiringUsers += @{
            UPN              = $user.userPrincipalName
            DisplayName      = $user.displayName
            ExpiryDate       = $expiryDate.ToString('yyyy-MM-dd')
            DaysUntilExpiry  = $daysUntilExpiry
            LastPasswordChange = $lastChange.ToString('yyyy-MM-dd')
        }
    }
}

Write-Output "  $($expiringUsers.Count) users with passwords expiring within $ExpiryThresholdDays days"

# ---- Write to Azure Table Storage ----
Write-Output "Writing to Table Storage..."

$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -Protocol Https

# Ensure table exists
$table = Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $table) {
    Write-Output "  Creating table: $TableName"
    $table = New-AzStorageTable -Name $TableName -Context $storageContext
}

$cloudTable = $table.CloudTable

# Clear existing records (full refresh)
Write-Output "  Clearing existing records..."
$existingEntities = Get-AzTableRow -Table $cloudTable -PartitionKey "PasswordExpiry" -ErrorAction SilentlyContinue
if ($existingEntities) {
    $existingEntities | Remove-AzTableRow -Table $cloudTable | Out-Null
    Write-Output "  Removed $($existingEntities.Count) old records"
}

# Insert new records
$inserted = 0
foreach ($user in $expiringUsers) {
    $properties = @{
        DisplayName        = $user.DisplayName
        ExpiryDate         = $user.ExpiryDate
        DaysUntilExpiry    = $user.DaysUntilExpiry
        LastPasswordChange = $user.LastPasswordChange
        UpdatedAt          = (Get-Date -AsUTC -Format 'o')
    }

    Add-AzTableRow -Table $cloudTable `
        -PartitionKey "PasswordExpiry" `
        -RowKey $user.UPN.ToLower() `
        -Property $properties | Out-Null

    $inserted++
}

Write-Output "  Inserted $inserted records"

# ---- Summary ----
Write-Output ""
Write-Output "=========================================="
Write-Output " COMPLETED"
Write-Output " Users with expiring passwords: $($expiringUsers.Count)"
Write-Output "=========================================="

if ($expiringUsers.Count -gt 0) {
    Write-Output ""
    Write-Output "Expiring users:"
    $expiringUsers | ForEach-Object {
        Write-Output "  $($_.UPN) - $($_.DaysUntilExpiry) days ($($_.ExpiryDate))"
    }
}
