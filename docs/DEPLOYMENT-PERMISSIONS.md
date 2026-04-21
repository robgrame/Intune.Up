# Intune.Up — Deployment Permissions

## Ruolo minimo richiesto per il deployer

| Ruolo | Basta? | Note |
|-------|--------|------|
| **Owner** | ✅ Sì | Crea risorse + assegna RBAC |
| **Contributor** | ❌ No | Crea risorse ma **non può assegnare RBAC** |
| **Contributor + User Access Administrator** | ✅ Sì | Alternativa a Owner |

> ⚠️ Il template Bicep crea **13 role assignments RBAC** (Managed Identity → risorse).
> Senza il permesso `Microsoft.Authorization/roleAssignments/write`, il deploy fallisce.

---

## Prerequisiti software

| Tool | Versione | Scopo |
|------|----------|-------|
| Azure CLI | 2.x+ | Deploy infrastruttura, gestione risorse |
| .NET SDK | 10.0+ | Build delle Azure Functions |
| Bicep CLI | Incluso in Azure CLI | Compilazione template Bicep |
| PowerShell | 7.x+ | Script di deploy e test |

---

## Risorse Azure create dal deploy

### Infrastruttura core (7 risorse)

| Risorsa | Nome | Tipo |
|---------|------|------|
| Log Analytics Workspace | `law-{baseName}-{env}` | `Microsoft.OperationalInsights/workspaces` |
| Service Bus Namespace + Queue | `sb-{baseName}-{env}` | `Microsoft.ServiceBus/namespaces` |
| Key Vault | `kv-{baseName}-{env}` | `Microsoft.KeyVault/vaults` |
| App Configuration | `appcs-{baseName}-{env}` | `Microsoft.AppConfiguration/configurationStores` |
| Application Insights | `appi-{baseName}-{env}` | `Microsoft.Insights/components` |
| Automation Account | `aa-{baseName}-{env}` | `Microsoft.Automation/automationAccounts` |

### Compute (4 risorse)

| Risorsa | Nome | Tipo |
|---------|------|------|
| App Service Plan (HTTP) | `asp-func-{baseName}-http-{env}` | `Microsoft.Web/serverfarms` (B1) |
| App Service Plan (SB) | `asp-func-{baseName}-sb-{env}` | `Microsoft.Web/serverfarms` (B1) |
| Function App (HTTP Collector) | `func-{baseName}-http-{env}` | `Microsoft.Web/sites` |
| Function App (SB Processor) | `func-{baseName}-sb-{env}` | `Microsoft.Web/sites` |

### Storage (4 account)

| Risorsa | Nome | Scopo |
|---------|------|-------|
| Storage HTTP Function | `st{baseName}http{env}` | Runtime Azure Functions (keys, state, leases) |
| Storage SB Function | `st{baseName}sb{env}` | Runtime Azure Functions (keys, state, leases) |
| Storage Claim-Check | `st{baseName}cc{env}` | Blob per messaggi >200KB (claim-check pattern) |
| Storage Password Expiry | `st{baseName}pe{env}` | Table Storage per scadenza password |

> Tutti gli storage hanno `allowSharedKeyAccess: false` (policy della subscription).
> L'accesso è esclusivamente tramite Managed Identity + RBAC.

---

## Role Assignments RBAC (creati dal Bicep)

### HTTP Function (Managed Identity)

| Risorsa target | Ruolo | Scopo |
|----------------|-------|-------|
| Storage runtime (`st*http*`) | Storage Blob Data Owner | Accesso blobs per runtime Functions |
| Storage runtime (`st*http*`) | Storage Account Contributor | Gestione file share |
| Storage runtime (`st*http*`) | Storage Queue Data Contributor | Accesso code interne |
| Storage runtime (`st*http*`) | Storage File Data Privileged Contributor | File share per Function runtime |
| Key Vault | Key Vault Secrets User | Lettura segreti (Log Analytics key, thumbprints) |
| App Configuration | App Configuration Data Reader | Lettura configurazione applicativa |
| Service Bus | Azure Service Bus Data Sender | Invio messaggi alla coda |
| Service Bus | Azure Service Bus Data Owner | Controllo completo (identity-based auth) |
| Storage pwd expiry (`st*pe*`) | Storage Table Data Contributor | Lettura/cancellazione record scadenza password |

### SB Processor Function (Managed Identity)

| Risorsa target | Ruolo | Scopo |
|----------------|-------|-------|
| Storage runtime (`st*sb*`) | Storage Blob Data Owner | Accesso blobs per runtime Functions |
| Storage runtime (`st*sb*`) | Storage Account Contributor | Gestione file share |
| Storage runtime (`st*sb*`) | Storage Queue Data Contributor | Accesso code interne |
| Storage runtime (`st*sb*`) | Storage File Data Privileged Contributor | File share per Function runtime |
| Key Vault | Key Vault Secrets User | Lettura segreti |
| App Configuration | App Configuration Data Reader | Lettura configurazione applicativa |
| Service Bus | Azure Service Bus Data Receiver | Ricezione messaggi dalla coda |
| Service Bus | Azure Service Bus Data Owner | Controllo completo (identity-based auth) |
| Log Analytics | Log Analytics Contributor | Scrittura dati telemetria nelle custom tables |

### Automation Account (Managed Identity)

| Risorsa target | Ruolo | Scopo |
|----------------|-------|-------|
| Storage pwd expiry (`st*pe*`) | Storage Table Data Contributor | Scrittura record scadenza password (runbook daily) |

### Deployer (utente che esegue deploy.ps1)

| Risorsa target | Ruolo | Scopo |
|----------------|-------|-------|
| Storage pwd expiry (`st*pe*`) | Storage Table Data Contributor | Inserimento dati di test per test-password-expiry.ps1 |

---

## Configurazione Service Bus

| Proprietà | Valore | Note |
|-----------|--------|------|
| `disableLocalAuth` | `true` | Shared Access Keys disabilitate |
| Autenticazione | Solo Managed Identity | Connection string non funzionano |
| SKU | Standard | Supporta queue, topic |

---

## Configurazione Storage

| Proprietà | Valore | Note |
|-----------|--------|------|
| `allowSharedKeyAccess` | `false` | Forzato da policy della subscription |
| Autenticazione | Solo OAuth / Managed Identity | |
| `defaultToOAuthAuthentication` | `true` | |

---

## Riepilogo: cosa serve per deployare

```
✅ Ruolo Owner (o Contributor + User Access Administrator) sulla subscription/RG
✅ Azure CLI installato e login con: az login
✅ .NET 10 SDK installato
✅ Subscription con quota VM disponibile nella region scelta (westeurope consigliato)
```

### Permessi Entra ID (Azure AD)

Il deploy Bicep crea **Managed Identity** per le Function Apps e l'Automation Account. Per assegnare RBAC a queste identità, il deployer necessita di:

| Permesso Entra ID | Chi lo serve | Perché |
|--------------------|--------------|--------|
| Lettura directory (`Directory.Read.All` o ruolo **Directory Readers**) | Utente deployer | Il Bicep deve risolvere i `principalId` delle Managed Identity per creare role assignments |

> In genere, un utente standard di Entra ID ha già questi permessi di lettura. Se il deploy fallisce con `PrincipalNotFound`, chiedere a un Global Admin di assegnare il ruolo **Directory Readers** all'utente.

### Permessi Entra ID per il Runbook Password Expiry

Il runbook `Write-PasswordExpiry.ps1` gira con la Managed Identity dell'Automation Account e richiede permessi **Microsoft Graph**:

| Permesso Graph | Tipo | Scopo | Chi lo assegna |
|----------------|------|-------|----------------|
| `User.Read.All` | Application | Query utenti e `lastPasswordChangeDateTime` | Global Admin o Privileged Role Administrator |

Comando per assegnare il permesso Graph alla MI dell'Automation Account:

```powershell
# Richiede: Global Admin o Privileged Role Administrator
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"

$miObjectId = az automation account show -g <rg> -n <aa-name> --query "identity.principalId" -o tsv

$graphAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
$appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq "User.Read.All" }

New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $miObjectId `
    -PrincipalId $miObjectId `
    -ResourceId $graphSp.Id `
    -AppRoleId $appRole.Id
```

### Riepilogo permessi per ruolo

| Ruolo/Persona | Permessi Azure | Permessi Entra ID |
|---------------|---------------|-------------------|
| **Deployer** (chi esegue deploy.ps1) | Owner sul RG (o Contributor + User Access Admin) | Directory Readers (di solito già assegnato) |
| **Global Admin** (one-time setup) | — | Assegna `User.Read.All` alla MI dell'Automation Account |
| **Function Apps** (Managed Identity) | RBAC assegnati dal Bicep (vedi sopra) | Nessuno |
| **Automation Account** (Managed Identity) | Table Data Contributor | `User.Read.All` (Microsoft Graph) |

### Comando di deploy

```powershell
az account set --subscription "<subscription-id>"
.\deploy.ps1 -BaseName <nome> -Environment <dev|test|prod> -Location westeurope
```
