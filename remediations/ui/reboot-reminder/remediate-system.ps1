<#
.SYNOPSIS
    Remediation SYSTEM – Reboot Reminder: crea Scheduled Task per notifica utente
.DESCRIPTION
    Non esegue azione tecnica immediata.
    Calcola i giorni dall'ultimo reboot e crea uno Scheduled Task
    nel contesto utente per mostrare la notifica di richiesta reboot.
    Intune Remediation: INTUNEUP-UI-RebootReminder
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase         = "RebootReminder"
$NotifyScriptPath = "C:\ProgramData\IntuneUp\notify\$UseCase\notify-user.ps1"
$EventSource     = "IntuneUp"

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName "Application" -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName "Application" -Source $EventSource `
            -EntryType $EntryType -EventId 1101 -Message "[$UseCase] $Message"
    } catch {}
}

function Get-CurrentInteractiveUser {
    (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Select-Object -First 1).UserName
}

try {
    $lastBoot  = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $daysSince = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 0)

    # Scrivi i giorni in un file temporaneo leggibile dallo script utente
    $dataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"
    $dataDir  = Split-Path $dataFile
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    @{ DaysSinceReboot = $daysSince } | ConvertTo-Json | Set-Content -Path $dataFile -Force

    $currentUser = Get-CurrentInteractiveUser
    if (-not $currentUser) {
        Write-IntuneLog "No interactive user found, skipping notification" -EntryType "Warning"
        exit 0
    }
    if (-not (Test-Path $NotifyScriptPath)) {
        Write-IntuneLog "Notify script not found at '$NotifyScriptPath'" -EntryType "Warning"
        exit 0
    }

    $taskName  = "IntuneUp-$UseCase-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                     -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -File `"$NotifyScriptPath`""
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet `
                     -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 120) `
                     -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
                     -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-IntuneLog "Scheduled notification for '$currentUser' (last reboot: $daysSince days ago)"
    exit 0

} catch {
    Write-IntuneLog "Error: $_" -EntryType "Error"
    exit 1
}
