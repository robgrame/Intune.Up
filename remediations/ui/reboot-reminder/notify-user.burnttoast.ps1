<#
.SYNOPSIS
    Notifica utente - Reboot Reminder (BurntToast)
.DESCRIPTION
    Versione con BurntToast. Richiede modulo BurntToast installato sul client.
    Context: USER (via Scheduled Task)
#>

$UseCase  = "RebootReminder"
$DataFile = "C:\ProgramData\IntuneUp\notify\$UseCase\data.json"

$daysSince = 14
try {
    if (Test-Path $DataFile) {
        $data = Get-Content $DataFile -Raw | ConvertFrom-Json
        $daysSince = $data.DaysSinceReboot
    }
} catch {}

try {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Warning "BurntToast not available, skipping notification"
        exit 0
    }
    Import-Module BurntToast -ErrorAction Stop

    $btn1 = New-BTButton -Content "Riavvia ora"              -Arguments "restart-now"
    $btn2 = New-BTButton -Content "Ricordamelo più tardi"    -Arguments "later"

    New-BurntToastNotification `
        -Text "Riavvio richiesto", "Il tuo PC non viene riavviato da $daysSince giorni. Riavvia per applicare gli aggiornamenti." `
        -Button $btn1, $btn2

    exit 0
} catch {
    Write-Warning "BurntToast notification failed: $_"
    exit 0
}
