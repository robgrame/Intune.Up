# 🚀 Fresh Deployment in Progress

**Started:** 2026-04-20 21:38  
**Status:** ⏳ RUNNING (Subscription corrected)

## Deployment Configuration

| Parameter | Value |
|-----------|-------|
| Subscription | ME-MngEnvMCAP181054-robgrame-1 ✅ |
| Environment | prod |
| BaseName | iu |
| Location | westeurope |
| mTLS Validation | Disabled (optional) |
| Previous RGs Deleted | rg-iu-westeu-705393, rg-intuneup-prod, rg-iu-prod (wrong sub) |

## Deployment Steps

- [ ] ✅ Pre-flight checks
- [ ] 🏗️ Build solution (Release)
- [ ] 📦 Publish HTTP function
- [ ] 📦 Publish ServiceBus function
- [ ] 📦 Create ZIP packages
- [ ] 🌐 Deploy Bicep infrastructure
- [ ] ⚡ Deploy functions (zip deploy)

## Monitoring

**Watch Progress:**
- PowerShell window (should show real-time output)
- Azure Portal → Resource Groups → rg-iu-prod
- Check deployment events and logs

**Commands to Monitor:**
```powershell
# Check resource groups
az group exists --name rg-iu-prod

# List deployment operations
az deployment group show -g rg-iu-prod --name main --query "properties.{state:provisioningState, timestamp:timestamp}" -o table

# Watch function app status
az functionapp list -g rg-iu-prod --query "[].{name:name, state:state}" -o table
```

## Expected Artifacts

After deployment completes:
- ✅ HTTP Function: `func-iu-http-prod`
- ✅ Service Bus Function: `func-iu-sb-prod`
- ✅ Service Bus Namespace: `sb-iu-prod`
- ✅ Log Analytics: `law-iu-prod`
- ✅ Key Vault: `kv-iu-prod`
- ✅ App Configuration: `appcs-iu-prod`
- ✅ Application Insights: `appi-iu-prod`
- ✅ Storage Accounts (4x): HTTP, SB, claim-check, password-expiry

## Next Steps After Completion

1. Verify all functions are running
2. Test HTTP endpoint with test-client-basic.ps1
3. Configure mTLS certificates
4. Monitor telemetry in Log Analytics

---

Check back when deployment completes!
