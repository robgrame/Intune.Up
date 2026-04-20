# Test Client - Intune.Up HTTP Function

Script di simulazione client che invia report di inventario device alla HTTP function con validazione mTLS.

## ⚡ Quick Start

### Per Dev/Test Environment (auto-setup):

```powershell
.\test-client.ps1 -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
  -ResourceGroup "rg-intuneup-prod" `
  -FunctionAppName "func-intuneup-http-prod" `
  -KeyVaultName "kv-intuneup-prod"
```

Lo script fa tutto automaticamente:
1. ✅ Crea/usa certificato self-signed
2. ✅ Lo registra in Key Vault come CA autorizzata
3. ✅ Recupera la function key
4. ✅ Invia il payload

### Per Produzione (con certificato PKI):

```powershell
# Prerequisiti:
# 1. Certificato PKI già installato in Cert:\LocalMachine\My
# 2. CA del certificato già in AllowedIssuerThumbprints (Key Vault)
# 3. Function key già recuperata

$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*YourCompany*" }
$functionKey = "your-function-key"

$payload = @{
    DeviceId = "DEVICE-001"
    DeviceName = "LAPTOP-USER1"
    UseCase = "DeviceInventory"
    Data = @{
        OS = @{ Name = "Windows 11"; Build = "22621" }
        Hardware = @{ ProcessorCount = 8; TotalMemoryGB = 16 }
    }
} | ConvertTo-Json

Invoke-WebRequest `
    -Uri "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -Method Post `
    -Certificate $cert `
    -Headers @{ "x-functions-key" = $functionKey } `
    -ContentType "application/json" `
    -Body $payload
```

---

## Requisiti

- PowerShell 5.1+ o PowerShell Core 7+
- Accesso a `Cert:\CurrentUser\My` per certificati
- HTTPS endpoint della function
- Credenziali Azure CLI (`az login`)

## Utilizzo Rapido

### Dev Environment

```powershell
# Test locale con endpoint dev
.\test-client.ps1 -FunctionUrl "https://func-intuneup-http-dev.azurewebsites.net/api/collect"
```

### Prod Environment

```powershell
# Test su prod con payload di 100 KB
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -ResourceGroup "rg-intuneup-prod" `
    -FunctionAppName "func-intuneup-http-prod" `
    -KeyVaultName "kv-intuneup-prod" `
    -PayloadSizeKB 100
```

## Parametri

| Parametro | Obbligatorio | Default | Descrizione |
|-----------|-------------|---------|-------------|
| `FunctionUrl` | ✅ Sì | - | URL endpoint della HTTP function (https://) |
| `ResourceGroup` | No | - | Resource group Azure (per recuperare function key) |
| `FunctionAppName` | No | - | Nome della function app (per recuperare function key) |
| `KeyVaultName` | No | - | Nome del Key Vault (per registrare certificato) |
| `DeviceId` | No | DEVICE-{random} | ID del device (deve essere univoco) |
| `DeviceName` | No | TEST-PC-{random} | Nome del device Windows |
| `UseCase` | No | DeviceInventory | Categoria del report |
| `PayloadSizeKB` | No | 50 | Dimensione approssimativa del payload (KB) |
| `SkipCertSetup` | No | $false | Se $true, salta setup certificato (lo usa già esistente) |

## Esempi

### 1. Test Semplice - Payload Piccolo
```powershell
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect"
```
**Output:** Device virtuale con inventario base (~50 KB), certificato auto-generato

### 2. Test Claim-Check Pattern (>200 KB)
```powershell
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -PayloadSizeKB 300 `
    -DeviceName "LAPTOP-LARGEDATA" `
    -UseCase "ExtendedInventory" `
    -SkipCertSetup
```
**Output:** Payload >200 KB viene salvato in Blob Storage, referenza inviata in Service Bus

### 3. Test Multipli Device in Loop
```powershell
for ($i = 1; $i -le 5; $i++) {
    .\test-client.ps1 `
        -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
        -DeviceId "DEVICE-$i" `
        -DeviceName "TESTPC-$i" `
        -SkipCertSetup
    
    Start-Sleep -Seconds 2
}
```

### 4. Con Setup Completo (Azure CLI + KV)
```powershell
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -ResourceGroup "rg-intuneup-prod" `
    -FunctionAppName "func-intuneup-http-prod" `
    -KeyVaultName "kv-intuneup-prod" `
    -PayloadSizeKB 150 `
    -DeviceName "PROD-DEVICE-01"
```

Lo script automaticamente:
- Genera o recupera certificato
- Lo registra in Key Vault
- Recupera la function key
- Invia il payload con headers corretti

## Cosa fa lo Script

### 1️⃣ Setup Certificato
```
┌─────────────────┐
│ Check Local Cert│  Cerca certificato "IntuneUp-Collector"
└────────┬────────┘
         │
         ├─ Esiste?
         │   └─ Usa quello ✅
         │
         └─ Non esiste?
            └─ Crea self-signed ✅
```

### 2️⃣ Registra in Key Vault
```
Certificato Thumbprint:
    │
    ├─ KV Name fornito?
    │   └─ Aggiungi a AllowedIssuerThumbprints ✅
    │
    └─ No? Skip ⚠️
```

### 3️⃣ Recupera Function Key
```
Azure CLI →  Get Function App Keys
    │
    ├─ Success? Usa quella ✅
    │
    └─ Fail? Continua senza (manuale dopo) ⚠️
```

### 4️⃣ Test Connessione
```
HEAD {FunctionUrl}
  │
  ├─ Success? Connessione OK ✅
  │
  └─ Fail? Warning ma continua ⚠️
```

### 5️⃣ Invia Payload
```
POST {FunctionUrl}
Headers:
  - Content-Type: application/json
  - x-functions-key: {FunctionKey}  (se disponibile)
  - TLS Client Cert: {Certificate}

Body: Inventario Device (JSON)
  │
  ├─ Function valida certificato vs Key Vault
  │   └─ Thumbprint CA verificato ✅
  │
  ├─ Response 202 Accepted
  │   └─ Enqueue in Service Bus ✅
  │
  └─ Response 401 Unauthorized
      └─ Certificato non autorizzato ❌
```

### 6️⃣ Enqueue in Service Bus
```
Se Payload <= 200 KB:
  ├─ Invia direttamente in coda ✅
  └─ Lato receiver: processa subito

Se Payload > 200 KB:
  ├─ Salva in Blob Storage
  │   └─ {UseCase}/yyyy/MM/dd/{MessageId}.json
  │
  └─ Invia claim-check in coda ✅
      └─ Lato receiver: recupera da Blob
```

## Output Atteso

### ✅ Successo (202 Accepted)

```
============================================================
 Intune.Up - Test Client Simulator
============================================================

📍 Configuration:
   Function URL   : https://func-intuneup-http-prod.azurewebsites.net/api/collect
   Device ID      : DEVICE-5678
   Device Name    : TEST-INVENTORY-01
   Use Case       : DeviceInventory
   Payload Size   : ~80 KB

♻️  Using existing certificate
   Thumbprint: 3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66
   Subject: CN=IntuneUp-Collector

🔐 Registering certificate in Key Vault...
   Adding thumbprint: 3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66
✅ Certificate registered in Key Vault
   Total allowed thumbprints: 3

🔑 Retrieving function key...
✅ Function key retrieved

🔗 Testing connection to function...
✅ Connection successful (HTTP 200)

📤 Sending telemetry payload...
   Payload size: 81920 bytes (80.00 KB)

✅ Payload accepted (HTTP 202)
   Response: {"status":"accepted"}

✅ Test completed successfully!

📊 Summary:
   Certificate Thumbprint : 3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66
   Device ID              : DEVICE-5678
   Message Status         : Accepted (202)

💡 Next steps:
   1. Check function logs in App Insights
   2. Verify message in Service Bus queue
   3. Check if payload was stored in blob (if >200KB)
```

### ❌ Certificato non Autorizzato (401)

```
❌ Request failed: Response status code does not indicate success: 401 (Unauthorized).
   Error body: {"error":"Unauthorized - valid client certificate required"}

💡 Manual certificate registration:
   Run this command to authorize the certificate:
   az keyvault secret set --vault-name kv-intuneup-prod --name AllowedIssuerThumbprints --value '3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66'
```

**Risoluzione:**
```powershell
# Ottieni il thumbprint
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" }

# Registra manualmente (richiede KV edit permissions)
az keyvault secret set `
  --vault-name kv-intuneup-prod `
  --name AllowedIssuerThumbprints `
  --value $cert.Thumbprint
```

### ❌ Function Key Non Trovata

```
🔑 Retrieving function key...
⚠️  Could not retrieve function key: ...
```

**Risoluzione:**
```powershell
# Recupera manualmente
$functionKey = az functionapp keys list `
  -g rg-intuneup-prod `
  -n func-intuneup-http-prod `
  --query "functionKeys.default" -o tsv

Write-Host $functionKey
```

## Validazione in Azure

### 1. Verificare i Log della Function

```bash
# Vedere i log dell'HTTP function
az monitor app-insights query \
  --apps appi-intuneup-prod \
  --analytics-query "traces | where message contains 'Certificate' or message contains 'Accepted' | top 10 by timestamp desc"
```

### 2. Verificare il Message in Service Bus

```bash
# Contare i messaggi nella coda
az servicebus queue show \
  --namespace-name sb-intuneup-prod \
  --name device-telemetry \
  --resource-group rg-intuneup-prod \
  --query "messageCount"

# Ricevere un messaggio per ispezionarlo
az servicebus queue-authorization-rule keys list \
  --namespace-name sb-intuneup-prod \
  --queue-name device-telemetry \
  --name RootManageSharedAccessKey \
  --query "primaryConnectionString" -o tsv
```

### 3. Verificare il Blob (se >200 KB)

```bash
# Elencare blob nel container claim-check
az storage blob list \
  --account-name stintuneupclaimcheckprod \
  --container-name claim-check \
  --auth-mode login
```

## Troubleshooting

| Errore | Causa | Soluzione |
|--------|-------|----------|
| **401 Unauthorized** | Certificato non nel AllowedIssuerThumbprints | Eseguire `az keyvault secret set ...` con il thumbprint del certificato |
| **404 Not Found** (HEAD) | Endpoint URL errata | Verificare URL della function in App Service settings |
| **403 Forbidden** | Permessi Key Vault insufficienti | Far aggiungere thumbprint da admin oppure usare `-SkipCertSetup` |
| **Timeout** | Payload troppo grande | Ridurre `PayloadSizeKB` a 100-200 KB |
| **No certificate provided** | Certificato non passato | Verificare che App Service ha `clientCertEnabled: true` ✅ (già fatto nel Bicep) |

## Security Notes

✅ **Best Practices Implementate:**
- mTLS con validazione CA
- Certificato self-signed solo per testing
- No hardcoded credentials
- Payload validation lato server
- Logging degli accessi
- Claim-check per payload grandi

⚠️ **Per Produzione Real:**
- Usare certificati PKI aziendale (non self-signed)
- Distribuire via Intune certificate deployment
- Ruotare certificati periodicamente
- Abilitare Certificate Revocation Check
- Monitorare accessi non autorizzati
- Implementare rate limiting
- Cifrazione at-rest dei dati in Blob/SB

## Parametri

| Parametro | Obbligatorio | Default | Descrizione |
|-----------|-------------|---------|-------------|
| `FunctionUrl` | ✅ Sì | - | URL endpoint della HTTP function (https://) |
| `DeviceId` | No | DEVICE-{random} | ID del device (deve essere univoco) |
| `DeviceName` | No | TEST-PC-{random} | Nome del device Windows |
| `UseCase` | No | DeviceInventory | Categoria del report (es. InventoryReport, SecurityUpdate) |
| `PayloadSizeKB` | No | 50 | Dimensione approssimativa del payload (KB) |

## Esempi

### 1. Test Semplice - Payload Piccolo
```powershell
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect"
```
**Output:** Device virtuale con inventario base (~50 KB), certificato auto-generato

### 2. Test Claim-Check Pattern (>200 KB)
```powershell
.\test-client.ps1 `
    -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -PayloadSizeKB 300 `
    -DeviceName "LAPTOP-LARGEDATA" `
    -UseCase "ExtendedInventory"
```
**Output:** Payload >200 KB viene salvato in Blob Storage, referenza inviata in Service Bus

### 3. Test Multipli Device in Loop
```powershell
for ($i = 1; $i -le 5; $i++) {
    .\test-client.ps1 `
        -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
        -DeviceId "DEVICE-$i" `
        -DeviceName "TESTPC-$i"
    
    Start-Sleep -Seconds 2  # Spacing tra richieste
}
```
**Output:** 5 device diversi inviano report

### 4. Stress Test
```powershell
# 10 richieste parallele
1..10 | ForEach-Object {
    & {
        .\test-client.ps1 `
            -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
            -DeviceId "STRESS-TEST-$_"
    } &
}
Wait-Job *
```
**Output:** Valida scalabilità della function

## Cosa fa lo Script

### 1️⃣ Setup Certificato
```
┌─────────────────┐
│ Check Local Cert│  Cerca certificato "IntuneUp-Collector"
└────────┬────────┘
         │
         ├─ Esiste?
         │   └─ Usa quello ✅
         │
         └─ Non esiste?
            └─ Crea self-signed ✅
```

### 2️⃣ Test Connessione
```
HEAD {FunctionUrl}
  │
  ├─ 200-299? Connessione OK ✅
  │
  └─ Error?  Warningma continua ⚠️
```

### 3️⃣ Genera Payload Inventario
```
{
  "DeviceId": "DEVICE-1234",
  "DeviceName": "TEST-PC-567",
  "UseCase": "DeviceInventory",
  "Data": {
    "OS": { "Name": "Windows 11", "Build": "22621" },
    "Hardware": { "ProcessorCount": 8, "TotalMemoryGB": 16 },
    "Network": { ... },
    "InstalledApplications": [...],
    "AntiVirus": { ... },
    "SecurityUpdates": { ... },
    "Padding": { ... }  // Per raggiungere PayloadSizeKB
  }
}
```

### 4️⃣ POST con mTLS
```
POST {FunctionUrl}
Content-Type: application/json
[Client Certificate in TLS handshake]

{DeviceId, DeviceName, UseCase, Data}
  │
  ├─ Validazione Certificato sulla function
  │   └─ Thumbprint CA verificato vs Key Vault
  │
  └─ Response 202 Accepted ✅
```

### 5️⃣ Enqueue in Service Bus
```
Se Payload <= 200 KB:
  ├─ Invia direttamente in coda ✅

Se Payload > 200 KB:
  ├─ Salva in Blob Storage
  │   └─ {UseCase}/yyyy/MM/dd/{MessageId}.json
  │
  └─ Invia claim-check in coda ✅
```

## Output Atteso

### Successo (202 Accepted)

```
============================================================
 Intune.Up - Test Client Simulator
============================================================

📍 Configuration:
   Function URL   : https://func-intuneup-http-prod.azurewebsites.net/api/collect
   Device ID      : DEVICE-5678
   Device Name    : TEST-PC-234
   Use Case       : DeviceInventory
   Payload Size   : ~50 KB

♻️  Using existing certificate
   Thumbprint: 3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66
   Subject: CN=IntuneUp-Collector

🔗 Testing connection to function...
✅ Connection successful (HTTP 200)

📤 Sending telemetry payload...
   Payload size: 51200 bytes (50.00 KB)

✅ Payload accepted (HTTP 202)
   Response: {"status":"accepted"}

✅ Test completed successfully!

📊 Summary:
   Certificate Thumbprint : 3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66
   Device ID              : DEVICE-5678
   Message Status         : Accepted (202)

💡 Next steps:
   1. Check function logs in App Insights
   2. Verify message in Service Bus queue
   3. Check if payload was stored in blob (if >200KB)
```

### Errore di Certificato (401 Unauthorized)

```
❌ Request failed: The remote server returned an error: (401) Unauthorized.
   Error body: {"error":"Unauthorized - valid client certificate required"}
```

**Risoluzione:**
- Verificare che il certificato è installato in `Cert:\CurrentUser\My`
- Verificare che il thumbprint della CA è in Key Vault `AllowedIssuerThumbprints`
- Controllare che la CA è nella catena X.509 del certificato

## Validazione in Azure

### 1. Verificare i Log della Function

```bash
# Vedere i log dell'HTTP function
az monitor app-insights query \
  --apps appi-intuneup-prod \
  --analytics-query "traces | where message contains 'Certificate' or message contains 'Accepted' | top 10 by timestamp desc"
```

### 2. Verificare il Message in Service Bus

```bash
# Contare i messaggi nella coda
az servicebus queue show \
  --namespace-name sb-intuneup-prod \
  --name device-telemetry \
  --resource-group rg-intuneup-prod \
  --query "messageCount"
```

### 3. Verificare il Blob (se >200 KB)

```bash
# Elencare blob nel container claim-check
az storage blob list \
  --account-name stintuneupclaimcheckprod \
  --container-name claim-check \
  --auth-mode login
```

## Troubleshooting

### ❌ "No client certificate provided"

La function dice che non riceve il certificato. Possibili cause:
- App Service non ha `clientCertEnabled: true` ✅ **Verificato in Bicep**
- Certificato non è valido per HTTPS
- TLS 1.2+ non supportato

**Azione:** Verificare `az functionapp config show -g rg-intuneup-prod -n func-intuneup-http-prod | grep clientCertEnabled`

### ❌ "Certificate rejected"

Il certificato è ricevuto ma la CA non è nell'allowlist.

**Azione:** Controllare Key Vault:
```powershell
az keyvault secret show \
  --vault-name kv-intuneup-prod \
  --name AllowedIssuerThumbprints \
  --query value -o tsv
```

### ❌ "Invalid JSON body"

Payload malformato. Verificare la struttura:
- Campo `DeviceId` must not be null/empty
- Campo `UseCase` must not be null/empty
- `Data` è opzionale

### ❌ "Timeout"

Payload troppo grande o rete lenta.

**Azioni:**
- Ridurre `PayloadSizeKB` a 100-200 KB
- Verificare latenza: `Test-NetConnection -ComputerName func-intuneup-http-prod.azurewebsites.net -Port 443`
- Incrementare timeout nello script se necessario

## Tips & Tricks

### Estrarre solo il Thumbprint del Certificato
```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" }
Write-Host $cert.Thumbprint
```

### Testare senza lo Script (Direct Invoke-WebRequest)
```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" }
$payload = @{
    DeviceId = "MANUAL-TEST"
    DeviceName = "MANUAL-PC"
    UseCase = "ManualTest"
    Data = @{}
} | ConvertTo-Json

Invoke-WebRequest `
    -Uri "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
    -Method Post `
    -Certificate $cert `
    -ContentType "application/json" `
    -Body $payload
```

### Monitorare in Tempo Reale
```bash
# Watch dei messaggi in Service Bus
watch -n 5 'az servicebus queue show --namespace-name sb-intuneup-prod --name device-telemetry --resource-group rg-intuneup-prod --query messageCount'
```

## Security Notes

✅ **Best Practices Implementate:**
- mTLS con validazione CA
- Certificato self-signed solo per testing
- No hardcoded credentials
- Payload validation lato server
- Logging degli accessi

⚠️ **Per Produzione Real:**
- Usare certificati PKI aziendale (non self-signed)
- Distribuire via Intune certificate deployment
- Ruotare certificati periodicamente
- Abilitare Certificate Revocation Check
- Monitorare accessi non autorizzati
