# Azure Deployment Blockers & Resolution

## Current Status: BLOCKED ❌

The infrastructure cannot deploy due to **zero VM quota** across all SKU tiers in the subscription.

## Error Details

### Quota Errors Encountered:

1. **Standard VMs quota**: 0 (needed: 1) - Failed when using S1 App Service Plan
2. **Basic VMs quota**: 0 (needed: 1) - Failed when using B1 App Service Plan  
3. **Dynamic/Consumption quota**: 0 (needed: 1) - Would fail for Y1 Consumption plan

All Azure App Service Plans (S1, B1, B2, B3, Y1, etc.) require "Virtual Machines" quota allocation.

### Related Constraints:

- **Storage account policy**: Subscription enforces llowSharedKeyAccess=false
  - All storage connections must use Managed Identity (RBAC), not shared keys
  - Already implemented: All app configs use DefaultAzureCredential
  
- **Resource naming**: Fixed to stay within 24-char storage account limit
  - Changed: claimcheck → cc, pwdexp → pe
  - All storage names now valid (3-24 chars, alphanumeric)

## Solutions

### Option 1: Request Quota Increase (Recommended for Production) ⏱️

1. **Open Azure Support Request**
   - Severity: High (Production deployment blocked)
   - Type: Service and subscription limits (Quotas)
   - Limit: Virtual Machines
   - New limit: 2 per region (for 2 functions + buffer)

2. **Wait for approval**: Usually 1-2 business days

3. **Redeploy**:
   \\\powershell
   az group create --name rg-intuneup-prod --location eastus
   
   az deployment group create \
     --resource-group rg-intuneup-prod \
     --template-file infrastructure/bicep/main.bicep \
     --parameters baseName=iu environment=prod location=eastus
   \\\

### Option 2: Use Azure Container Apps (Immediate, No Quota Needed) ⚡

Container Apps is a serverless compute service that doesn't use VM quotas:

1. **Create new bicep modules** for Container Apps instead of Function Apps:
   - Create infrastructure/bicep/container-app-http.bicep
   - Create infrastructure/bicep/container-app-sb.bicep
   - Use ca-env.bicep for Container Apps environment
   
2. **Build function container images**:
   \\\ash
   cd src/IntuneUp.Collector.Http
   docker build -t intuneup-http:latest .
   
   cd ../IntuneUp.Collector.ServiceBus
   docker build -t intuneup-sb:latest .
   \\\

3. **Push to registry**: Azure Container Registry (ACR)

4. **Update main.bicep** to use container modules instead of function modules

5. **Deploy**: Same deployment script works

### Option 3: Use Azure Functions on Premium Plan (Alternative)

Premium plan requires pre-allocated instances but might have different quotas - check availability first.

## Testing Without Deployment

While awaiting quota or implementing Container Apps, we can:

1. **Run local tests** against the code:
   \\\powershell
   cd src/IntuneUp.Collector.Http
   dotnet build
   dotnet test
   \\\

2. **Mock Azure services locally**:
   - Use Azure Storage Emulator
   - Use Azure Service Bus local emulator
   - Unit tests with mocked dependencies

3. **Deploy to different subscription** if available

## Files Modified

- infrastructure/bicep/main.bicep - Fixed storage account names (cc, pe suffixes)
- infrastructure/bicep/function-app.bicep - Changed SKU to B1

## Next Steps

**Immediate Action Required:**
1. Choose Option 1, 2, or 3 above
2. If Option 1: Submit Azure Support request
3. If Option 2: Start Container Apps implementation
4. Notify team of deployment status

