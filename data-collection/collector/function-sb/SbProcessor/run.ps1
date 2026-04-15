<#
.SYNOPSIS
    Azure Function – Service Bus trigger, writes data to Log Analytics.
.DESCRIPTION
    Consumes messages from the Service Bus queue (produced by the HTTP entry Function),
    normalises them, and writes to a Log Analytics Workspace via the Data Collector API.

    App Settings required:
      LOG_ANALYTICS_WORKSPACE_ID  – Workspace ID (GUID)
      LOG_ANALYTICS_SHARED_KEY    – Primary or secondary shared key
      LOG_TABLE_PREFIX            – Optional prefix for table names (default: "IntuneUp")
#>

param($QueueMessage, $TriggerMetadata)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Log Analytics Data Collector API helper
# ---------------------------------------------------------------------------
function Send-LogAnalyticsData {
    param(
        [string]$WorkspaceId,
        [string]$SharedKey,
        [string]$LogType,      # becomes <LogType>_CL in Log Analytics
        [string]$JsonBody
    )

    $date    = [DateTime]::UtcNow.ToString("r")
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
    $contentLength = $bodyBytes.Length

    $stringToHash = "POST`n$contentLength`napplication/json`nx-ms-date:$date`n/api/logs"
    $bytesToHash  = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes     = [System.Convert]::FromBase64String($SharedKey)
    $hmac         = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key     = $keyBytes
    $signature    = [System.Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
    $authorization = "SharedKey ${WorkspaceId}:${signature}"

    $uri = "https://$WorkspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    $headers = @{
        "Authorization"        = $authorization
        "Log-Type"             = $LogType
        "x-ms-date"            = $date
        "time-generated-field" = "ReceivedAt"
    }

    $response = Invoke-WebRequest -Uri $uri -Method Post -ContentType "application/json" `
        -Headers $headers -Body $bodyBytes -UseBasicParsing
    return $response.StatusCode
}

# ---------------------------------------------------------------------------
# Process message
# ---------------------------------------------------------------------------
try {
    $payload = $QueueMessage | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Failed to deserialize Service Bus message: $_"
    throw   # rethrow → Service Bus will retry / dead-letter
}

$workspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
$sharedKey   = $env:LOG_ANALYTICS_SHARED_KEY
$prefix      = $env:LOG_TABLE_PREFIX ?? "IntuneUp"

if ([string]::IsNullOrEmpty($workspaceId) -or [string]::IsNullOrEmpty($sharedKey)) {
    throw "Missing Log Analytics configuration (LOG_ANALYTICS_WORKSPACE_ID / LOG_ANALYTICS_SHARED_KEY)"
}

# Derive table name from UseCase: "IntuneUp_BitLockerStatus"
$useCase  = $payload.UseCase -replace '[^A-Za-z0-9_]', '_'
$logType  = "${prefix}_${useCase}"

# Flatten Data into the top-level object for easier KQL querying
$record = [ordered]@{
    DeviceId      = $payload.DeviceId
    DeviceName    = $payload.DeviceName
    UPN           = $payload.UPN
    UseCase       = $payload.UseCase
    ReceivedAt    = $payload.ReceivedAt
    FunctionRegion = $payload.FunctionRegion
}
# Merge Data fields at top level
if ($payload.Data -is [PSCustomObject]) {
    $payload.Data.PSObject.Properties | ForEach-Object {
        $record[$_.Name] = $_.Value
    }
}

$jsonBody = @($record) | ConvertTo-Json -Depth 5 -Compress

$statusCode = Send-LogAnalyticsData -WorkspaceId $workspaceId -SharedKey $sharedKey `
    -LogType $logType -JsonBody $jsonBody

if ($statusCode -in 200, 202) {
    Write-Host "Written to Log Analytics table '$logType' for device '$($payload.DeviceName)' – HTTP $statusCode"
} else {
    throw "Log Analytics API returned unexpected status: $statusCode"
}
