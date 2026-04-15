<#
.SYNOPSIS
    Template - Remediation script per Intune Remediation (Silent)
.DESCRIPTION
    Esegue l'azione correttiva. Deve essere idempotente.
    Exit 0 = successo
    Exit 1 = fallimento
.NOTES
    Naming:  ENEL-SILENT-<UseCase>
    Context: SYSTEM
    Replace: TODO_USECASE con il nome del use case
#>

$ErrorActionPreference = "Stop"
$UseCase   = "TODO_USECASE"
$EventLog  = "Application"
$EventSource = "IntuneUp"

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName $EventLog -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName $EventLog -Source $EventSource -EntryType $EntryType `
            -EventId 1000 -Message "[$UseCase] $Message"
    } catch {
        Write-Warning "EventLog write failed: $_"
    }
}

try {

    Write-IntuneLog "Remediation started"

    # -------------------------------------------------------------------------
    # TODO: inserire qui la logica di remediation
    # Esempio: riavviare un servizio
    # -------------------------------------------------------------------------
    # Restart-Service -Name "wuauserv" -Force
    # -------------------------------------------------------------------------

    Write-IntuneLog "Remediation completed successfully"
    Write-Host "Success: $UseCase remediation completed"
    exit 0

} catch {
    Write-IntuneLog "Remediation failed: $_" -EntryType "Error"
    Write-Error "Failed: $UseCase remediation error: $_"
    exit 1
}
