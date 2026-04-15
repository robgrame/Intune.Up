# Architettura Target – Intune.Up

## Contesto

ENEL utilizza Nexthink per remediation automatiche, raccolta dati custom, campagne utente e azioni Service Desk.
Obiettivo: replicare e superare queste funzionalità con **Microsoft Intune + Azure**.

---

## Decisioni architetturali

| # | Ambito | Decisione |
|---|--------|-----------|
| 1 | Collettore dati | Azure Function HTTP trigger (entry) → Service Bus → Azure Function SB trigger (processor) |
| 2 | Auth client→collettore | Certificato client X.509 (thumbprint validato dalla HTTP Function) |
| 3 | Notifica utente | Due template: BurntToast (PS module) + XML Toast nativo. Il cliente sceglie. |
| 4 | AI integration | Da analizzare con bot Teams esistente ENEL (Bot Framework / Azure Bot Service?) |

---

## Componenti

### Intune

- **Remediations** (Detection + Remediation script)
  - Contesto: SYSTEM
  - Schedule: configurabile per policy
  - On-demand: Run Remediation (Service Desk)
- **Platform Scripts**
  - Usati per logica USER context (notifiche)

### Azure

| Componente | Scopo |
|-----------|-------|
| Azure Function (HTTP trigger) | Entry point raccolta dati, valida cert client |
| Azure Service Bus | Disaccoppiamento, retry automatico, Dead Letter Queue |
| Azure Function (SB trigger) | Elaborazione messaggi, scrittura su Log Analytics |
| Log Analytics Workspace | Storage dati custom, KQL, retention configurabile |
| Azure Monitor Workbooks | Reportistica strutturata e condivisibile |

---

## Flussi

### Remediation silent

```
[Intune Policy]
    → schedule / compliance check
    → [detect.ps1] eseguito in SYSTEM
        → se non compliant: [remediate.ps1] in SYSTEM
            → log risultato (Event Log o output)
```

### Remediation con UI utente

```
[Intune Policy]
    → [detect.ps1] in SYSTEM
        → se non compliant: [remediate-system.ps1] in SYSTEM
            → crea Scheduled Task one-time in USER context
                → [notify-user.ps1] → Toast Notification
                    → utente interagisce (opzionale)
                        → Scheduled Task si auto-rimuove
```

### Raccolta dati custom

```
[Intune Remediation / Platform Script]
    → [collect.ps1] in SYSTEM
        → HTTP POST + certificato X.509
            → [Azure Function HTTP trigger]
                → valida thumbprint certificato
                → enqueue su Service Bus
                    → [Azure Function SB trigger]
                        → normalizza payload
                        → POST su Log Analytics Data Collector API
                            → [Custom Log Table]
                                → KQL / Workbooks
```

### Azione Service Desk on-demand

```
[Intune Admin / Help Desk]
    → Intune Portal: Run Remediation su device specifico
        → [detect.ps1] → detection forzata (ritorna always-non-compliant per trigger manuale)
            → [remediate.ps1] eseguito
```

---

## Sicurezza

- Client non scrivono mai direttamente su Log Analytics
- Certificato X.509 generato e distribuito via Intune (SCEP/PKCS)
- Azure Function valida thumbprint contro lista allowlist in configurazione
- Service Bus accesso tramite Managed Identity della Function
- Log Analytics: scrittura solo dalla SB Function (Managed Identity)

---

## Reportistica

- **Retention:** default 30 giorni (Log Analytics), estendibile a pagamento
- **Query:** KQL direttamente in Log Analytics
- **Report semplici:** Log Analytics queries salvate
- **Report strutturati:** Azure Monitor Workbooks (JSON, condivisibili)
- **Export/archivio:** eventuale Data Lake via Diagnostic Settings

---

## AI Assistant (futuro)

ENEL dispone di un bot AI già deployato su Teams.
Da investigare:
- Tecnologia del bot (Bot Framework? Power Virtual Agents? Azure OpenAI + bot?)
- Supporto per tool/function calling o plugin
- Possibilità di esporre un **MCP server** come capability layer:
  - Il bot chiama MCP per scoprire le azioni disponibili
  - MCP mappa le capability a remediation/runbook specifici
  - Autenticazione delegata tramite il contesto utente Teams
