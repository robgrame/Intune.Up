<#
.SYNOPSIS
    Template - Notifica utente via Toast Notification (BurntToast module)
.DESCRIPTION
    Eseguito in contesto UTENTE tramite Scheduled Task creato da remediate-system.ps1.
    Usa il modulo PowerShell BurntToast per Toast Notification ricche.
    Richiede: modulo BurntToast installato sul client (distribuire via Intune Platform Script).
.NOTES
    Context: USER (via Scheduled Task)
    Dipendenza: modulo BurntToast (Install-Module BurntToast)
    Per la versione senza dipendenze, vedere notify-user.xml.ps1
#>

$UseCase = "TODO_USECASE"

# -------------------------------------------------------------------------
# TODO: personalizzare titolo, messaggio e azioni
# -------------------------------------------------------------------------
$ToastTitle   = "Notifica IT – TODO_TITOLO"
$ToastMessage = "TODO_MESSAGGIO_PER_L_UTENTE"
$ToastLogo    = ""   # percorso immagine opzionale (es. "C:\ProgramData\IntuneUp\logo.png")
# -------------------------------------------------------------------------

try {
    # Verifica presenza modulo
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        # Fallback: nessuna notifica ma non fallire (non bloccare la remediation)
        Write-Warning "BurntToast module not available. Skipping notification for $UseCase."
        exit 0
    }

    Import-Module BurntToast -ErrorAction Stop

    $btParams = @{
        Text = $ToastTitle, $ToastMessage
    }

    # Aggiungi logo se disponibile
    if ($ToastLogo -and (Test-Path $ToastLogo)) {
        $btParams['AppLogo'] = $ToastLogo
    }

    # TODO: aggiungere bottoni se necessario
    # $button1 = New-BTButton -Content "Riavvia ora" -Arguments "restart"
    # $button2 = New-BTButton -Content "Più tardi"   -Arguments "later"
    # $btParams['Button'] = $button1, $button2

    New-BurntToastNotification @btParams
    exit 0

} catch {
    Write-Warning "BurntToast notification failed for $UseCase`: $_"
    # Non bloccare: la remediation tecnica è già avvenuta
    exit 0
}
