<#
.SYNOPSIS
    Template - Detection script per Intune Remediation (Silent)
.DESCRIPTION
    Verifica se la condizione che richiede remediation è presente.
    Exit 0 = compliant (remediation non eseguita)
    Exit 1 = non compliant (remediation eseguita)
.NOTES
    Naming:  ENEL-SILENT-<UseCase>
    Context: SYSTEM
    Replace: TODO_USECASE con il nome del use case
#>

$ErrorActionPreference = "Stop"
$UseCase = "TODO_USECASE"

try {

    # -------------------------------------------------------------------------
    # TODO: inserire qui la logica di detection
    # Esempio: verificare se un servizio è in stato anomalo
    # -------------------------------------------------------------------------
    # $service = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    # if ($service.Status -ne "Running") {
    #     Write-Host "Non compliant: service not running"
    #     exit 1
    # }
    # -------------------------------------------------------------------------

    Write-Host "Compliant: $UseCase check passed"
    exit 0

} catch {
    # In caso di errore nella detection, considerare non compliant
    Write-Warning "Detection error for $UseCase`: $_"
    exit 1
}
