<#
.SYNOPSIS
    Detection stub per L1 Service Desk – Clear Chrome Settings
.DESCRIPTION
    Ritorna sempre non-compliant per garantire l'esecuzione on-demand da Service Desk.
    La logica di targeting è delegata all'operatore (Run Remediation su device specifico).
    Intune Remediation: INTUNEUP-MANUAL-ClearChromeSettings
    Context: SYSTEM
#>

# Sempre non-compliant: questa remediation è solo on-demand (Service Desk trigger)
Write-Host "Non compliant: on-demand remediation, always triggers"
exit 1
