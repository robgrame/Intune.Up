<#
.SYNOPSIS
    Detection - Password Expiry Reminder Campaign (server-side targeting)
.DESCRIPTION
    L'informazione sulla scadenza password viene calcolata lato server
    (es. Runbook Azure che interroga AD/Entra ID).
    Il server scrive un trigger file sul device tramite Intune Platform Script.
    Questo script legge quel trigger e determina se mostrare la campagna.

    Trigger file path: C:\ProgramData\IntuneUp\triggers\PasswordExpiryReminder.json
    Contenuto atteso:
      {
        "DaysUntilExpiry": 7,
        "UserUPN": "user@domain.com",
        "WrittenAt": "2026-04-15T09:00:00Z"
      }

    Il trigger viene considerato valido solo se scritto nelle ultime 25 ore
    (evita di mostrare la campagna per trigger obsoleti).

    Intune Remediation: INTUNEUP-UI-PasswordExpiryReminder
    Schedule: giornaliero
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$TriggerFile       = "C:\ProgramData\IntuneUp\triggers\PasswordExpiryReminder.json"
$TriggerMaxAgeHours = 25
$ThresholdDays     = 10

try {
    if (-not (Test-Path $TriggerFile)) {
        Write-Host "Compliant - no trigger file found (user not in target)"
        exit 0
    }

    $trigger = Get-Content $TriggerFile -Raw | ConvertFrom-Json

    # Validità del trigger (non obsoleto)
    $writtenAt = [datetime]$trigger.WrittenAt
    $ageHours  = ((Get-Date).ToUniversalTime() - $writtenAt.ToUniversalTime()).TotalHours
    if ($ageHours -gt $TriggerMaxAgeHours) {
        Write-Host "Compliant - trigger file is stale ($([math]::Round($ageHours,1))h old), removing"
        Remove-Item $TriggerFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $daysUntilExpiry = [int]$trigger.DaysUntilExpiry
    if ($daysUntilExpiry -le $ThresholdDays) {
        Write-Host "Non compliant - password expires in $daysUntilExpiry days (user: $($trigger.UserUPN))"
        exit 1
    }

    Write-Host "Compliant - password expires in $daysUntilExpiry days"
    exit 0

} catch {
    Write-Warning "Detection error: $_"
    exit 1
}
