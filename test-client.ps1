# ============================================================
# Intune.Up - Test Client Simulator
# Simulates a device sending inventory report to the HTTP function
# with mutual TLS (client certificate validation)
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$FunctionUrl,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory = $false)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$DeviceId = "DEVICE-$(Get-Random -Minimum 1000 -Maximum 9999)",
    
    [Parameter(Mandatory = $false)]
    [string]$DeviceName = "TEST-PC-$(Get-Random -Minimum 100 -Maximum 999)",
    
    [Parameter(Mandatory = $false)]
    [string]$UseCase = "DeviceInventory",
    
    [Parameter(Mandatory = $false)]
    [int]$PayloadSizeKB = 50,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipCertSetup = $false
)

# ============================================================
# Helper Functions
# ============================================================

function Create-SelfSignedCert {
    param([string]$Subject)
    
    Write-Host "📝 Generating self-signed certificate..." -ForegroundColor Cyan
    
    $cert = New-SelfSignedCertificate `
        -Subject $Subject `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(2) `
        -Type Custom `
        -KeyUsage DigitalSignature
    
    Write-Host "✅ Certificate created" -ForegroundColor Green
    Write-Host "   Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
    Write-Host "   Subject: $($cert.Subject)" -ForegroundColor Green
    
    return $cert
}

function Get-OrCreateCertificate {
    param([string]$Subject)
    
    # Try to find existing certificate
    $existing = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" } | Select-Object -First 1
    
    if ($existing) {
        Write-Host "♻️  Using existing certificate" -ForegroundColor Yellow
        Write-Host "   Thumbprint: $($existing.Thumbprint)" -ForegroundColor Yellow
        return $existing
    }
    
    return Create-SelfSignedCert -Subject $Subject
}

function Get-FunctionKey {
    param(
        [string]$ResourceGroup,
        [string]$FunctionAppName
    )
    
    if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($FunctionAppName)) {
        Write-Host "⚠️  ResourceGroup or FunctionAppName not provided, skipping function key retrieval" -ForegroundColor Yellow
        return $null
    }
    
    Write-Host "🔑 Retrieving function key..." -ForegroundColor Cyan
    
    try {
        $functionKey = az functionapp keys list `
            -g $ResourceGroup `
            -n $FunctionAppName `
            --query "functionKeys.default" `
            -o tsv
        
        if ([string]::IsNullOrWhiteSpace($functionKey)) {
            Write-Host "⚠️  Could not retrieve function key" -ForegroundColor Yellow
            return $null
        }
        
        Write-Host "✅ Function key retrieved" -ForegroundColor Green
        return $functionKey
    }
    catch {
        Write-Host "❌ Failed to retrieve function key: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Add-CertificateToKeyVault {
    param(
        [string]$KeyVaultName,
        [string]$CertThumbprint,
        [string[]]$ExistingThumbprints
    )
    
    if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
        Write-Host "⚠️  KeyVault name not provided, skipping certificate registration" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "🔐 Registering certificate in Key Vault..." -ForegroundColor Cyan
    
    try {
        # Build the thumbprints list
        $allThumbprints = @($CertThumbprint)
        if ($ExistingThumbprints -and $ExistingThumbprints.Count -gt 0) {
            $allThumbprints += $ExistingThumbprints | Where-Object { $_ -ne $CertThumbprint }
        }
        
        $thumbprintList = $allThumbprints -join ","
        
        Write-Host "   Adding thumbprint: $CertThumbprint" -ForegroundColor Gray
        
        # Set the secret in Key Vault
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name AllowedIssuerThumbprints `
            --value $thumbprintList 2>&1 | Out-Null
        
        Write-Host "✅ Certificate registered in Key Vault" -ForegroundColor Green
        Write-Host "   Total allowed thumbprints: $($allThumbprints.Count)" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "⚠️  Could not register certificate (permission denied)" -ForegroundColor Yellow
        Write-Host "   Manual command:" -ForegroundColor Yellow
        Write-Host "   az keyvault secret set --vault-name $KeyVaultName --name AllowedIssuerThumbprints --value '$CertThumbprint'" -ForegroundColor Yellow
        return $false
    }
}

function Get-ExistingCertificateThumbprints {
    param([string]$KeyVaultName)
    
    if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
        return @()
    }
    
    try {
        $secret = az keyvault secret show `
            --vault-name $KeyVaultName `
            --name AllowedIssuerThumbprints `
            --query value `
            -o tsv 2>/dev/null
        
        if ([string]::IsNullOrWhiteSpace($secret)) {
            return @()
        }
        
        return $secret -split "," | ForEach-Object { $_.Trim() }
    }
    catch {
        return @()
    }
}

function Generate-InventoryPayload {
    param(
        [string]$DeviceId,
        [string]$DeviceName,
        [string]$UseCase,
        [int]$PayloadSizeKB
    )
    
    # Create base inventory object
    $inventory = @{
        OS = @{
            Name = "Windows 11"
            Build = "22621"
            Version = "21H2"
            InstallDate = (Get-Date).AddMonths(-6).ToUniversalTime()
        }
        
        Hardware = @{
            Manufacturer = "Dell"
            Model = "Latitude 5540"
            ProcessorCount = 8
            TotalMemoryGB = 16
            DiskSpaceGB = 512
        }
        
        Network = @{
            DNSServers = @("8.8.8.8", "1.1.1.1")
            DHCPEnabled = $true
            DNSSearchOrder = @("contoso.com", "internal.contoso.com")
        }
        
        InstalledApplications = @(
            @{ Name = "Microsoft Teams"; Version = "1.6.00.4472"; Publisher = "Microsoft" }
            @{ Name = "Microsoft Office 365"; Version = "16.0.14731.20200"; Publisher = "Microsoft" }
            @{ Name = "7-Zip"; Version = "19.01"; Publisher = "Igor Pavlov" }
            @{ Name = "Visual Studio Code"; Version = "1.75.1"; Publisher = "Microsoft" }
        )
        
        AntiVirus = @{
            Engine = "Windows Defender"
            EngineVersion = "1.1.22621.1433"
            SignatureVersion = "1.385.1234.0"
            LastUpdate = (Get-Date).AddDays(-1).ToUniversalTime()
        }
        
        SecurityUpdates = @{
            WindowsUpdateStatus = "Current"
            LastUpdateDate = (Get-Date).AddDays(-3).ToUniversalTime()
            PendingRestarts = 0
        }
    }
    
    # Add padding to reach desired size
    $baseJson = $inventory | ConvertTo-Json
    $currentSizeKB = [System.Text.Encoding]::UTF8.GetByteCount($baseJson) / 1024
    
    if ($currentSizeKB -lt $PayloadSizeKB) {
        $paddingSizeKB = [math]::Ceiling($PayloadSizeKB - $currentSizeKB)
        $paddingData = @{
            "___PaddingData___" = @()
        }
        
        for ($i = 0; $i -lt $paddingSizeKB * 100; $i++) {
            $paddingData["___PaddingData___"] += "padding-item-$i"
        }
        
        $inventory["Padding"] = $paddingData
    }
    
    return $inventory
}

function Test-FunctionConnection {
    param(
        [string]$FunctionUrl,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    
    Write-Host "`n🔗 Testing connection to function..." -ForegroundColor Cyan
    
    try {
        $response = Invoke-WebRequest `
            -Uri $FunctionUrl `
            -Method Head `
            -Certificate $Certificate `
            -TimeoutSec 10 `
            -ErrorAction Stop
        
        Write-Host "✅ Connection successful (HTTP $($response.StatusCode))" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Send-TelemetryPayload {
    param(
        [string]$FunctionUrl,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [object]$Payload,
        [string]$FunctionKey
    )
    
    Write-Host "`n📤 Sending telemetry payload..." -ForegroundColor Cyan
    
    $json = $Payload | ConvertTo-Json -Depth 10
    $sizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($json)
    $sizeKB = [math]::Round($sizeBytes / 1024, 2)
    
    Write-Host "   Payload size: $sizeBytes bytes ($sizeKB KB)" -ForegroundColor Gray
    
    try {
        # Build headers
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if (-not [string]::IsNullOrWhiteSpace($FunctionKey)) {
            $headers["x-functions-key"] = $FunctionKey
        }
        
        $response = Invoke-WebRequest `
            -Uri $FunctionUrl `
            -Method Post `
            -Certificate $Certificate `
            -Headers $headers `
            -Body $json `
            -TimeoutSec 30 `
            -ErrorAction Stop
        
        $statusCode = $response.StatusCode
        $responseBody = $response.Content | ConvertFrom-Json
        
        if ($statusCode -eq 202) {
            Write-Host "✅ Payload accepted (HTTP 202)" -ForegroundColor Green
            Write-Host "   Response: $($responseBody | ConvertTo-Json)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "⚠️  Unexpected status code: HTTP $statusCode" -ForegroundColor Yellow
            Write-Host "   Response: $($responseBody | ConvertTo-Json)" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode
        $errorMsg = $_.Exception.Message
        
        Write-Host "❌ Request failed: $errorMsg" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            try {
                $errorBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { $_.ReadToEnd() }
                Write-Host "   Error body: $errorBody" -ForegroundColor Red
            }
            catch { }
        }
        
        return $false
    }
}

# ============================================================
# Main Script
# ============================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Intune.Up - Test Client Simulator" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Validate function URL
if ([string]::IsNullOrWhiteSpace($FunctionUrl)) {
    Write-Host "❌ Function URL is required" -ForegroundColor Red
    exit 1
}

if (-not $FunctionUrl.StartsWith("https://")) {
    Write-Host "❌ Function URL must start with https://" -ForegroundColor Red
    exit 1
}

Write-Host "`n📍 Configuration:" -ForegroundColor Cyan
Write-Host "   Function URL   : $FunctionUrl" -ForegroundColor Gray
Write-Host "   Device ID      : $DeviceId" -ForegroundColor Gray
Write-Host "   Device Name    : $DeviceName" -ForegroundColor Gray
Write-Host "   Use Case       : $UseCase" -ForegroundColor Gray
Write-Host "   Payload Size   : ~$PayloadSizeKB KB" -ForegroundColor Gray

# Get or create certificate
$cert = Get-OrCreateCertificate -Subject "CN=IntuneUp-Collector"

if (-not $cert) {
    Write-Host "❌ Failed to get certificate" -ForegroundColor Red
    exit 1
}

# Setup certificate in Key Vault and get function key (if not skipped)
$functionKey = $null

if (-not $SkipCertSetup) {
    # Get existing thumbprints from Key Vault
    $existingThumbprints = Get-ExistingCertificateThumbprints -KeyVaultName $KeyVaultName
    
    # Add certificate to Key Vault
    if ($KeyVaultName) {
        Add-CertificateToKeyVault `
            -KeyVaultName $KeyVaultName `
            -CertThumbprint $cert.Thumbprint `
            -ExistingThumbprints $existingThumbprints | Out-Null
    }
    
    # Get function key
    if ($ResourceGroup -and $FunctionAppName) {
        $functionKey = Get-FunctionKey `
            -ResourceGroup $ResourceGroup `
            -FunctionAppName $FunctionAppName
    }
}

# Test connection
$connectionOk = Test-FunctionConnection -FunctionUrl $FunctionUrl -Certificate $cert

if (-not $connectionOk) {
    Write-Host "`n⚠️  Warning: Connection test failed, proceeding anyway..." -ForegroundColor Yellow
}

# Generate payload
$payload = Generate-InventoryPayload `
    -DeviceId $DeviceId `
    -DeviceName $DeviceName `
    -UseCase $UseCase `
    -PayloadSizeKB $PayloadSizeKB

# Display payload preview
Write-Host "`n📋 Payload preview:" -ForegroundColor Cyan
$payloadJson = $payload | ConvertTo-Json -Depth 5
$preview = $payloadJson.Substring(0, [math]::Min(300, $payloadJson.Length))
Write-Host "$preview..." -ForegroundColor Gray

# Send payload
$success = Send-TelemetryPayload `
    -FunctionUrl $FunctionUrl `
    -Certificate $cert `
    -Payload $payload `
    -FunctionKey $functionKey

if ($success) {
    Write-Host "`n✅ Test completed successfully!" -ForegroundColor Green
    Write-Host "`n📊 Summary:" -ForegroundColor Cyan
    Write-Host "   Certificate Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "   Device ID              : $DeviceId" -ForegroundColor Gray
    Write-Host "   Message Status         : Accepted (202)" -ForegroundColor Green
    Write-Host "`n💡 Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Check function logs in App Insights" -ForegroundColor Gray
    Write-Host "   2. Verify message in Service Bus queue" -ForegroundColor Gray
    Write-Host "   3. Check if payload was stored in blob (if >200KB)" -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "`n❌ Test failed!" -ForegroundColor Red
    
    # If cert was not added to KV, show manual command
    if ($KeyVaultName -and $cert) {
        Write-Host "`n💡 Manual certificate registration:" -ForegroundColor Cyan
        Write-Host "   Run this command to authorize the certificate:" -ForegroundColor Gray
        Write-Host "   az keyvault secret set --vault-name $KeyVaultName --name AllowedIssuerThumbprints --value '$($cert.Thumbprint)'" -ForegroundColor Yellow
    }
    
    exit 1
}
