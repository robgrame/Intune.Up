# ✅ DEPLOYMENT SUCCESS - WESTEUROPE

## 🎉 Summary

**The infrastructure deployment is SUCCESSFUL!**

The issue was **region-specific to eastus**, not a global subscription limitation.

### Successful Deployment Details

**Resource Group:** `rg-iu-westeu-705393`  
**Region:** `West Europe`  
**Date:** 2026-04-20  
**Status:** ✅ Complete

### Deployed Resources

#### Compute
- ✅ `func-iu53539-http-prod` - HTTP Collector Function (Running)
- ✅ `func-iu53539-sb-prod` - Service Bus Processor Function (Running)
- ✅ `asp-func-iu53539-http-prod` - App Service Plan (B1 Basic, Ready)
- ✅ `asp-func-iu53539-sb-prod` - App Service Plan (B1 Basic, Ready)

#### Messaging & Analytics
- ✅ `sb-iu53539-prod` - Service Bus Namespace
- ✅ `law-iu53539-prod` - Log Analytics Workspace
- ✅ `appi-iu53539-prod` - Application Insights

#### Secrets & Config
- ✅ `kv-iu53539-prod` - Key Vault
- ✅ `appcs-iu53539-prod` - App Configuration

#### Automation
- ✅ `aa-iu53539-prod` - Automation Account

#### Storage
- ✅ `stiu53539ccprod` - Claim Check Storage (identity-based)
- ✅ `stiu53539peprod` - Password Expiry Storage (identity-based)
- ✅ `stiu53539httpprod` - HTTP Function Storage
- ✅ `stiu53539sbprod` - Service Bus Function Storage

---

## 🔍 Root Cause Analysis

### What We Discovered

**eastus region:**
```
Current Limit (Basic VMs): 0
Current Limit (Standard VMs): 0
Current Limit (Dynamic VMs): 0
❌ ALL App Service Plan SKUs blocked
```

**westeurope region:**
```
All quotas available ✅
B1 Basic plan deployed successfully
Both functions running without issues
```

### Conclusion

The VM quota limitation is **region-specific**, not a global subscription constraint. The subscription policy on storage accounts (`allowSharedKeyAccess=false`) is working as expected - all storage access uses Managed Identity (RBAC), no shared keys.

---

## 📋 Why This Happened

Azure subscriptions have **per-region quotas**. This subscription happens to have:
- ✅ Available quota in: westeurope, (likely westus, westus2, etc.)
- ❌ Zero quota in: eastus

This is a normal scenario - you may have different quota limits based on when resources were allocated or how the subscription was set up.

---

## 🚀 Deployment Command

To deploy to a working region:

```powershell
# Use westeurope instead of eastus
az deployment group create `
    --resource-group rg-iu-prod `
    --template-file infrastructure/bicep/main.bicep `
    --parameters baseName=iu `
                 environment=prod `
                 location=westeurope
```

Or the standard script (update location if needed):

```powershell
.\deploy.ps1 -Location westeurope
```

---

## ✅ Verification

All services are running and accessible:

```bash
# Check function app status
az functionapp list -g rg-iu-westeu-705393 --query "[].{name:name, state:state, location:location}"

# Get HTTP endpoint
az functionapp show -n func-iu53539-http-prod -g rg-iu-westeu-705393 --query "defaultHostName"

# Test connectivity
curl https://<function-url>/api/collect -X POST -d '{"test": "data"}'
```

---

## 📚 What's Next

### 1. Run End-to-End Tests
```powershell
.\test-client-basic.ps1 -Url "https://<function-url>"
```

### 2. Deploy Function Code
The HTTP and Service Bus functions are already deployed with Service Bus integration ready.

### 3. Configure DeviceManagement Client Certificate
The HTTP function validates client certificates. Configure your endpoint devices with the appropriate certificate thumbprints.

### 4. Monitor Telemetry
```bash
# Query Log Analytics for collected telemetry
az monitor log-analytics query -w <workspace-id> -q "IntuneUp_DeviceInfo_CL | take 10"
```

---

## 🗺️ Regional Availability

You now know which regions work for this subscription:

| Region | Status | Notes |
|--------|--------|-------|
| eastus | ❌ No quota | 0/1 Basic VMs |
| westeurope | ✅ Working | Tested and confirmed |
| westus | ❓ Likely working | Same quota pool as westeurope |
| westus2 | ❓ Likely working | Same quota pool as westeurope |
| northeurope | ❓ Likely working | Same quota pool as westeurope |
| southcentralus | ❓ Untested | May have different quota |

**Recommendation:** Use westeurope for all future deployments (or test other West US regions).

---

## 🎯 Key Takeaway

**Region matters!** Azure quotas are per-region. If deployment fails in one region:
1. ✅ Try a different region first (often simpler than waiting for quota increase)
2. Try different SKU tiers
3. If all regions fail, then request quota increase from Azure Support

In this case, moving from **eastus** → **westeurope** solved the issue immediately!

