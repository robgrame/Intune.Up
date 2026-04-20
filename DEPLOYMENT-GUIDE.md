# 🚀 Intune.Up Deployment Guide

Complete step-by-step instructions for deploying Intune.Up infrastructure and functions.

---

## ✅ Prerequisites

Before deploying, ensure you have:

- ✅ Azure CLI installed ([install](https://aka.ms/installazurecliwindows))
- ✅ .NET 10 SDK installed ([install](https://dotnet.microsoft.com/download/dotnet/10.0))
- ✅ PowerShell 5.1+ (Windows or cross-platform)
- ✅ Azure subscription with available quota in **westeurope** region
- ✅ Azure CLI authenticated: `az login`
- ⚠️ **IMPORTANT:** This subscription has VM quota constraints in `eastus`. Always use **`westeurope`** for deployment.

### Check Your Azure Connection

```powershell
az account show
```

Output should show your subscription name and ID.

---

## 📋 Deployment Methods

### Method 1: Automated Script (Recommended)

The `deploy.ps1` script automates the entire pipeline:

```powershell
# Full deployment with build
.\deploy.ps1 -Environment prod -Location westeurope

# With certificate thumbprints for mTLS validation
.\deploy.ps1 -Environment prod -Location westeurope `
  -AllowedIssuerThumbprints "ABC123DEF456..."

# Skip build if already compiled
.\deploy.ps1 -Environment prod -Location westeurope -SkipBuild
```

**What the script does:**
1. ✅ Pre-flight checks (Azure CLI, .NET SDK, resource group)
2. ✅ Build solution in Release mode
3. ✅ Publish HTTP and Service Bus functions
4. ✅ Create deployment ZIP packages
5. ✅ Deploy Bicep infrastructure (Log Analytics, Service Bus, Key Vault, etc.)
6. ✅ Deploy function apps (zip deploy)

**Time:** ~5-10 minutes (depending on build size)

### Method 2: Manual Step-by-Step

If you prefer to deploy manually:

#### Step 1: Prepare

```powershell
$Environment = "prod"
$Location = "westeurope"
$BaseName = "iu"  # Or any 2-3 character name
$ResourceGroup = "rg-$BaseName-$Environment"
```

#### Step 2: Build & Publish

```powershell
# Build solution
dotnet build src -c Release

# Publish HTTP function
dotnet publish src/IntuneUp.Collector.Http/IntuneUp.Collector.Http.csproj `
  -c Release -o publish/http --no-build

# Publish Service Bus function
dotnet publish src/IntuneUp.Collector.ServiceBus/IntuneUp.Collector.ServiceBus.csproj `
  -c Release -o publish/sb --no-build

# Create ZIP packages
Compress-Archive -Path "publish/http/*" -DestinationPath publish/http.zip -Force
Compress-Archive -Path "publish/sb/*" -DestinationPath publish/sb.zip -Force
```

#### Step 3: Create Resource Group

```powershell
az group create --name $ResourceGroup --location $Location
```

#### Step 4: Deploy Infrastructure

```powershell
$CaThumbprints = "ABC123..."  # Leave empty if not using mTLS

az deployment group create `
  --resource-group $ResourceGroup `
  --template-file infrastructure/bicep/main.bicep `
  --parameters `
    environment=$Environment `
    baseName=$BaseName `
    location=$Location `
    allowedIssuerThumbprints=$CaThumbprints
```

#### Step 5: Deploy Functions

```powershell
$HttpFuncName = "func-$BaseName-http-$Environment"
$SbFuncName = "func-$BaseName-sb-$Environment"

az functionapp deployment source config-zip `
  --resource-group $ResourceGroup `
  --name $HttpFuncName `
  --src publish/http.zip

az functionapp deployment source config-zip `
  --resource-group $ResourceGroup `
  --name $SbFuncName `
  --src publish/sb.zip
```

---

## 🔍 Verify Deployment

After deployment completes, verify all resources are running:

### Check Functions

```powershell
az functionapp list -g $ResourceGroup `
  --query "[].{name:name, state:state, location:location}" -o table
```

Output should show both functions with `Running` state:

```
Name                        State      Location
---------------------------  ---------  -----------
func-iu-http-prod           Running    West Europe
func-iu-sb-prod             Running    West Europe
```

### Get HTTP Endpoint

```powershell
$HttpFunc = "func-iu-http-prod"
$HttpUrl = (az functionapp show -n $HttpFunc -g $ResourceGroup `
  --query "defaultHostName" -o tsv)

Write-Host "HTTP Endpoint: https://$HttpUrl/api/collect"
```

### Check App Insights

```powershell
# List Application Insights instances
az monitor app-insights component show -g $ResourceGroup `
  --query "[].{name:name, appId:appId}" -o table
```

---

## 🧪 Test the Deployment

### 1. Test HTTP Function (Local)

```powershell
# Use the test client
.\test-client-basic.ps1 -FunctionUrl "https://<your-function-url>/api/collect" `
  -TestData @{
    deviceId = "test-device-123"
    hostname = "TESTPC"
  }
```

### 2. Test Service Bus Message Processing

```powershell
# Query Service Bus queue to verify message processing
az servicebus queue show -g $ResourceGroup `
  --namespace-name "sb-iu-prod" `
  --name "device-telemetry" `
  --query "messageCount"
```

Should return `0` or lower count if messages are being processed.

### 3. Check Log Analytics

```powershell
# Query custom table for collected device information
$WorkspaceId = $(az monitor log-analytics workspace list -g $ResourceGroup `
  --query "[0].id" -o tsv)

az monitor log-analytics query -w $WorkspaceId `
  --analytics-query "IntuneUp_DeviceInfo_CL | take 10" -o table
```

---

## 🛠️ Troubleshooting

### Deployment Fails: "InternalSubscriptionIsOverQuotaForSku"

**Cause:** The subscription has no VM quota in the selected region.

**Solution:** Use `westeurope` (tested and verified to work):

```powershell
.\deploy.ps1 -Environment prod -Location westeurope
```

### Function App Not Starting

Check the function app logs:

```powershell
az functionapp log tail -g $ResourceGroup -n "func-iu-http-prod" --provider ms
```

### Service Bus Not Receiving Messages

1. Verify the HTTP function can access Service Bus:
   ```powershell
   az functionapp identity show -g $ResourceGroup `
     -n "func-iu-http-prod" --query "principalId" -o tsv
   ```

2. Check RBAC role assignments:
   ```powershell
   az role assignment list --resource-group $ResourceGroup `
     --query "[?contains(principalName, 'func-iu')].{role:roleDefinitionName, principal:principalName}" -o table
   ```

### Log Analytics Not Receiving Data

1. Verify the workspace exists:
   ```powershell
   az monitor log-analytics workspace list -g $ResourceGroup -o table
   ```

2. Check managed identity permissions on workspace:
   ```powershell
   az role assignment list --resource-group $ResourceGroup `
     --scope "/subscriptions/YOUR-SUB-ID/resourcegroups/$ResourceGroup/providers/microsoft.operationalinsights/workspaces/*" -o table
   ```

---

## 📊 Post-Deployment Checklist

- [ ] Both function apps are in `Running` state
- [ ] HTTP function endpoint is accessible (https://<name>.azurewebsites.net/api/collect)
- [ ] Service Bus namespace has messages flowing (or queue is empty if processing)
- [ ] Log Analytics workspace has custom tables (`IntuneUp_DeviceInfo_CL` etc.)
- [ ] Application Insights showing requests from functions
- [ ] Key Vault has secrets initialized
- [ ] App Configuration has values seeded

---

## 🗑️ Clean Up

To remove all deployed resources:

```powershell
$ResourceGroup = "rg-iu-prod"

# Delete the entire resource group
az group delete --name $ResourceGroup --yes --no-wait

Write-Host "Resource group $ResourceGroup deleted (this may take a few minutes)"
```

---

## 📚 Related Documentation

- [DEPLOYMENT-SUCCESS.md](DEPLOYMENT-SUCCESS.md) - Details of successful westeurope deployment
- [DEPLOYMENT-BLOCKERS.md](DEPLOYMENT-BLOCKERS.md) - Analysis of quota issues and solutions
- [CONTAINER-APPS-GUIDE.md](CONTAINER-APPS-GUIDE.md) - Alternative Container Apps deployment
- [README.md](README.md) - Project overview and use cases
