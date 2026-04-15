<#
.SYNOPSIS
    Notifica utente – Password Expiry Reminder (XML Toast nativo)
.DESCRIPTION
    Mostra una Toast Notification che avvisa l'utente della scadenza imminente
    della password e lo invita a cambiarla.
    Context: USER (via Scheduled Task)
#>

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

$urgency = if ($daysUntilExpiry -le 3) { "⚠️ URGENTE – " } else { "" }
$title   = "${urgency}La tua password sta per scadere"
$message = "La password scade tra $daysUntilExpiry giorni. Cambiala il prima possibile per evitare interruzioni di accesso."

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
    <action content="Cambia password ora" arguments="change-password" activationType="protocol" activationUri="https://aka.ms/sspr"/>
    <action content="Ricordamelo più tardi" arguments="later" activationType="foreground"/>
  </actions>
</toast>
"@
    # Nota: il link punta a Azure AD Self-Service Password Reset (SSPR).
    # Personalizzare l'URL con il portale SSPR aziendale se diverso.

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast    = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)
    exit 0
} catch {
    Write-Warning "Toast notification failed: $_"
    exit 1
}
