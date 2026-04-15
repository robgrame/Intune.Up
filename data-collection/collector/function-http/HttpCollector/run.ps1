<#
.SYNOPSIS
    Azure Function - HTTP trigger entry point for client data collection.
.DESCRIPTION
    Receives telemetry payloads from managed devices via HTTPS + client certificate.
    Validates the client certificate thumbprint against an allowlist, enriches the
    payload with server-side metadata, then enqueues to Azure Service Bus.

    Expected request:
      POST /api/collect
      Header: X-Client-Thumbprint: <certificate thumbprint>
      Body (JSON):
        {
          "DeviceId":   "<Intune Device ID>",
          "DeviceName": "<hostname>",
          "UPN":        "<user@domain>",
          "UseCase":    "<collection use case name>",
          "Data":       { ... }
        }

    App Settings required:
      ALLOWED_CERT_THUMBPRINTS  - comma-separated list of allowed thumbprints
      SERVICEBUS_CONNECTION     - Service Bus connection string (or Managed Identity)
      SERVICEBUS_QUEUE_NAME     - target queue name
#>

using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Certificate validation
# App Service mutual TLS populates X-ARR-ClientCert with base64-encoded cert.
# Falls back to X-Client-Thumbprint for local dev/testing.
# ---------------------------------------------------------------------------
$allowedThumbs = ($env:ALLOWED_CERT_THUMBPRINTS -split ',') | ForEach-Object { $_.Trim().ToUpper() }

$clientThumb = $null
$arrCert = $Request.Headers['X-ARR-ClientCert']
if (-not [string]::IsNullOrEmpty($arrCert)) {
    try {
        $certBytes = [Convert]::FromBase64String($arrCert)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
        $clientThumb = $cert.Thumbprint.ToUpper()
    } catch {
        Write-Warning "Failed to parse X-ARR-ClientCert: $_"
    }
}
if (-not $clientThumb) {
    $clientThumb = ($Request.Headers['X-Client-Thumbprint'] ?? '').Trim().ToUpper()
}

if ([string]::IsNullOrEmpty($clientThumb) -or ($clientThumb -notin $allowedThumbs)) {
    Write-Warning "Rejected request - thumbprint: '$clientThumb'"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body       = '{"error":"Unauthorized"}'
        Headers    = @{ 'Content-Type' = 'application/json' }
    })
    return
}

# ---------------------------------------------------------------------------
# Parse and validate body
# ---------------------------------------------------------------------------
try {
    $payload = $Request.Body | ConvertFrom-Json -ErrorAction Stop
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = '{"error":"Invalid JSON body"}'
        Headers    = @{ 'Content-Type' = 'application/json' }
    })
    return
}

$requiredFields = @('DeviceId','DeviceName','UseCase','Data')
foreach ($field in $requiredFields) {
    if (-not $payload.PSObject.Properties[$field]) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "{`"error`":`"Missing required field: $field`"}"
            Headers    = @{ 'Content-Type' = 'application/json' }
        })
        return
    }
}

# ---------------------------------------------------------------------------
# Enrich payload with server-side metadata
# ---------------------------------------------------------------------------
$enriched = @{
    DeviceId      = $payload.DeviceId
    DeviceName    = $payload.DeviceName
    UPN           = $payload.UPN
    UseCase       = $payload.UseCase
    Data          = $payload.Data
    ReceivedAt    = (Get-Date).ToUniversalTime().ToString("o")
    FunctionRegion = $env:REGION_NAME ?? "unknown"
}

# ---------------------------------------------------------------------------
# Enqueue to Service Bus
# ---------------------------------------------------------------------------
$messageBody = $enriched | ConvertTo-Json -Depth 10 -Compress

Push-OutputBinding -Name OutputMessage -Value $messageBody

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::Accepted
    Body       = '{"status":"accepted"}'
    Headers    = @{ 'Content-Type' = 'application/json' }
})

Write-Host "Accepted payload from device '$($payload.DeviceName)' use case '$($payload.UseCase)'"
