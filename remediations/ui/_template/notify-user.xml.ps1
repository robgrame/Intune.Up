<#
.SYNOPSIS
    Template - Notifica utente via Toast Notification (XML nativo Windows)
.DESCRIPTION
    Eseguito in contesto UTENTE tramite Scheduled Task creato da remediate-system.ps1.
    Mostra una Toast Notification nativa Windows senza dipendenze esterne.
    Compatibile con Windows 10 1803+ e Windows 11.
.NOTES
    Context: USER (via Scheduled Task)
    No dipendenze: usa solo API Windows native
    Per la versione con BurntToast, vedere notify-user.burnttoast.ps1
#>

$UseCase     = "TODO_USECASE"
$AppId       = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

# -------------------------------------------------------------------------
# TODO: personalizzare titolo, messaggio e azioni
# -------------------------------------------------------------------------
$ToastTitle   = "Notifica IT - TODO_TITOLO"
$ToastMessage = "TODO_MESSAGGIO_PER_L_UTENTE"
$ToastLogo    = ""   # percorso immagine locale opzionale (es. logo aziendale)
# -------------------------------------------------------------------------

function Show-ToastNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$AppId,
        [string]$LogoPath = ""
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $logoXml = if ($LogoPath -and (Test-Path $LogoPath)) {
        "<image placement='appLogoOverride' src='file:///$LogoPath'/>"
    } else { "" }

    $toastXml = @"
<toast activationType="foreground">
  <visual>
    <binding template="ToastGeneric">
      $logoXml
      <text>$Title</text>
      <text>$Message</text>
    </binding>
  </visual>
  <actions>
    <action content="OK" arguments="ok" activationType="foreground"/>
  </actions>
</toast>
"@
    # TODO: aggiungere bottoni aggiuntivi se necessario, es:
    # <action content="Riavvia ora" arguments="restart" activationType="foreground"/>
    # <action content="Più tardi" arguments="later" activationType="foreground"/>

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)
}

try {
    Show-ToastNotification -Title $ToastTitle -Message $ToastMessage -AppId $AppId -LogoPath $ToastLogo
    exit 0
} catch {
    Write-Warning "Toast notification failed: $_"
    exit 1
}
