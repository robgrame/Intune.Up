# Pattern: Azioni Service Desk on-demand

## Descrizione

L'Help Desk può eseguire remediation su singolo device on-demand tramite Intune.

## Meccanismo Intune

1. **Run Remediation** – esegue una Intune Remediation specifica su un device
2. **Run Platform Script** – esegue uno script PowerShell su un device (senza detection)

## Problema con detection

Una Intune Remediation on-demand esegue prima la **detection**:
- Se la detection ritorna **compliant (exit 0)** → la remediation **non parte**
- Se la detection ritorna **non-compliant (exit 1)** → la remediation parte

### Pattern consigliato per remediation manuali

```powershell
# detect.ps1 per remediation pensate per uso manuale
# Ritorna sempre non-compliant per garantire l'esecuzione on-demand
exit 1
```

Oppure, per remediation sia automatiche che manuali:
```powershell
# detect.ps1 con doppia modalità
# Se eseguita manualmente (es. via parametro o flag file), salta la check
$manualTriggerFlag = "C:\ProgramData\IntuneUp\manual-trigger\{use-case}.flag"
if (Test-Path $manualTriggerFlag) {
    Remove-Item $manualTriggerFlag -Force
    exit 1  # forza remediation
}
# altrimenti: logica detection normale
```

## Naming convention (aiuta il Service Desk a trovare le remediation)

```
INTUNEUP-MANUAL-<DESCRIZIONE>    # remediation solo manuali
INTUNEUP-SILENT-<DESCRIZIONE>    # remediation automatiche (usabili anche manualmente)
INTUNEUP-UI-<DESCRIZIONE>        # remediation con interazione utente
```

## Tagging / categorizzazione

Usare il campo **Description** della Remediation in Intune per taggare:
```
Category: Manual | Silent | UI
Owner: ServiceDesk | Ops | Security
RunAs: System | User
Description: <cosa fa in plain text per l'operatore>
```

## Workflow Service Desk

1. Operatore riceve ticket con Device ID / Device Name
2. Intune Portal → Devices → cerca device
3. Monitor → Remediations → seleziona remediation da categoria **MANUAL** o **SILENT**
4. Run Remediation → conferma
5. Attendere esecuzione (tipicamente 15-30 minuti per sync policy)
6. Verificare risultato nel report Remediation

## Considerazioni

- Le Platform Scripts non hanno detection → sempre disponibili on-demand
- Per azioni urgenti, preferire Platform Scripts (no dipendenza da detection)
- Documentare sempre cosa fa ogni remediation nel campo Description (visibile in portale)
