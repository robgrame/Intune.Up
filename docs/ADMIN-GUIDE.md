# Admin Guide - Intune.Up Production Deployment

## Overview

Questo documento fornisce istruzioni per completare l'autenticazione mTLS sul HTTP function in produzione.

## Status Attuale

✅ **Completato:**
- Infrastructure Bicep deployment (App Insights, storage, functions)
- Azure Functions runtime (.NET 10 Isolated)
- App Configuration seeding
- Key Vault setup
- HTTP function pronta a ricevere richieste

❌ **In Sospeso:**
- Autorizzazione del certificato client nel Key Vault

## Prerequisiti

- Accesso al Key Vault `kv-intuneup-prod` con ruolo **Key Vault Secrets Officer** (o equivalente)
- PowerShell 5.1+
- Azure CLI (`az` command)

## Passaggi

### Passo 1: Verifica lo Stato del Certificato

```powershell
# Controlla quale certificato è stato generato
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" }

if ($cert) {
    Write-Host "Certificato trovato:"
    Write-Host "  Subject: $($cert.Subject)"
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  Valid From: $($cert.NotBefore)"
    Write-Host "  Valid Until: $($cert.NotAfter)"
}
else {
    Write-Host "Nessun certificato trovato. Genera uno con:"
    Write-Host '  $cert = New-SelfSignedCertificate -Subject "CN=IntuneUp-Collector" -CertStoreLocation "Cert:\CurrentUser\My"'
}
```

### Passo 2: Autorizza il Certificato (Metodo 1: Script Automatico)

```powershell
# Uso dello script di autorizzazione automatica (CONSIGLIATO)
cd C:\Users\robgrame\source\repos\Intune.Up

.\authorize-certificate.ps1 `
  -KeyVaultName "kv-intuneup-prod" `
  -Thumbprint "4E050ADBD50A4132C1CC2B237929E113431993D2"
```

Lo script:
- Legge i thumbprint attuali
- Aggiunge il nuovo thumbprint
- Deduplica automaticamente
- Salva il nuovo valore in KV

### Passo 2 Alternativo: Autorizza il Certificato (Metodo 2: Manuale)

```powershell
# Se preferisci farlo manualmente:

# 1. Ottieni il thumbprint
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*IntuneUp*" }
$newThumbprint = $cert.Thumbprint

# 2. Leggi i thumbprint attuali dal KV
$currentSecret = az keyvault secret show `
  --vault-name kv-intuneup-prod `
  --name AllowedIssuerThumbprints `
  --query "value" -o tsv

if ($currentSecret) {
    Write-Host "Thumbprint attuali:"
    ($currentSecret -split ',') | ForEach-Object { Write-Host "  - $_" }
}

# 3. Aggiungi il nuovo thumbprint
$thumbprints = @()
if ($currentSecret) {
    $thumbprints = ($currentSecret -split ',').Trim()
}
$thumbprints += $newThumbprint
$thumbprints = $thumbprints | Sort-Object -Unique

# 4. Salva il nuovo valore
$newValue = ($thumbprints | Where-Object { $_ }) -join ','

az keyvault secret set `
  --vault-name kv-intuneup-prod `
  --name AllowedIssuerThumbprints `
  --value $newValue

Write-Host "✅ Certificato autorizzato"
Write-Host "   Totale thumbprint autorizzati: $($thumbprints.Count)"
```

### Passo 3: Verifica l'Autorizzazione

```powershell
# Controlla che il thumbprint sia stato salvato correttamente
az keyvault secret show `
  --vault-name kv-intuneup-prod `
  --name AllowedIssuerThumbprints `
  --query "value" -o tsv
```

Output atteso:
```
4E050ADBD50A4132C1CC2B237929E113431993D2,3F4DD6BE8C7C4181A24E37B18A73C96C1F75BE66,60C4DBFFFFFF...
```

### Passo 4: Test della Function

Una volta autorizzato il certificato, il test dovrebbe funzionare:

```powershell
# Utente esegue (dopo che tu hai autorizzato il cert):
.\test-client.ps1 `
  -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
  -ResourceGroup "rg-intuneup-prod" `
  -FunctionAppName "func-intuneup-http-prod" `
  -SkipCertSetup
```

Output atteso:
```
✅ Payload accepted (HTTP 202)
```

## Troubleshooting

### Errore: "Forbidden" - Non hai permessi KV

```
(Forbidden) Caller is not authorized to perform action on resource.
Action: 'Microsoft.KeyVault/vaults/secrets/setSecret/action'
```

**Soluzione:**
- Richiedi al subscription owner di assegnarti il ruolo **"Key Vault Secrets Officer"**
- Oppure usa Azure Portal per aggiungere il thumbprint manualmente

### Errore: Certificato scaduto

```powershell
# Genera un nuovo certificato valido per 10 anni
$cert = New-SelfSignedCertificate `
  -Subject "CN=IntuneUp-Collector" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -NotAfter (Get-Date).AddYears(10)

Write-Host "Nuovo thumbprint: $($cert.Thumbprint)"
```

Poi autorizza il nuovo thumbprint seguendo i passaggi sopra.

### Funzione continua a rispondere 403

```powershell
# Potrebbe servire un reload della function app
az functionapp restart -g rg-intuneup-prod -n func-intuneup-http-prod

# Aspetta 10 secondi
Start-Sleep -Seconds 10

# Ritesta
.\test-client.ps1 -FunctionUrl "..." -SkipCertSetup
```

## Monitoring

Dopo aver autorizzato il certificato, puoi monitorare gli accessi:

```bash
# Query App Insights per vedere le richieste
az monitor app-insights query \
  --app appi-intuneup-prod \
  --analytics-query "traces | where message contains 'Certificate' or message contains 'Accepted' | top 20 by timestamp desc"

# Contare i messaggi accodati in Service Bus
az servicebus queue show \
  -g rg-intuneup-prod \
  --namespace-name sb-intuneup-prod \
  --name device-telemetry \
  --query "messageCount"
```

## Security Checklist

- [ ] Thumbprint del certificato è unico (non duplicato)
- [ ] Certificato è stato validato (NotBefore <= Now <= NotAfter)
- [ ] Solo thumbprint autorizzati nel AllowedIssuerThumbprints
- [ ] App Insights è configurato per logging
- [ ] Service Bus ha retention policy appropriata
- [ ] Storage accounts hanno identity-based access
- [ ] Key Vault ha soft-delete e purge-protection abilitato

## Domande Frequenti

**D: Posso aggiungere più certificati?**
A: Sì, il secret AllowedIssuerThumbprints contiene una lista delimitata da virgole.

**D: Quanto tempo impiega l'autorizzazione?**
A: Immediato. La function legge il secret ad ogni richiesta.

**D: Cosa succede se il certificato scade?**
A: Le richieste con quel certificato risponderanno 401. Genera un nuovo certificato e aggiorna il thumbprint nel KV.

**D: Posso usare certificati aziendali PKI?**
A: Sì, solo che il thumbprint deve essere il thumbprint della CA emittente (issuer), non del certificato foglia.

## Contatti

Per problemi di deployment o accesso, contattare:
- Subscription Owner: [nome admin Azure]
- Cloud Architect: [nome architect]
