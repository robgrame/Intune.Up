<#
.SYNOPSIS
    Azure Function - Service Bus trigger, writes data to Log Analytics (PowerShell reference implementation).
.DESCRIPTION
    NOTE: This is the PowerShell reference/POC implementation.
    For production enterprise deployments, use the .NET 10 solution in src/IntuneUp.Collector.ServiceBus.

    Consumes messages from the Service Bus queue (produced by the HTTP entry Function),
    normalises them, and writes to a Log Analytics Workspace via the Logs Ingestion API
    (DCE + DCR, Entra ID / Managed Identity authentication).

    App Settings required:
      APPCONFIG_ENDPOINT              - Azure App Configuration endpoint (preferred)
      IntuneUp__LogAnalytics__DceEndpoint    - Data Collection Endpoint URL
      IntuneUp__LogAnalytics__DcrImmutableId - Default DCR Immutable ID
      IntuneUp__LogAnalytics__TablePrefix    - Optional table prefix (default: "IntuneUp")
#>

param($QueueMessage, $TriggerMetadata)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Logs Ingestion API helper (replaces deprecated HTTP Data Collector API)
# ---------------------------------------------------------------------------
function Send-LogsIngestionData {
    param(
        [string]$DceEndpoint,     # Data Collection Endpoint URL
        [string]$DcrImmutableId,  # DCR Immutable ID (dcr-...)
        [string]$StreamName,      # Custom-IntuneUp_LoginInformation_CL
        [string]$JsonBody         # JSON array of log records
    )

    # Acquire Managed Identity token for Azure Monitor ingestion scope
    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmonitor.azure.com%2F" `
            -Headers @{ Metadata = "true" } `
            -Method Get
        if ([string]::IsNullOrEmpty($tokenResponse.access_token)) {
            throw "access_token is empty in IMDS response"
        }
        $token = $tokenResponse.access_token
    } catch {
        throw "Failed to acquire Managed Identity token for Azure Monitor: $($_.Exception.Message)"
    }

    $uri = "${DceEndpoint}/dataCollectionRules/${DcrImmutableId}/streams/${StreamName}?api-version=2023-01-01"
    $headers = @{
        Authorization  = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $JsonBody -UseBasicParsing
    return $response.StatusCode
}

# ---------------------------------------------------------------------------
# Process message (with claim-check support)
# ---------------------------------------------------------------------------
$rawMessage = $QueueMessage | ConvertFrom-Json -ErrorAction Stop

# Check if this is a claim-check message
if ($rawMessage.ClaimCheck -eq $true) {
    $blobName           = $rawMessage.BlobName
    $storageAccountName = $env:AzureWebJobsStorage__accountName
    $containerName      = "claim-check"
    $blobUri            = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

    $token = (Get-AzAccessToken -ResourceUrl "https://storage.azure.com/").Token
    $blobContent = Invoke-RestMethod -Uri $blobUri `
        -Headers @{ Authorization = "Bearer $token"; "x-ms-version" = "2020-10-02" }
    $payload = $blobContent | ConvertFrom-Json -ErrorAction Stop

    Write-Host "Claim-check: fetched '$blobName'"

    # Cleanup blob
    try {
        Invoke-RestMethod -Uri $blobUri -Method Delete `
            -Headers @{ Authorization = "Bearer $token"; "x-ms-version" = "2020-10-02" } `
            -ErrorAction SilentlyContinue
    } catch {}
} else {
    $payload = $rawMessage
}

# Read config from App Settings
$dceEndpoint   = $env:IntuneUp__LogAnalytics__DceEndpoint
$dcrImmutableId = $env:IntuneUp__LogAnalytics__DcrImmutableId
$prefix         = $env:IntuneUp__LogAnalytics__TablePrefix ?? "IntuneUp"

if ([string]::IsNullOrEmpty($dceEndpoint) -or [string]::IsNullOrEmpty($dcrImmutableId)) {
    throw "Missing Logs Ingestion API configuration (DceEndpoint / DcrImmutableId)"
}

# Derive table and stream names from UseCase: IntuneUp_BitLockerStatus_CL
$useCase    = $payload.UseCase -replace '[^A-Za-z0-9_]', '_'
$tableName  = "${prefix}_${useCase}_CL"
$streamName = "Custom-${tableName}"

# Check for per-use-case DCR override
$useCaseDcrId = [System.Environment]::GetEnvironmentVariable("IntuneUp__LogAnalytics__Dcr__${useCase}__ImmutableId")
if (-not [string]::IsNullOrEmpty($useCaseDcrId)) {
    $dcrImmutableId = $useCaseDcrId
}

# Build the log record — Data is stored as a dynamic column
$record = [ordered]@{
    DeviceId       = $payload.DeviceId
    DeviceName     = $payload.DeviceName
    UPN            = $payload.UPN
    UseCase        = $payload.UseCase
    ReceivedAt     = $payload.ReceivedAt
    FunctionRegion = $payload.FunctionRegion
    Data           = $payload.Data
}

$jsonBody = @($record) | ConvertTo-Json -Depth 10 -Compress

$statusCode = Send-LogsIngestionData `
    -DceEndpoint $dceEndpoint `
    -DcrImmutableId $dcrImmutableId `
    -StreamName $streamName `
    -JsonBody $jsonBody

if ($statusCode -in 200, 204) {
    Write-Host "Written to Log Analytics table '$tableName' for device '$($payload.DeviceName)' - HTTP $statusCode"
} else {
    throw "Logs Ingestion API returned unexpected status: $statusCode"
}