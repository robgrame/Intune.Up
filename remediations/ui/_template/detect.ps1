<#
.SYNOPSIS
    Template - Detection script per Intune Remediation con UI utente
.DESCRIPTION
    Verifica se la condizione che richiede remediation (e notifica utente) è presente.
    Exit 0 = compliant
    Exit 1 = non compliant → esegue remediate-system.ps1
.NOTES
    Naming:  INTUNEUP-UI-<UseCase>
    Context: SYSTEM
#>

$ErrorActionPreference = "Stop"
$UseCase = "TODO_USECASE"

try {

    # -------------------------------------------------------------------------
    # TODO: inserire qui la logica di detection
    # -------------------------------------------------------------------------

    Write-Host "Compliant: $UseCase"
    exit 0

} catch {
    Write-Warning "Detection error for $UseCase`: $_"
    exit 1
}
