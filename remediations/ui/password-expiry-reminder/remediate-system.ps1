<#
.SYNOPSIS
    Remediation SYSTEM - Password Expiry Reminder: notifica utente
.DESCRIPTION
    Legge i dati dal trigger file scritto dal server, crea uno Scheduled Task
    nel contesto utente per mostrare la notifica di cambio password.
    Dopo aver schedulato la notifica, rimuove il trigger file
    (evita campagna ripetuta prima del prossimo aggiornamento server).
    Intune Remediation: INTUNEUP-UI-PasswordExpiryReminder
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase         = "PasswordExpiryReminder"
$TriggerFile     = "C:\ProgramData\IntuneUp\triggers\$UseCase.json"
$NotifyScriptPath = "C:\ProgramData\IntuneUp\notify\$UseCase\notify-user.ps1"
$DataDir         = "C:\ProgramData\IntuneUp\notify\$UseCase"
$EventSource     = "IntuneUp"

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName "Application" -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName "Application" -Source $EventSource `
            -EntryType $EntryType -EventId 1102 -Message "[$UseCase] $Message"
    } catch {}
}

function Get-CurrentInteractiveUser {
    (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Select-Object -First 1).UserName
}

try {
    $trigger = Get-Content $TriggerFile -Raw | ConvertFrom-Json

    # Passa i dati allo script di notifica
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    $trigger | ConvertTo-Json | Set-Content -Path "$DataDir\data.json" -Force

    $currentUser = Get-CurrentInteractiveUser
    if (-not $currentUser) {
        Write-IntuneLog "No interactive user, skipping notification" -EntryType "Warning"
        exit 0
    }
    if (-not (Test-Path $NotifyScriptPath)) {
        Write-IntuneLog "Notify script not found at '$NotifyScriptPath'" -EntryType "Warning"
        exit 0
    }

    $taskName  = "IntuneUp-$UseCase-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                     -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -File `"$NotifyScriptPath`""
    $trigger_st = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet `
                     -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 120) `
                     -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
                     -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger_st `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-IntuneLog "Notification scheduled for '$currentUser' ($($trigger.DaysUntilExpiry) days until expiry)"

    # Rimuovi il trigger dopo aver schedulato la notifica
    Remove-Item $TriggerFile -Force -ErrorAction SilentlyContinue

    exit 0
} catch {
    Write-IntuneLog "Error: $_" -EntryType "Error"
    exit 1
}
