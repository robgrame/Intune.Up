<#
.SYNOPSIS
    Remediation SYSTEM - Reboot Reminder (self-contained)
.DESCRIPTION
    Calcola i giorni dall'ultimo reboot, genera lo script di notifica
    on-the-fly e crea uno Scheduled Task nel contesto utente.
    Nessun prerequisito: tutto e' embedded in questo singolo script.
    Intune Remediation: INTUNEUP-UI-RebootReminder
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase         = "RebootReminder"
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
            -EntryType $EntryType -EventId 1101 -Message "[$UseCase] $Message"
    } catch {}
}

function Get-CurrentInteractiveUser {
    (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Select-Object -First 1).UserName
}

# Embedded notification script (written to disk, executed in USER context)
$notifyScriptContent = @'
$UseCase  = "RebootReminder"
$DataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"
$AppId    = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

$daysSince = 14
try {
    if (Test-Path $DataFile) {
        $data = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysSince = $data.DaysSinceReboot
    }
} catch {}

$title   = "Riavvio richiesto"
$message = "Il tuo PC non viene riavviato da $daysSince giorni. Il riavvio e' necessario per installare aggiornamenti e migliorare le prestazioni."

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
        $btn1 = New-BTButton -Content "Riavvia ora"              -Arguments "restart-now"
        $btn2 = New-BTButton -Content "Ricordamelo piu tardi"    -Arguments "later"
        New-BurntToastNotification -Text $title, $message -Button $btn1, $btn2
        exit 0
    } catch {}
}

# Fallback: native Windows Toast XML
try {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
        exit $LASTEXITCODE
    }
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    [void][Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]

    $toastXml = @"
<toast scenario="reminder" activationType="foreground">
  <visual>
    <binding template="ToastGeneric">
      <text>$title</text>
      <text>$message</text>
    </binding>
  </visual>
  <actions>
    <action content="Riavvia ora" arguments="restart-now" activationType="foreground"/>
    <action content="Ricordamelo piu tardi" arguments="later" activationType="foreground"/>
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
    $lastBoot  = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $daysSince = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 0)

    # Crea directory, scrivi lo script di notifica + dati
    if (-not (Test-Path $NotifyDir)) { New-Item -ItemType Directory -Path $NotifyDir -Force | Out-Null }
    @{ DaysSinceReboot = $daysSince } | ConvertTo-Json | Set-Content -Path "$NotifyDir\data.json" -Force -Encoding UTF8
    Set-Content -Path $NotifyScriptPath -Value $notifyScriptContent -Force -Encoding UTF8

    $currentUser = Get-CurrentInteractiveUser
    if (-not $currentUser) {
        Write-IntuneLog "No interactive user found, skipping notification" -EntryType "Warning"
        exit 0
    }

    # Crea Scheduled Task nel contesto utente
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
