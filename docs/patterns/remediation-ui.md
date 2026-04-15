# Pattern: Remediation con UI utente

## Descrizione

Remediation che richiede interazione o notifica verso l'utente.
Usa un pattern **dual-context**: azione tecnica in SYSTEM, notifica in USER context.

## Problema

Intune Remediations girano in contesto SYSTEM.
SYSTEM non può mostrare UI all'utente corrente (sessione interattiva separata).

## Soluzione: dual-context via Scheduled Task

```
[remediate-system.ps1]  (SYSTEM context)
    → esegue azione tecnica
    → crea Scheduled Task one-time nel profilo utente corrente
        ↓
[notify-user.ps1]  (USER context, via Scheduled Task)
    → mostra Toast Notification
    → l'utente può interagire (es. "Riavvia ora" / "Più tardi")
    → Scheduled Task si auto-rimuove dopo esecuzione
```

## Struttura

```
remediations/ui/{use-case}/
├── detect.ps1               # Detection (SYSTEM)
├── remediate-system.ps1     # Azione tecnica + crea Scheduled Task (SYSTEM)
└── notify-user.ps1          # Notifica UI (USER context)
```

## Due implementazioni di notify-user.ps1

Il cliente può scegliere:

| Approccio | File | Pro | Contro |
|-----------|------|-----|--------|
| **BurntToast** | `notify-user.burnttoast.ps1` | Semplice, customizzabile, bottoni nativi | Dipendenza modulo PS (da distribuire) |
| **XML Toast nativo** | `notify-user.xml.ps1` | Nessuna dipendenza, funziona su Windows 10/11 | Più verboso, API Windows diretta |

## Trovare l'utente corrente (da SYSTEM)

```powershell
$currentUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
# oppure
$currentUser = (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
    Select-Object -First 1).UserName
```

## Creare lo Scheduled Task (da SYSTEM per USER)

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
               -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$notifyScript`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 60)

Register-ScheduledTask -TaskName "IntuneUp-Notify-$([guid]::NewGuid())" `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
```

## Naming convention

```
ENEL-UI-<DESCRIZIONE>
es: ENEL-UI-RebootReminder
    ENEL-UI-OneDriveRestart
    ENEL-UI-PasswordReminder
```
