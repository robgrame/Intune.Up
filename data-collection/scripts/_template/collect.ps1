<#
.SYNOPSIS
    Template – Data Collection script (client-side)
.DESCRIPTION
    Raccoglie informazioni dal device e le invia al collettore Azure
    tramite HTTPS con autenticazione tramite certificato client X.509.
    Non apporta modifiche al sistema.

    Replace:
      TODO_USECASE          → nome del use case (es. "BitLockerStatus")
      TODO_FUNCTION_URL     → URL della Azure Function HTTP trigger
      TODO_CERT_SUBJECT     → Subject del certificato client (es. "CN=IntuneUp-Collector")
                              oppure usare TODO_CERT_THUMBPRINT

    Il certificato deve essere distribuito ai device tramite Intune (SCEP/PKCS)
    e presente in Cert:\LocalMachine\My
#>

$ErrorActionPreference = "Stop"
$UseCase      = "TODO_USECASE"
$FunctionUrl  = "TODO_FUNCTION_URL"
$CertSubject  = "TODO_CERT_SUBJECT"   # es: "CN=IntuneUp-Collector"
# Alternativa: $CertThumbprint = "TODO_CERT_THUMBPRINT"

# ---------------------------------------------------------------------------
# Trova il certificato client
# ---------------------------------------------------------------------------
function Get-CollectorCertificate {
    param([string]$Subject)
    $cert = Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*$Subject*" -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if (-not $cert) {
        throw "Certificate not found in Cert:\LocalMachine\My with subject '$Subject'"
    }
    return $cert
}

# ---------------------------------------------------------------------------
# Invia i dati al collettore
# ---------------------------------------------------------------------------
function Send-CollectorData {
    param(
        [string]$Url,
        [hashtable]$Payload,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $body = $Payload | ConvertTo-Json -Depth 10 -Compress
    $headers = @{
        "Content-Type"         = "application/json"
        "X-Client-Thumbprint"  = $Certificate.Thumbprint
    }

    $response = Invoke-RestMethod -Uri $Url -Method Post -Body $body `
        -Headers $headers -Certificate $Certificate `
        -TimeoutSec 30 -ErrorAction Stop

    return $response
}

# ---------------------------------------------------------------------------
# Metadati device
# ---------------------------------------------------------------------------
function Get-DeviceMetadata {
    $intuneDeviceId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations" `
        -ErrorAction SilentlyContinue).EntDMID
    if (-not $intuneDeviceId) {
        $intuneDeviceId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\*" `
            -ErrorAction SilentlyContinue | Where-Object ProviderID -eq "MS DM Server" |
            Select-Object -First 1).DeviceEnrollmentID
    }

    $upn = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" `
        -ErrorAction SilentlyContinue).LastLoggedOnSAMUser

    return @{
        DeviceId   = $intuneDeviceId ?? $env:COMPUTERNAME
        DeviceName = $env:COMPUTERNAME
        UPN        = $upn ?? ""
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    $cert     = Get-CollectorCertificate -Subject $CertSubject
    $metadata = Get-DeviceMetadata

    # -------------------------------------------------------------------------
    # TODO: inserire qui la logica di raccolta dati
    # -------------------------------------------------------------------------
    $collectedData = @{
        # Esempio:
        # PropertyName = "value"
    }
    # -------------------------------------------------------------------------

    $payload = $metadata + @{
        UseCase = $UseCase
        Data    = $collectedData
    }

    $result = Send-CollectorData -Url $FunctionUrl -Payload $payload -Certificate $cert
    Write-Host "Data sent successfully for use case '$UseCase'. Response: $($result | ConvertTo-Json -Compress)"
    exit 0

} catch {
    Write-Error "Data collection failed for '$UseCase': $_"
    exit 1
}
