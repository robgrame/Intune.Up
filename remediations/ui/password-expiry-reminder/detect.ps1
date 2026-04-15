<#
.SYNOPSIS
    Detection - Password Expiry Reminder Campaign (pull-based)
.DESCRIPTION
    Il client interroga un endpoint server-side (Azure Function / Azure Table)
    per verificare se l'utente corrente ha la password in scadenza.

    Il Runbook server-side popola una Azure Table Storage con i record:
      PartitionKey = "PasswordExpiry"
      RowKey       = UPN (lowercase)
      DaysUntilExpiry = N

    Questo script legge l'UPN dell'utente corrente, chiama l'endpoint
    e verifica se e' presente un record con scadenza <= ThresholdDays.

    Se l'endpoint non e' raggiungibile, lo script esce compliant (fail-safe).

    Intune Remediation: INTUNEUP-UI-PasswordExpiryReminder
    Schedule: giornaliero
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$ThresholdDays  = 10
$EndpointUrl    = $env:INTUNEUP_EXPIRY_ENDPOINT   # es: https://func-intuneup-http-dev.azurewebsites.net/api/password-expiry
$CertSubject    = $env:INTUNEUP_CERT_SUBJECT ?? "CN=IntuneUp-Collector"
$DataDir        = "C:\ProgramData\IntuneUp\notify\PasswordExpiryReminder"

function Get-CurrentUserUPN {
    try {
        $upn = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" `
            -ErrorAction SilentlyContinue).LastLoggedOnSAMUser
        if ($upn) { return $upn }
        $dsreg = dsregcmd /status 2>&1
        $match = $dsreg | Select-String "UserEmail\s*:\s*(.+)"
        if ($match) { return $match.Matches.Groups[1].Value.Trim() }
    } catch {}
    return $null
}

function Get-CollectorCertificate {
    param([string]$Subject)
    Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*$Subject*" -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
}

try {
    $upn = Get-CurrentUserUPN
    if (-not $upn) {
        Write-Host "Compliant - no logged on user detected"
        exit 0
    }

    if ([string]::IsNullOrEmpty($EndpointUrl)) {
        Write-Host "Compliant - INTUNEUP_EXPIRY_ENDPOINT not configured"
        exit 0
    }

    $cert = Get-CollectorCertificate -Subject $CertSubject

    $response = $null
    try {
        $queryUrl = "${EndpointUrl}?upn=$([uri]::EscapeDataString($upn))"
        $params = @{ Uri = $queryUrl; Method = "Get"; TimeoutSec = 15; ErrorAction = "Stop" }
        if ($cert) { $params["Certificate"] = $cert }
        $response = Invoke-RestMethod @params
    } catch {
        Write-Host "Compliant - endpoint unreachable (fail-safe): $_"
        exit 0
    }

    if ($response -and $response.Expiring -eq $true -and [int]$response.DaysUntilExpiry -le $ThresholdDays) {
        if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
        $response | ConvertTo-Json | Set-Content -Path "$DataDir\data.json" -Force -Encoding UTF8

        Write-Host "Non compliant - password expires in $($response.DaysUntilExpiry) days (user: $upn)"
        exit 1
    }

    Write-Host "Compliant - password not expiring soon for $upn"
    exit 0

} catch {
    Write-Warning "Detection error: $_"
    exit 0
}