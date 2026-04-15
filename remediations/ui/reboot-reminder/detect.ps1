<#
.SYNOPSIS
    Detection – Reboot Reminder Campaign
.DESCRIPTION
    Verifica se l'ultimo riavvio è avvenuto più di 14 giorni fa.
    Non compliant → campagna chiede all'utente di riavviare.
    Intune Remediation: INTUNEUP-UI-RebootReminder
    Schedule: giornaliero
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$MaxDaysSinceReboot = 14

try {
    $lastBoot   = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $daysSince  = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)

    if ($daysSince -gt $MaxDaysSinceReboot) {
        Write-Host "Non compliant – last reboot $daysSince days ago (threshold: $MaxDaysSinceReboot days)"
        exit 1
    }

    Write-Host "Compliant – last reboot $daysSince days ago"
    exit 0

} catch {
    Write-Warning "Detection error: $_"
    exit 1
}
