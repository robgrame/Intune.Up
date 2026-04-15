# Pattern: Remediation Silent

## Descrizione

Remediation automatica, silenziosa, senza interazione utente.
Eseguita in contesto **SYSTEM** tramite Intune Remediations.

## Struttura

```
remediations/silent/{use-case}/
├── detect.ps1       # Detection script
└── remediate.ps1    # Remediation script
```

## Naming convention

```
<CLIENTE>-<CATEGORIA>-<DESCRIZIONE>
es: ENEL-SILENT-WMIRepair
    ENEL-SILENT-CleanupTemp
    ENEL-SILENT-SCCMAgentFix
```

## Tagging Intune (Description field)

```
Category: Silent
Owner: <team>
Version: 1.0
UseCase: <descrizione breve>
```

## Regole detect.ps1

- Exit code **0** = compliant (remediation NON eseguita)
- Exit code **1** = non compliant (remediation eseguita)
- Non deve mai throw uncatched exceptions
- Usare `try/catch` con exit code espliciti

## Regole remediate.ps1

- Exit code **0** = successo
- Exit code **1** = fallimento
- Loggare su Windows Event Log per diagnostica
- Idempotente: eseguibile più volte senza effetti collaterali

## Scheduling

Configurato nella policy Intune:
- **Every 15 min / 1 hour / 8 hours / 1 day** (selezionabile)
- Per azioni critiche: 1 ora o meno
- Per pulizie/manutenzione: 1 giorno

## On-demand (Service Desk)

Vedi pattern [service-desk.md](service-desk.md).
Attenzione: la detection deve essere soddisfatta per l'esecuzione on-demand.
Per remediation puramente manuali, usare una detection che ritorna sempre non-compliant.
