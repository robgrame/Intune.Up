<#
.SYNOPSIS
    Azure Automation Runbook – Password Expiry Trigger Writer
.DESCRIPTION
    Runbook lato server (Azure Automation) che:
    1. Interroga Active Directory (on-prem via Hybrid Worker) o Microsoft Graph (Entra ID)
       per trovare gli utenti con password in scadenza entro ThresholdDays giorni.
    2. Per ogni device associato a quegli utenti, scrive un trigger file via Intune
       (Graph API – Platform Script o Device Configuration) oppure direttamente
       tramite Run Script on device.
    3. Il trigger file viene letto dalla Remediation INTUNEUP-UI-PasswordExpiryReminder.

    Scheduling: giornaliero (Azure Automation Schedule)
    Prerequisiti:
      - Azure Automation Account con Managed Identity
      - Ruolo: Intune Administrator (o Graph DeviceManagementManagedDevices.ReadWrite.All)
      - Per AD on-prem: Hybrid Runbook Worker con accesso al domain controller
      - App Setting: THRESHOLD_DAYS (default 10)
#>

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.DeviceManagement

param(
    [int]$ThresholdDays = 10
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Autenticazione tramite Managed Identity dell'Automation Account
# ---------------------------------------------------------------------------
Connect-MgGraph -Identity -NoWelcome

# ---------------------------------------------------------------------------
# Recupero utenti con password in scadenza (Entra ID / cloud-only)
# ---------------------------------------------------------------------------
# Nota: per hybrid/on-prem, sostituire con Get-ADUser -Filter {Enabled -eq $true} |
#       Select PasswordLastSet, msDS-UserPasswordExpiryTimeComputed, ecc.

$today      = (Get-Date).ToUniversalTime()
$targetDate = $today.AddDays($ThresholdDays)

Write-Output "Querying users with password expiry before $($targetDate.ToString('yyyy-MM-dd'))"

$users = Get-MgUser -All `
    -Property "id,userPrincipalName,passwordPolicies,passwordProfile,onPremisesExtensionAttributes" `
    -Filter "accountEnabled eq true" |
    Where-Object {
        # Per cloud-only: verificare la data di scadenza password tramite Get-MgUserAuthenticationMethod
        # o tramite lastPasswordChangeDateTime + policy di scadenza.
        # Placeholder: sostituire con la logica specifica dell'ambiente.
        $true  # TODO: filtrare utenti con scadenza < ThresholdDays
    }

Write-Output "Found $($users.Count) candidate users (TODO: apply real expiry filter)"

# ---------------------------------------------------------------------------
# Per ogni utente, trova il device Intune e scrivi il trigger via Run Script
# ---------------------------------------------------------------------------
foreach ($user in $users) {
    try {
        # Trova i managed device dell'utente
        $devices = Get-MgUserManagedDevice -UserId $user.Id -ErrorAction SilentlyContinue
        if (-not $devices) {
            Write-Warning "No managed devices for $($user.UserPrincipalName), skipping"
            continue
        }

        # Calcola giorni alla scadenza (placeholder – adattare alla fonte dati reale)
        $daysUntilExpiry = $ThresholdDays - 1  # TODO: calcolo reale

        $triggerPayload = @{
            DaysUntilExpiry = $daysUntilExpiry
            UserUPN         = $user.UserPrincipalName
            WrittenAt       = $today.ToString("o")
        } | ConvertTo-Json -Compress

        # Script da eseguire sul device per scrivere il trigger file
        $writeScript = @"
`$dir = 'C:\ProgramData\IntuneUp\triggers'
if (-not (Test-Path `$dir)) { New-Item -ItemType Directory -Path `$dir -Force | Out-Null }
Set-Content -Path "`$dir\PasswordExpiryReminder.json" -Value '$triggerPayload' -Force -Encoding UTF8
"@

        foreach ($device in $devices) {
            # Esegui script tramite Graph API (Intune Run Script)
            # Nota: per produzione, usare Invoke-MgGraphRequest con l'endpoint appropriato
            # o caricare il trigger tramite Intune Configuration Profile (Custom OMA-URI)
            Write-Output "Writing trigger to device: $($device.DeviceName) for user: $($user.UserPrincipalName)"

            # TODO: chiamata Graph API per Run Script su device specifico
            # POST /deviceManagement/managedDevices/{deviceId}/runSummary (o tramite deviceShellScript)
        }

    } catch {
        Write-Warning "Error processing user $($user.UserPrincipalName): $_"
    }
}

Write-Output "Trigger writing completed"
Disconnect-MgGraph
