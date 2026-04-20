# Gestione Certificati Client (mTLS)

## Architettura

```
[Device]                          [Azure]
Cert in LocalMachine\My  --mTLS-->  App Service (clientCertEnabled=true)
                                        |
                                    X-ARR-ClientCert header (base64 cert)
                                        |
                                    Azure Function risale la chain X.509
                                    e valida il thumbprint della CA emittente
                                    vs AllowedIssuerThumbprints in Key Vault
```

> **Nota:** La validazione non controlla il thumbprint del singolo certificato client,
> ma il thumbprint della **CA che lo ha emesso** (uno qualsiasi nella catena).
> Questo permette di autorizzare tutti i device con un certificato emesso dalla
> stessa PKI aziendale configurando la CA una sola volta.

## Setup passo-passo

### 1. Genera il certificato (una tantum)

```powershell
# Genera un certificato self-signed per il POC
$cert = New-SelfSignedCertificate `
    -Subject "CN=IntuneUp-Collector" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(2) `
    -Type Custom `
    -KeyUsage DigitalSignature

# Esporta come PFX (con password) per importazione in Intune
$pwd = ConvertTo-SecureString -String "IntuneUpPOC!" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath ".\IntuneUp-Collector.pfx" -Password $pwd

# Annota il thumbprint
Write-Host "Thumbprint: $($cert.Thumbprint)"
```

### 2. Distribuisci il certificato via Intune

1. **Intune portal** -> Devices -> Configuration -> Create -> New Policy
2. Platform: **Windows 10 and later**
3. Profile type: **Templates** -> **PKCS imported certificate**
4. Carica il file `.pfx` con la password
5. Certificate store: **Computer certificate store - Root** (oppure My)
6. Assegna al gruppo di device target

### 3. Configura il thumbprint della CA nel Key Vault

> ⚠️ **Importante:** configurare il thumbprint della **CA emittente** (non del certificato client).
> Per un certificato self-signed, il cert stesso è la propria CA — usare il suo thumbprint.

```powershell
# Scrivi il thumbprint della CA nell'allowlist (Key Vault)
az keyvault secret set `
    --vault-name kv-intuneup-dev `
    --name AllowedIssuerThumbprints `
    --value "<CA_THUMBPRINT>"
```

Per più CA (es. CA intermedia + CA root, oppure rotazione CA):
```powershell
az keyvault secret set `
    --vault-name kv-intuneup-dev `
    --name AllowedIssuerThumbprints `
    --value "<CA_THUMBPRINT_NUOVA>,<CA_THUMBPRINT_VECCHIA>"
```

### 4. Verifica

```powershell
# Recupera la function key
$functionKey = az functionapp keys list -g rg-intuneup-dev -n func-intup-http-dev `
    --query "functionKeys.default" -o tsv

# Test da un device con il certificato installato
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*IntuneUp*" }

Invoke-RestMethod `
    -Uri "https://func-intup-http-dev.azurewebsites.net/api/collect" `
    -Method Post `
    -Certificate $cert `
    -Headers @{ "x-functions-key" = $functionKey } `
    -ContentType "application/json" `
    -Body '{"DeviceId":"test","DeviceName":"TEST-PC","UseCase":"Test","Data":{}}'
```

## Rotazione certificati

La rotazione riguarda la **CA emittente** (raro) o i **certificati client** (frequente con SCEP).

### Rotazione certificati client (PKI/SCEP)
Con SCEP/PKCS la CA rimane la stessa → nessuna modifica al Key Vault necessaria.
Intune gestisce il rinnovo automaticamente.

### Rotazione CA (es. migrazione PKI)
1. Genera/ottieni il thumbprint della nuova CA
2. Aggiungi il nuovo thumbprint al Key Vault (mantieni anche il vecchio per coesistenza)
3. Distribuisci i nuovi certificati client firmati dalla nuova CA via Intune
4. Dopo che tutti i device hanno il nuovo cert, rimuovi il thumbprint della vecchia CA

## Produzione

Per ambienti di produzione, sostituire il certificato self-signed con:
- **SCEP** (Intune + NDES): rinnovo automatico, un cert per device
- **PKI aziendale**: certificati firmati dalla CA interna
- **Azure AD Certificate-Based Auth**: se disponibile
