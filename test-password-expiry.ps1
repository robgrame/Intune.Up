<#
.SYNOPSIS
    Test script for the Password Expiry flow.
    Populates Table Storage with test data, then queries the password-expiry endpoint.

.PARAMETER ResourceGroup
    Azure resource group name.

.PARAMETER BaseName
    Base name used in deployment (e.g., iu001).

.PARAMETER Environment
    Deployment environment (e.g., test, prod).

.EXAMPLE
    .\test-password-expiry.ps1 -ResourceGroup rg-iu001-test -BaseName iu001 -Environment test
#>

param(
    [Parameter(Mandatory)]
    [string]$BaseName,

    [string]$Environment = 'test',

    [string]$SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'

# Force lowercase
$BaseName    = $BaseName.ToLower()
$Environment = $Environment.ToLower()

$ResourceGroup = "rg-$BaseName-$Environment"
$storageAccount = "st${BaseName}pe${Environment}"
$funcApp = "func-${BaseName}-http-${Environment}"
$tableName = 'PasswordExpiry'

# Subscription
$subParam = @()
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    $subParam = @('--subscription', $SubscriptionId)
}

$ScriptVersion = (Get-Content (Join-Path $PSScriptRoot 'VERSION') -ErrorAction SilentlyContinue).Trim()

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  🔑 TEST PASSWORD EXPIRY v$ScriptVersion" -ForegroundColor Cyan
Write-Host "  Storage: $storageAccount" -ForegroundColor Cyan
Write-Host "  Function: $funcApp" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan

# ---- STEP 1: Create table and insert test data ----
Write-Host ""
Write-Host "📋 STEP 1: Creating table and inserting test data..." -ForegroundColor Yellow

# Create table if not exists
az storage table create `
    --name $tableName `
    --account-name $storageAccount `
    --auth-mode login `
    -o none 2>$null

Write-Host "  ✅ Table '$tableName' ready" -ForegroundColor Green

# Insert test records
$testUsers = @(
    @{
        upn = "testuser.expiring@contoso.com"
        displayName = "Test User (Expiring)"
        expiryDate = (Get-Date).AddDays(5).ToString('yyyy-MM-dd')
        daysUntilExpiry = 5
    },
    @{
        upn = "testuser.soon@contoso.com"
        displayName = "Test User (Soon)"
        expiryDate = (Get-Date).AddDays(12).ToString('yyyy-MM-dd')
        daysUntilExpiry = 12
    }
)

foreach ($user in $testUsers) {
    # Use REST API with OAuth token (az storage entity insert may fail with allowSharedKeyAccess=false)
    $token = az account get-access-token --resource "https://storage.azure.com/" --query "accessToken" -o tsv
    $tableUrl = "https://$storageAccount.table.core.windows.net/$tableName"
    
    $entity = @{
        PartitionKey = "PasswordExpiry"
        RowKey = $user.upn
        DisplayName = $user.displayName
        ExpiryDate = $user.expiryDate
        DaysUntilExpiry = $user.daysUntilExpiry
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $tableUrl -Method POST `
            -Headers @{ 
                'Authorization' = "Bearer $token"
                'Content-Type' = 'application/json'
                'Accept' = 'application/json;odata=nometadata'
                'Prefer' = 'return-no-content'
            } `
            -Body $entity -ErrorAction Stop | Out-Null
        
        Write-Host "  ✅ Inserted: $($user.upn) (expires in $($user.daysUntilExpiry) days)" -ForegroundColor Green
    } catch {
        # May already exist — try merge/update
        $entityUrl = "$tableUrl(PartitionKey='PasswordExpiry',RowKey='$($user.upn)')"
        try {
            Invoke-RestMethod -Uri $entityUrl -Method PUT `
                -Headers @{ 
                    'Authorization' = "Bearer $token"
                    'Content-Type' = 'application/json'
                    'Accept' = 'application/json;odata=nometadata'
                    'If-Match' = '*'
                } `
                -Body $entity -ErrorAction Stop | Out-Null
            Write-Host "  ✅ Updated: $($user.upn) (expires in $($user.daysUntilExpiry) days)" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ Failed to insert $($user.upn): $_" -ForegroundColor Red
        }
    }
}

# ---- STEP 2: Get function key ----
Write-Host ""
Write-Host "🔑 STEP 2: Getting function key..." -ForegroundColor Yellow

$funcId = az functionapp show -g $ResourceGroup -n $funcApp @subParam --query "id" -o tsv
$keysJson = az rest --method post --uri "$funcId/host/default/listkeys?api-version=2022-03-01" -o json 2>&1
$keys = $keysJson | ConvertFrom-Json
$funcKey = $keys.functionKeys.default

if (-not $funcKey) {
    Write-Host "  ❌ Could not get function key" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ Function key obtained" -ForegroundColor Green

# ---- STEP 3: Test password-expiry endpoint ----
Write-Host ""
Write-Host "🧪 STEP 3: Testing password-expiry endpoint..." -ForegroundColor Yellow

$baseUrl = "https://$funcApp.azurewebsites.net/api/password-expiry"

# Test 1: User with expiring password
Write-Host ""
Write-Host "  Test A: User with expiring password" -ForegroundColor Cyan
$url = "$baseUrl`?upn=testuser.expiring@contoso.com&code=$funcKey"
$r = Invoke-WebRequest -Uri $url -Method GET -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "    Status: $($r.StatusCode)" -ForegroundColor $(if ($r.StatusCode -eq 200) {"Green"} else {"Red"})
Write-Host "    Response: $($r.Content)" -ForegroundColor Gray

# Test 2: User with password expiring soon
Write-Host ""
Write-Host "  Test B: User expiring soon" -ForegroundColor Cyan
$url = "$baseUrl`?upn=testuser.soon@contoso.com&code=$funcKey"
$r = Invoke-WebRequest -Uri $url -Method GET -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "    Status: $($r.StatusCode)" -ForegroundColor $(if ($r.StatusCode -eq 200) {"Green"} else {"Red"})
Write-Host "    Response: $($r.Content)" -ForegroundColor Gray

# Test 3: User NOT in the table (should return Expiring: false)
Write-Host ""
Write-Host "  Test C: User NOT expiring" -ForegroundColor Cyan
$url = "$baseUrl`?upn=healthy.user@contoso.com&code=$funcKey"
$r = Invoke-WebRequest -Uri $url -Method GET -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "    Status: $($r.StatusCode)" -ForegroundColor $(if ($r.StatusCode -eq 200) {"Green"} else {"Red"})
Write-Host "    Response: $($r.Content)" -ForegroundColor Gray

# Test 4: Missing UPN (should return 400)
Write-Host ""
Write-Host "  Test D: Missing UPN (expect 400)" -ForegroundColor Cyan
$url = "$baseUrl`?code=$funcKey"
$r = Invoke-WebRequest -Uri $url -Method GET -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "    Status: $($r.StatusCode)" -ForegroundColor $(if ($r.StatusCode -eq 400) {"Green"} else {"Red"})
Write-Host "    Response: $($r.Content)" -ForegroundColor Gray

# ---- STEP 4: Test password-change-webhook ----
Write-Host ""
Write-Host "🧪 STEP 4: Testing password-change-webhook..." -ForegroundColor Yellow

$webhookUrl = "https://$funcApp.azurewebsites.net/api/password-change-webhook?code=$funcKey"
$webhookPayload = @{ upn = "testuser.expiring@contoso.com" } | ConvertTo-Json

$r = Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body $webhookPayload -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "  Status: $($r.StatusCode)" -ForegroundColor $(if ($r.StatusCode -eq 200) {"Green"} else {"Red"})
Write-Host "  Response: $($r.Content)" -ForegroundColor Gray

# Verify the user was removed
Write-Host ""
Write-Host "  Verifying user was removed from table..." -ForegroundColor Cyan
$url = "$baseUrl`?upn=testuser.expiring@contoso.com&code=$funcKey"
$r = Invoke-WebRequest -Uri $url -Method GET -SkipHttpErrorCheck -TimeoutSec 30
Write-Host "    Response: $($r.Content)" -ForegroundColor Gray

$result = $r.Content | ConvertFrom-Json
if ($result.Expiring -eq $false) {
    Write-Host "    ✅ User correctly removed after password change!" -ForegroundColor Green
} else {
    Write-Host "    ❌ User still in table (expected Expiring=false)" -ForegroundColor Red
}

# ---- Summary ----
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ PASSWORD EXPIRY TEST COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
