#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Admin script to authorize certificate thumbprint for Intune.Up HTTP function
    
.DESCRIPTION
    Adds a certificate thumbprint to AllowedIssuerThumbprints in Key Vault.
    Required to enable mTLS on the HTTP function.
    
.PARAMETER KeyVaultName
    Name of the Key Vault (e.g., kv-intuneup-prod)
    
.PARAMETER Thumbprint
    Certificate thumbprint to authorize (uppercase hex)
    
.EXAMPLE
    .\authorize-certificate.ps1 -KeyVaultName "kv-intuneup-prod" -Thumbprint "4E050ADBD50A4132C1CC2B237929E113431993D2"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-F0-9]{40}$')]
    [string]$Thumbprint
)

function Get-AllowedThumbprints {
    param([string]$KeyVaultName)
    
    try {
        $secret = az keyvault secret show `
            --vault-name $KeyVaultName `
            --name AllowedIssuerThumbprints `
            --query "value" -o tsv
        
        if ($secret) {
            return $secret
        }
        else {
            return ""
        }
    }
    catch {
        Write-Host "⚠️  Could not read current thumbprints: $_"
        return ""
    }
}

function Add-ThumbprintToKeyVault {
    param(
        [string]$KeyVaultName,
        [string]$Thumbprint,
        [string]$CurrentValue
    )
    
    # Parse current thumbprints
    $existing = @()
    if ($CurrentValue) {
        $existing = $CurrentValue -split ',' | ForEach-Object { $_.Trim() }
    }
    
    # Check if already exists
    if ($Thumbprint -in $existing) {
        Write-Host "ℹ️  Thumbprint already authorized"
        return $true
    }
    
    # Add new thumbprint
    $existing += $Thumbprint
    $newValue = ($existing | ForEach-Object { $_.Trim() } | Sort-Object -Unique) -join ','
    
    Write-Host "🔐 Updating Key Vault secret..."
    Write-Host "   Current thumbprints: $($existing.Count)"
    Write-Host "   Adding: $Thumbprint"
    
    try {
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name AllowedIssuerThumbprints `
            --value $newValue | Out-Null
        
        Write-Host "✅ Secret updated successfully"
        return $true
    }
    catch {
        Write-Host "❌ Failed to update secret: $_"
        return $false
    }
}

# Main
Write-Host ""
Write-Host "============================================================"
Write-Host " Authorize Certificate for Intune.Up HTTP Function"
Write-Host "============================================================"
Write-Host ""

Write-Host "📍 Configuration:"
Write-Host "   Key Vault    : $KeyVaultName"
Write-Host "   Thumbprint   : $Thumbprint"
Write-Host ""

# Get current value
Write-Host "📖 Reading current authorized thumbprints..."
$current = Get-AllowedThumbprints -KeyVaultName $KeyVaultName

if ($current) {
    $thumbprints = $current -split ','
    Write-Host "✅ Found $($thumbprints.Count) authorized thumbprints:"
    $thumbprints | ForEach-Object { Write-Host "   - $_" }
}
else {
    Write-Host "ℹ️  No thumbprints currently configured"
}
Write-Host ""

# Add new thumbprint
$success = Add-ThumbprintToKeyVault `
    -KeyVaultName $KeyVaultName `
    -Thumbprint $Thumbprint `
    -CurrentValue $current

Write-Host ""

if ($success) {
    Write-Host "✅ Certificate authorized!"
    Write-Host ""
    Write-Host "📋 Next steps:"
    Write-Host "   1. Function automatically picks up the updated secret"
    Write-Host "   2. Test with: .\test-client.ps1"
    Write-Host "   3. Expected response: HTTP 202 Accepted"
    Write-Host ""
    exit 0
}
else {
    Write-Host "❌ Failed to authorize certificate"
    exit 1
}
