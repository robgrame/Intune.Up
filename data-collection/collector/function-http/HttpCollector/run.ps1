<#
.SYNOPSIS
    Azure Function - HTTP trigger entry point for client data collection.
.DESCRIPTION
    Receives telemetry payloads from managed devices via HTTPS + client certificate.
    Validates the client certificate thumbprint against an allowlist, enriches the
    payload with server-side metadata, then enqueues to Azure Service Bus.

    Expected request:
      POST /api/collect
      Client certificate: presented via mutual TLS (validated by App Service + Function)
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
# Checks: expiration, EKU, issuer thumbprint in chain, chain subject names.
# ---------------------------------------------------------------------------
$allowedIssuerThumbs    = ($env:ALLOWED_ISSUER_THUMBPRINTS -split ',') | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
$requiredChainSubjects  = ($env:REQUIRED_CHAIN_SUBJECTS -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$requiredCertSubject    = $env:REQUIRED_CERT_SUBJECT
$checkRevocation        = $env:CHECK_CERT_REVOCATION -eq 'true'

$certValid = $false
$rejectReason = ""
$arrCert = $Request.Headers['X-ARR-ClientCert']
if (-not [string]::IsNullOrEmpty($arrCert)) {
    try {
        $certBytes = [Convert]::FromBase64String($arrCert)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)

        # 1. Expiration check
        $now = [DateTime]::UtcNow
        if ($now -lt $cert.NotBefore) {
            $rejectReason = "Certificate not yet valid (NotBefore: $($cert.NotBefore.ToString('o')))"
        } elseif ($now -gt $cert.NotAfter) {
            $rejectReason = "Certificate expired (NotAfter: $($cert.NotAfter.ToString('o')))"
        }

        # 2. Leaf subject pattern check
        if (-not $rejectReason -and $requiredCertSubject) {
            if ($cert.Subject -notmatch [regex]::Escape($requiredCertSubject)) {
                $rejectReason = "Subject '$($cert.Subject)' does not match required pattern '$requiredCertSubject'"
            }
        }

        # 3. EKU check - if present, must include Client Authentication (1.3.6.1.5.5.7.3.2)
        if (-not $rejectReason) {
            $eku = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] }
            if ($eku) {
                $hasClientAuth = $eku.EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.2' }
                if (-not $hasClientAuth) {
                    $rejectReason = "EKU does not include Client Authentication (1.3.6.1.5.5.7.3.2)"
                }
            }
        }

        # 4. Chain validation + issuer thumbprint
        if (-not $rejectReason -and $allowedIssuerThumbs) {
            $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
            $chain.ChainPolicy.RevocationMode = if ($checkRevocation) {
                [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
            } else {
                [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            }
            $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
            $null = $chain.Build($cert)

            # Check for critical chain errors
            $criticalErrors = $chain.ChainStatus | Where-Object {
                $_.Status -ne 'NoError' -and
                $_.Status -ne 'UntrustedRoot' -and
                (-not $checkRevocation -or ($_.Status -ne 'RevocationStatusUnknown' -and $_.Status -ne 'OfflineRevocation'))
            }
            if ($criticalErrors) {
                $rejectReason = "Chain validation failed: $(($criticalErrors | ForEach-Object { "$($_.Status): $($_.StatusInformation)" }) -join '; ')"
            }

            # Check issuer thumbprint (skip leaf cert at index 0)
            if (-not $rejectReason) {
                $issuerFound = $false
                for ($i = 1; $i -lt $chain.ChainElements.Count; $i++) {
                    if ($chain.ChainElements[$i].Certificate.Thumbprint.ToUpper() -in $allowedIssuerThumbs) {
                        $issuerFound = $true
                        break
                    }
                }
                if (-not $issuerFound) {
                    $rejectReason = "Issuer not trusted. Issuer: '$($cert.Issuer)'"
                }
            }

            # 5. Chain subject names check
            if (-not $rejectReason -and $requiredChainSubjects) {
                $chainSubjects = @()
                for ($i = 1; $i -lt $chain.ChainElements.Count; $i++) {
                    $chainSubjects += $chain.ChainElements[$i].Certificate.Subject
                }
                foreach ($reqSubject in $requiredChainSubjects) {
                    $found = $chainSubjects | Where-Object { $_ -match [regex]::Escape($reqSubject) }
                    if (-not $found) {
                        $rejectReason = "Required chain subject '$reqSubject' not found. Chain: [$($chainSubjects -join ' -> ')]"
                        break
                    }
                }
            }

            $chain.Dispose()
        }

        if (-not $rejectReason) { $certValid = $true }
        else { Write-Warning "Rejected - $rejectReason" }

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
