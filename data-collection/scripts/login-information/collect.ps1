<#
.SYNOPSIS
    GETINFO - Get Login Information
.DESCRIPTION
    Raccoglie informazioni di login dal device:
    - Ultimo utente loggato
    - Ora dell'ultimo logon
    - Tipo di logon (locale, domain, Azure AD)
    - Sessioni attive
    - Ultimi N eventi di logon dal Security Event Log

    Nessuna modifica al sistema.
    Invia i dati al collettore Azure tramite HTTPS + certificato client X.509.

    Intune Remediation/Platform Script: INTUNEUP-GETINFO-LoginInformation
    Schedule: ogni 8 ore (o su richiesta)
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase     = "LoginInformation"
$FunctionUrl = $env:INTUNEUP_COLLECTOR_URL   # Configurare come variabile ambiente o hardcode per POC
$CertSubject = $env:INTUNEUP_CERT_SUBJECT ?? "CN=IntuneUp-Collector"
$MaxLoginEvents = 10

# ---------------------------------------------------------------------------
# Helpers (dalla libreria comune - inline per portabilità Intune)
# ---------------------------------------------------------------------------
function Get-CollectorCertificate {
    param([string]$Subject)
    $cert = Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*$Subject*" -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if (-not $cert) { throw "Certificate not found: '$Subject'" }
    return $cert
}

function Send-CollectorData {
    param($Url, $Payload, $Certificate)
    $body    = $Payload | ConvertTo-Json -Depth 10 -Compress
    $headers = @{
        "Content-Type" = "application/json"
    }
    return Invoke-RestMethod -Uri $Url -Method Post -Body $body `
        -Headers $headers -Certificate $Certificate -TimeoutSec 30 -ErrorAction Stop
}

function Get-DeviceMetadata {
    $deviceId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Enrollments\*" -ErrorAction SilentlyContinue |
        Where-Object ProviderID -eq "MS DM Server" | Select-Object -First 1).DeviceEnrollmentID
    return @{
        DeviceId   = $deviceId ?? $env:COMPUTERNAME
        DeviceName = $env:COMPUTERNAME
        UPN        = ""
    }
}

# ---------------------------------------------------------------------------
# Raccolta dati login
# ---------------------------------------------------------------------------
function Get-LoginInformation {
    $data = @{}

    # Ultimo utente loggato (da registry)
    try {
        $lastUser = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" `
            -ErrorAction SilentlyContinue).LastLoggedOnSAMUser
        $lastUserDisplayName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" `
            -ErrorAction SilentlyContinue).LastLoggedOnDisplayName
        $data["LastLoggedOnUser"]        = $lastUser ?? ""
        $data["LastLoggedOnDisplayName"] = $lastUserDisplayName ?? ""
    } catch {}

    # Sessioni attive
    try {
        $sessions = query session 2>&1 | Select-Object -Skip 1 |
            Where-Object { $_ -match 'Active' } |
            ForEach-Object { ($_ -split '\s+' | Where-Object { $_ }) -join ',' }
        $data["ActiveSessions"] = $sessions -join '; '
    } catch {}

    # Informazioni join (Azure AD / Domain / Workgroup)
    try {
        $dsregOutput = dsregcmd /status 2>&1
        $azureAdJoined   = ($dsregOutput | Select-String "AzureAdJoined\s*:\s*YES")  ? $true : $false
        $domainJoined    = ($dsregOutput | Select-String "DomainJoined\s*:\s*YES")   ? $true : $false
        $hybridJoined    = ($dsregOutput | Select-String "DomainName\s*:") -ne $null
        $tenantName      = ($dsregOutput | Select-String "TenantName\s*:\s*(.+)")?.Matches?.Groups[1]?.Value?.Trim()
        $domainName      = ($dsregOutput | Select-String "DomainName\s*:\s*(.+)")?.Matches?.Groups[1]?.Value?.Trim()

        $data["AzureAdJoined"]  = $azureAdJoined
        $data["DomainJoined"]   = $domainJoined
        $data["TenantName"]     = $tenantName ?? ""
        $data["DomainName"]     = $domainName ?? ""
    } catch {}

    # Ultimi eventi di logon dal Security Event Log (Event ID 4624)
    try {
        $loginEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4624
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents $MaxLoginEvents -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,
            @{ N='LogonType'; E={ $_.Properties[8].Value } },
            @{ N='AccountName'; E={ $_.Properties[5].Value } },
            @{ N='WorkstationName'; E={ $_.Properties[11].Value } } |
        Where-Object { $_.AccountName -notmatch '^\$' -and $_.AccountName -ne 'SYSTEM' }

        $data["RecentLogonEvents"] = $loginEvents | ForEach-Object {
            @{
                Time            = $_.TimeCreated.ToString("o")
                LogonType       = $_.LogonType
                AccountName     = $_.AccountName
                WorkstationName = $_.WorkstationName
            }
        }
    } catch {
        $data["RecentLogonEvents"] = @()
    }

    # Uptime corrente
    try {
        $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $data["LastBootTime"]     = $lastBoot.ToString("o")
        $data["UptimeHours"]      = [math]::Round(((Get-Date) - $lastBoot).TotalHours, 1)
    } catch {}

    return $data
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    if ([string]::IsNullOrEmpty($FunctionUrl)) {
        throw "INTUNEUP_COLLECTOR_URL is not set. Configure as environment variable or update script."
    }

    $cert     = Get-CollectorCertificate -Subject $CertSubject
    $metadata = Get-DeviceMetadata
    $loginData = Get-LoginInformation

    $payload = $metadata + @{
        UseCase = $UseCase
        Data    = $loginData
    }

    $result = Send-CollectorData -Url $FunctionUrl -Payload $payload -Certificate $cert
    Write-Host "LoginInformation sent successfully"
    exit 0

} catch {
    Write-Error "GetInfo LoginInformation failed: $_"
    exit 1
}
