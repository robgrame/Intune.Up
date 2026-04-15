<#
.SYNOPSIS
    Template - Remediation SYSTEM: azione tecnica + creazione Scheduled Task per notifica utente
.DESCRIPTION
    Eseguito in contesto SYSTEM da Intune.
    1. Esegue l'azione tecnica (se necessaria)
    2. Crea uno Scheduled Task one-time nel contesto dell'utente corrente
       per eseguire notify-user.ps1
.NOTES
    Naming:  INTUNEUP-UI-<UseCase>
    Context: SYSTEM
    Richiede: notify-user.ps1 (o .burnttoast.ps1) distribuito sul client
              Percorso consigliato: C:\ProgramData\IntuneUp\notify\
#>

$ErrorActionPreference = "Stop"
$UseCase       = "TODO_USECASE"
$NotifyScriptPath = "C:\ProgramData\IntuneUp\notify\$UseCase\notify-user.ps1"
$EventSource   = "IntuneUp"

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName "Application" -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName "Application" -Source $EventSource -EntryType $EntryType `
            -EventId 1001 -Message "[$UseCase] $Message"
    } catch {}
}

function Get-CurrentInteractiveUser {
    try {
        $user = (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
            Select-Object -First 1).UserName
        return $user
    } catch {
        return $null
    }
}

function Register-UserNotificationTask {
    param([string]$UserName, [string]$ScriptPath)

    $taskName = "IntuneUp-Notify-$UseCase-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -File `"$ScriptPath`""
    $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
    $principal = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet `
                    -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 120) `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
                    -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-IntuneLog "Scheduled Task '$taskName' created for user '$UserName'"
}

try {
    Write-IntuneLog "Remediation (SYSTEM) started"

    # -------------------------------------------------------------------------
    # TODO: azione tecnica in contesto SYSTEM (se necessaria)
    # -------------------------------------------------------------------------
    # es: Restart-Service -Name "OneDrive" -Force
    # -------------------------------------------------------------------------

    # Notifica utente via Scheduled Task
    $currentUser = Get-CurrentInteractiveUser
    if ($null -eq $currentUser) {
        Write-IntuneLog "No interactive user found, skipping notification" -EntryType "Warning"
    } elseif (-not (Test-Path $NotifyScriptPath)) {
        Write-IntuneLog "Notify script not found at '$NotifyScriptPath', skipping notification" -EntryType "Warning"
    } else {
        Register-UserNotificationTask -UserName $currentUser -ScriptPath $NotifyScriptPath
    }

    Write-IntuneLog "Remediation (SYSTEM) completed"
    exit 0

} catch {
    Write-IntuneLog "Remediation failed: $_" -EntryType "Error"
    exit 1
}
