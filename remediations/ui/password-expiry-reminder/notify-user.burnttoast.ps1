<#
.SYNOPSIS
    Notifica utente – Password Expiry Reminder (BurntToast)
.DESCRIPTION
    Versione con BurntToast. Richiede modulo BurntToast installato sul client.
    Context: USER (via Scheduled Task)
#>

$UseCase  = "PasswordExpiryReminder"
$DataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"

$daysUntilExpiry = 10
try {
    if (Test-Path $DataFile) {
        $data            = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysUntilExpiry = $data.DaysUntilExpiry
    }
} catch {}

try {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Warning "BurntToast not available, skipping"
        exit 0
    }
    Import-Module BurntToast -ErrorAction Stop

    $urgency = if ($daysUntilExpiry -le 3) { "⚠️ URGENTE – " } else { "" }
    $title   = "${urgency}La tua password sta per scadere"
    $message = "La password scade tra $daysUntilExpiry giorni. Cambiala il prima possibile."

    # Bottone che apre il portale SSPR
    $btnChange = New-BTButton -Content "Cambia password ora" -Arguments "https://aka.ms/sspr" -ActivationType Protocol
    $btnLater  = New-BTButton -Content "Più tardi" -Arguments "later"

    New-BurntToastNotification -Text $title, $message -Button $btnChange, $btnLater
    exit 0
} catch {
    Write-Warning "BurntToast notification failed: $_"
    exit 0
}
