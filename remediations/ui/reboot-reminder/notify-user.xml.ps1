<#
.SYNOPSIS
    Notifica utente – Reboot Reminder (XML Toast nativo, no dipendenze)
.DESCRIPTION
    Mostra una Toast Notification che chiede all'utente di riavviare il PC.
    Legge i giorni dall'ultimo reboot dal file data.json passato da remediate-system.ps1.
    Context: USER (via Scheduled Task)
#>

$UseCase  = "RebootReminder"
$DataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"
$AppId    = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

# Leggi giorni dall'ultimo reboot
$daysSince = 14
try {
    if (Test-Path $DataFile) {
        $data = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysSince = $data.DaysSinceReboot
    }
} catch {}

$title   = "Riavvio richiesto"
$message = "Il tuo PC non viene riavviato da $daysSince giorni. Il riavvio è necessario per installare aggiornamenti e migliorare le prestazioni."

try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

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
    <action content="Ricordamelo più tardi" arguments="later" activationType="foreground"/>
  </actions>
</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast    = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)

    # Nota: per gestire la risposta dell'utente (es. "Riavvia ora" → eseguire shutdown /r /t 60)
    # è necessario un listener separato. In Intune, il pattern semplificato è:
    # mostrare la notifica e lasciare che l'utente agisca manualmente.
    # Per reboot forzato con ritardo, aggiungere: Start-Sleep 5; shutdown /r /t 300

    exit 0
} catch {
    Write-Warning "Toast notification failed: $_"
    exit 1
}
