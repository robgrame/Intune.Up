#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Basic test client for Intune.Up HTTP function (without mTLS requirement)
    
.DESCRIPTION
    Tests the HTTP function endpoint with just the function key.
    Useful for initial validation before mTLS certificate setup.
    
.EXAMPLE
    .\test-client-basic.ps1 -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_ -match '^https?://' })]
    [string]$FunctionUrl,
    
    [string]$ResourceGroup = "rg-intuneup-prod",
    [string]$FunctionAppName = "func-intuneup-http-prod",
    [string]$DeviceId = "DEVICE-$(Get-Random -Minimum 1000 -Maximum 9999)",
    [string]$DeviceName = "TEST-PC-$(Get-Random -Minimum 100 -Maximum 999)",
    [string]$UseCase = "DeviceInventory",
    [int]$PayloadSizeKB = 50
)

function Get-FunctionKey {
    param([string]$ResourceGroup, [string]$FunctionAppName)
    
    try {
        Write-Host "🔑 Retrieving function key from Azure..."
        $key = az functionapp keys list `
            -g $ResourceGroup `
            -n $FunctionAppName `
            --query "functionKeys.default" -o tsv
        
        if ($key -and $key -ne "") {
            Write-Host "✅ Function key retrieved"
            return $key
        }
        else {
            Write-Host "⚠️  Function key is empty"
            return $null
        }
    }
    catch {
        Write-Host "⚠️  Could not retrieve function key: $_"
        return $null
    }
}

function New-TestPayload {
    param(
        [string]$DeviceId,
        [string]$DeviceName,
        [string]$UseCase,
        [int]$SizeKB
    )
    
    # Create realistic inventory payload
    $payload = @{
        DeviceId   = $DeviceId
        DeviceName = $DeviceName
        UseCase    = $UseCase
        Timestamp  = [DateTime]::UtcNow.ToString("o")
        Data       = @{
            OS = @{
                Name     = "Windows 11"
                Build    = "22621"
                Edition  = "Enterprise"
                Version  = "23H2"
            }
            Hardware = @{
                ProcessorCount = 8
                ProcessorName  = "Intel Core i7-11700K"
                TotalMemoryGB  = 16
                MaxMemoryGB    = 16
                Architecture   = "x64"
            }
            Network = @{
                DNSSuffix    = "contoso.corp"
                DHCPEnabled  = $true
                DNSServers   = @("10.0.0.10", "10.0.0.11")
                IPAddresses  = @("192.168.1.100")
            }
            InstalledApps = @(
                @{ Name = "Microsoft Edge"; Version = "124.0.2478.67" }
                @{ Name = "Visual Studio Code"; Version = "1.88.1" }
                @{ Name = "Git"; Version = "2.44.0" }
            )
            Security = @{
                AntivirusProduct = "Windows Defender"
                AntivirusEnabled = $true
                DefenderVersion = "1.395.0"
                FirewallEnabled  = $true
            }
            Updates = @{
                LastUpdateCheck = (Get-Date).AddHours(-2)
                PendingUpdates   = 3
                FailedUpdates    = 0
            }
        }
    }
    
    # Convert to JSON
    $json = $payload | ConvertTo-Json -Depth 10
    
    # Pad to desired size
    $currentSizeKB = ($json | Measure-Object -Character).Characters / 1024
    if ($currentSizeKB -lt $SizeKB) {
        $padSizeBytes = [int](($SizeKB - $currentSizeKB) * 1024)
        $padding = -join ((0..9) | ForEach-Object { "X" * 100 })
        $padding = $padding.PadRight($padSizeBytes, "X")
        $payload.Padding = $padding
        $json = $payload | ConvertTo-Json -Depth 10
    }
    
    return $json
}

function Test-Connection {
    param([string]$Url)
    
    Write-Host "🔗 Testing connection to function..."
    try {
        # Skip certificate validation for this test (basic connectivity only)
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        
        $response = Invoke-WebRequest `
            -Uri $Url `
            -Method Head `
            -TimeoutSec 10 `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue
        
        Write-Host "✅ Connection successful (HTTP $($response.StatusCode))"
        return $true
    }
    catch {
        Write-Host "⚠️  Connection test failed: $($_.Exception.Message)"
        return $false
    }
}

function Send-Payload {
    param(
        [string]$Url,
        [string]$Payload,
        [string]$FunctionKey
    )
    
    Write-Host "📤 Sending telemetry payload..."
    
    $payloadBytes = [System.Text.Encoding]::UTF8.GetByteCount($Payload)
    Write-Host "   Payload size: $payloadBytes bytes ($([math]::Round($payloadBytes / 1024, 2)) KB)"
    
    try {
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        # Add function key if available
        if ($FunctionKey) {
            $headers["x-functions-key"] = $FunctionKey
            Write-Host "   Using x-functions-key header"
        }
        else {
            Write-Host "   ⚠️  No function key available"
        }
        
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        
        $response = Invoke-WebRequest `
            -Uri $Url `
            -Method Post `
            -Headers $headers `
            -Body $Payload `
            -ContentType "application/json" `
            -TimeoutSec 30 `
            -SkipCertificateCheck `
            -ErrorAction Stop
        
        Write-Host "✅ Payload accepted (HTTP $($response.StatusCode))"
        
        if ($response.Content) {
            Write-Host "   Response: $($response.Content)"
        }
        
        return $true
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        $errorMsg = $_.Exception.Response.StatusDescription
        
        Write-Host "❌ Request failed: HTTP $statusCode - $errorMsg"
        
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
            if ($body) {
                Write-Host "   Error body: $body"
            }
        }
        catch { }
        
        return $false
    }
}

# Main execution
Write-Host ""
Write-Host "============================================================"
Write-Host " Intune.Up - Basic Test Client (No mTLS)"
Write-Host "============================================================"
Write-Host ""

Write-Host "📍 Configuration:"
Write-Host "   Function URL   : $FunctionUrl"
Write-Host "   Device ID      : $DeviceId"
Write-Host "   Device Name    : $DeviceName"
Write-Host "   Use Case       : $UseCase"
Write-Host "   Payload Size   : ~$PayloadSizeKB KB"
Write-Host ""

# Get function key
$functionKey = Get-FunctionKey -ResourceGroup $ResourceGroup -FunctionAppName $FunctionAppName
Write-Host ""

# Test connection
Test-Connection -Url $FunctionUrl
Write-Host ""

# Create payload
Write-Host "📋 Generating payload..."
$payload = New-TestPayload `
    -DeviceId $DeviceId `
    -DeviceName $DeviceName `
    -UseCase $UseCase `
    -SizeKB $PayloadSizeKB
Write-Host "✅ Payload generated"
Write-Host ""

# Send payload
$success = Send-Payload -Url $FunctionUrl -Payload $payload -FunctionKey $functionKey
Write-Host ""

if ($success) {
    Write-Host "✅ Test completed successfully!"
    Write-Host ""
    Write-Host "📊 Summary:"
    Write-Host "   Device ID      : $DeviceId"
    Write-Host "   Message Status : Accepted (202)"
    Write-Host ""
    Write-Host "💡 Next steps:"
    Write-Host "   1. Check function logs in App Insights"
    Write-Host "   2. Verify message in Service Bus queue"
    Write-Host "   3. Add mTLS certificate to AllowedIssuerThumbprints"
    Write-Host ""
    exit 0
}
else {
    Write-Host "❌ Test failed!"
    Write-Host ""
    Write-Host "💡 Troubleshooting:"
    Write-Host "   1. Verify function URL is correct"
    Write-Host "   2. Check that function is running"
    Write-Host "   3. If 401: function requires mTLS certificate"
    Write-Host "      - Admin: add cert thumbprint to Key Vault"
    Write-Host "      - Use: .\test-client.ps1 (with mTLS)"
    Write-Host ""
    exit 1
}
