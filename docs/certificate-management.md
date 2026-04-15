# Gestione Certificati Client (mTLS)

## Architettura

```
[Device]                          [Azure]
Cert in LocalMachine\My  --mTLS-->  App Service (clientCertEnabled=true)
                                        |
                                    X-ARR-ClientCert header (base64 cert)
                                        |
                                    Azure Function valida thumbprint
                                    vs allowlist in Key Vault
```

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

### 3. Configura il thumbprint nel Key Vault

```powershell
# Scrivi il thumbprint nell'allowlist (Key Vault)
az keyvault secret set `
    --vault-name kv-intuneup-dev `
    --name AllowedCertThumbprints `
    --value "<THUMBPRINT>"
```

Per piu certificati (es. rotazione), separa con virgola:
```powershell
az keyvault secret set `
    --vault-name kv-intuneup-dev `
    --name AllowedCertThumbprints `
    --value "<THUMBPRINT_NUOVO>,<THUMBPRINT_VECCHIO>"
```

### 4. Verifica

```powershell
# Test da un device con il certificato installato
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*IntuneUp*" }

Invoke-RestMethod `
    -Uri "https://func-intuneup-http-dev.azurewebsites.net/api/collect" `
    -Method Post `
    -Certificate $cert `
    -ContentType "application/json" `
    -Body '{"DeviceId":"test","DeviceName":"TEST-PC","UseCase":"Test","Data":{}}'
```

## Rotazione certificati

1. Genera nuovo certificato
2. Distribuiscilo via Intune (nuovo profilo PKCS)
3. Aggiungi il nuovo thumbprint al Key Vault (mantieni anche il vecchio)
4. Dopo che tutti i device hanno il nuovo cert, rimuovi il vecchio thumbprint

## Produzione

Per ambienti di produzione, sostituire il certificato self-signed con:
- **SCEP** (Intune + NDES): rinnovo automatico, un cert per device
- **PKI aziendale**: certificati firmati dalla CA interna
- **Azure AD Certificate-Based Auth**: se disponibile
