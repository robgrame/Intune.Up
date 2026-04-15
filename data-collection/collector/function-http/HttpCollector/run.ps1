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
# Validates that the client cert was issued by a trusted CA (issuer thumbprint).
# ---------------------------------------------------------------------------
$allowedIssuerThumbs = ($env:ALLOWED_ISSUER_THUMBPRINTS -split ',') | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }

$certValid = $false
$arrCert = $Request.Headers['X-ARR-ClientCert']
if (-not [string]::IsNullOrEmpty($arrCert)) {
    try {
        $certBytes = [Convert]::FromBase64String($arrCert)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)

        if ($allowedIssuerThumbs) {
            $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
            $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $null = $chain.Build($cert)
            # Skip element[0] (leaf/client cert), check only issuers (intermediate + root CAs)
            for ($i = 1; $i -lt $chain.ChainElements.Count; $i++) {
                if ($chain.ChainElements[$i].Certificate.Thumbprint.ToUpper() -in $allowedIssuerThumbs) {
                    $certValid = $true
                    break
                }
            }
            $chain.Dispose()
        }

        if (-not $certValid) {
            Write-Warning "Rejected - cert thumbprint: '$($cert.Thumbprint)', issuer: '$($cert.Issuer)'"
        }
    } catch {
        Write-Warning "Failed to parse X-ARR-ClientCert: $_"
    }
} else {
    Write-Warning "Rejected - no client certificate provided"
}

if (-not $certValid) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body       = '{"error":"Unauthorized - valid client certificate required"}'
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
