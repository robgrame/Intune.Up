<#
.SYNOPSIS
    Remediation SYSTEM - Password Expiry Reminder (self-contained)
.DESCRIPTION
    Legge i dati dal trigger file scritto dal server, genera lo script di notifica
    on-the-fly e crea uno Scheduled Task nel contesto utente per mostrarlo.
    Nessun prerequisito: tutto e' embedded in questo singolo script.
    Dopo aver schedulato la notifica, rimuove il trigger file.
    Intune Remediation: INTUNEUP-UI-PasswordExpiryReminder
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase         = "PasswordExpiryReminder"
$TriggerFile     = "C:\ProgramData\IntuneUp\triggers\$UseCase.json"
$NotifyDir       = "C:\ProgramData\IntuneUp\notify\$UseCase"
$NotifyScriptPath = "$NotifyDir\notify-user.ps1"
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

# Embedded notification script (written to disk, executed in USER context)
$notifyScriptContent = @'
$UseCase  = "PasswordExpiryReminder"
$DataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"
$AppId    = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

$daysUntilExpiry = 10
$userUPN         = ""
try {
    if (Test-Path $DataFile) {
        $data            = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysUntilExpiry = $data.DaysUntilExpiry
        $userUPN         = $data.UserUPN
    }
} catch {}

$urgency = if ($daysUntilExpiry -le 3) { "[!] URGENTE - " } else { "" }
$title   = "${urgency}La tua password sta per scadere"
$message = "La password scade tra $daysUntilExpiry giorni. Cambiala il prima possibile per evitare interruzioni di accesso."

# Try BurntToast first, fallback to native XML toast
$useBurntToast = $false
try {
    if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
        Import-Module BurntToast -ErrorAction Stop
        $useBurntToast = $true
    }
} catch {}

if ($useBurntToast) {
    try {
        $btnChange = New-BTButton -Content "Cambia password ora" -Arguments "https://aka.ms/sspr" -ActivationType Protocol
        $btnLater  = New-BTButton -Content "Piu tardi" -Arguments "later"
        New-BurntToastNotification -Text $title, $message -Button $btnChange, $btnLater
        exit 0
    } catch {}
}

# Fallback: native Windows Toast XML
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $scenario = if ($daysUntilExpiry -le 3) { 'alarm' } else { 'reminder' }
    $toastXml = @"
<toast scenario="$scenario" activationType="foreground">
  <visual>
    <binding template="ToastGeneric">
      <text>$title</text>
      <text>$message</text>
    </binding>
  </visual>
  <actions>
    <action content="Cambia password ora" arguments="https://aka.ms/sspr" activationType="protocol"/>
    <action content="Piu tardi" arguments="later" activationType="foreground"/>
  </actions>
</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast    = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)
    exit 0
} catch {
    exit 1
}
'@

try {
    $trigger = Get-Content $TriggerFile -Raw | ConvertFrom-Json

    # Crea directory e scrivi lo script di notifica + dati
    if (-not (Test-Path $NotifyDir)) { New-Item -ItemType Directory -Path $NotifyDir -Force | Out-Null }
    $trigger | ConvertTo-Json | Set-Content -Path "$NotifyDir\data.json" -Force -Encoding UTF8
    Set-Content -Path $NotifyScriptPath -Value $notifyScriptContent -Force -Encoding UTF8

    $currentUser = Get-CurrentInteractiveUser
    if (-not $currentUser) {
        Write-IntuneLog "No interactive user, skipping notification" -EntryType "Warning"
        exit 0
    }

    # Crea Scheduled Task nel contesto utente
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
