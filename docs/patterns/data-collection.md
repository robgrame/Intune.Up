# Pattern: Raccolta dati custom → Log Analytics

## Descrizione

Script PowerShell che raccolgono informazioni dal client (senza modificare il sistema)
e le inviano a Log Analytics tramite un collettore Azure intermedio.

## Flusso completo

```
[collect.ps1]  (SYSTEM context, Intune Remediation o Platform Script)
    → raccoglie dati (registry, WMI, file system, stato servizi...)
    → HTTP POST + certificato X.509 client
        ↓
[Azure Function - HTTP trigger]  (entry point)
    → valida thumbprint certificato
    → normalizza payload (aggiunge DeviceId, Timestamp, TenantId)
    → pubblica su Service Bus queue
        ↓
[Azure Service Bus queue]
    → retry automatico in caso di errori downstream
    → Dead Letter Queue per diagnostica
        ↓
[Azure Function - Service Bus trigger]  (processor)
    → deserializza messaggio
    → POST su Log Analytics Data Collector API
        ↓
[Log Analytics Workspace]
    → Custom Log table: IntuneUp_{UseCase}_CL
        ↓
[KQL queries / Azure Workbooks]
```

## Struttura

```
data-collection/scripts/{use-case}/
└── collect.ps1          # Script client-side

data-collection/collector/
├── function-http/       # Azure Function HTTP trigger (entry)
│   ├── run.ps1 / run.cs
│   └── function.json
└── function-sb/         # Azure Function Service Bus trigger (processor)
    ├── run.ps1 / run.cs
    └── function.json
```

## Autenticazione: certificato X.509

### Sul client
- Certificato distribuito via Intune (SCEP o PKCS)
- Lo script carica il certificato dallo store `Cert:\LocalMachine\My`
- Usato come client certificate nella richiesta HTTPS

### Nella Azure Function (HTTP)
- La Function riceve il certificato client dall'header `X-ARR-ClientCert` (se su App Service con client cert enabled)
- Oppure: il client invia il thumbprint nell'header, la Function valida
- La Function controlla il thumbprint contro una allowlist in Application Settings

## Payload standard

```json
{
  "DeviceId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "DeviceName": "HOSTNAME",
  "UPN": "user@contoso.com",
  "Timestamp": "2026-04-15T09:00:00Z",
  "UseCase": "BitLockerStatus",
  "Data": {
    // dati specifici del use case
  }
}
```

## Naming tabelle Log Analytics

```
IntuneUp_{UseCase}_CL
es: IntuneUp_BitLockerStatus_CL
    IntuneUp_RegistryCheck_CL
    IntuneUp_DiskUsage_CL
```

## Scheduling raccolta

Tramite Intune Remediation (detection sempre compliant, remediation raccoglie dati)
oppure Platform Script con schedule.
Frequenza raccomandata: **ogni 4-8 ore** per dati operativi, **1 volta/giorno** per inventario.
