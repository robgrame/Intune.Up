<#
.SYNOPSIS
    Remediation SYSTEM - Password Expiry Reminder (self-contained, pull-based)
.DESCRIPTION
    Legge i dati scritti dalla detection (data.json), genera lo script di notifica
    on-the-fly e crea uno Scheduled Task nel contesto utente per mostrarlo.
    Nessun prerequisito: deploy su Intune con solo detect.ps1 + remediate-system.ps1
    Intune Remediation: INTUNEUP-UI-PasswordExpiryReminder
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase          = "PasswordExpiryReminder"
$NotifyDir        = "C:\ProgramData\IntuneUp\notify\$UseCase"
$NotifyScriptPath = "$NotifyDir\notify-user.ps1"
$DataFile         = "$NotifyDir\data.json"
$EventSource      = "IntuneUp"

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

$notifyScriptContent = @'
$DataFile = "C:\ProgramData\IntuneUp\notify\PasswordExpiryReminder\data.json"
$AppId    = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
$daysUntilExpiry = 10
try {
    if (Test-Path $DataFile) {
        $d = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysUntilExpiry = $d.DaysUntilExpiry
    }
} catch {}
$urgency = if ($daysUntilExpiry -le 3) { "[!] URGENTE - " } else { "" }
$title   = "${urgency}La tua password sta per scadere"
$message = "La password scade tra $daysUntilExpiry giorni. Cambiala il prima possibile."
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $scenario = if ($daysUntilExpiry -le 3) { 'alarm' } else { 'reminder' }
    $toastXml = "<toast scenario=`"$scenario`" activationType=`"foreground`"><visual><binding template=`"ToastGeneric`"><text>$title</text><text>$message</text></binding></visual><actions><action content=`"Cambia password ora`" arguments=`"https://aka.ms/sspr`" activationType=`"protocol`"/><action content=`"Piu tardi`" arguments=`"later`" activationType=`"foreground`"/></actions></toast>"
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast    = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)
} catch { exit 1 }
'@

try {
    if (-not (Test-Path $DataFile)) {
        Write-IntuneLog "data.json not found" -EntryType "Warning"
        exit 0
    }
    $data = Get-Content $DataFile -Raw | ConvertFrom-Json

    Set-Content -Path $NotifyScriptPath -Value $notifyScriptContent -Force -Encoding UTF8

    $currentUser = Get-CurrentInteractiveUser
    if (-not $currentUser) {
        Write-IntuneLog "No interactive user, skipping" -EntryType "Warning"
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

    Write-IntuneLog "Notification scheduled for '$currentUser' ($($data.DaysUntilExpiry) days until expiry)"
    exit 0
} catch {
    Write-IntuneLog "Error: $_" -EntryType "Error"
    exit 1
}