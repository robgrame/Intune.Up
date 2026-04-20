# Azure Container Apps Deployment Guide

## Overview

This guide covers deploying Intune.Up using **Azure Container Apps** instead of Azure Functions. Container Apps provides serverless compute without VM quota limitations.

## Why Container Apps?

| Aspect | Azure Functions | Azure Container Apps |
|--------|-----------------|----------------------|
| Compute Model | Managed (App Service Plan) | Serverless (No VM quota) |
| VM Quota | Required (0/1 in this subscription ❌) | None required ✅ |
| Container Support | Limited | Full Docker support ✅ |
| Scaling | Auto-scaling | Auto-scaling ✅ |
| Pricing | Pay per execution + plan | Pay per vCPU-hour |
| Deployment | Zip/binary | Container images |

## Prerequisites

1. Azure CLI installed
2. Docker installed
3. Access to Azure subscription
4. Resource group for deployment

## Deployment Steps

### Step 1: Build Container Images

```powershell
# Create resource group
$rg = "rg-iu-prod-$(Get-Random -Minimum 100000 -Maximum 999999)"
az group create --name $rg --location eastus

# Run the build and push script
.\build-push-containers.ps1 -ResourceGroup $rg -ContainerRegistryName crXXXXX
```

This script:
1. Creates Azure Container Registry
2. Builds HTTP Collector image
3. Builds Service Bus Processor image
4. Pushes both images to ACR
5. Outputs image URLs for deployment

### Step 2: Deploy Infrastructure

```powershell
# After build-push-containers.ps1 completes, use the output image URLs:

$httpImage = "crXXXXX.azurecr.io/intuneup-http:latest"
$sbImage = "crXXXXX.azurecr.io/intuneup-sb:latest"

az deployment group create `
    --resource-group $rg `
    --template-file infrastructure/bicep/main-container-apps.bicep `
    --parameters baseName=iu`
                 httpContainerImage=$httpImage `
                 sbContainerImage=$sbImage `
                 environment=prod `
                 location=eastus
```

### Step 3: Verify Deployment

```powershell
# Check Container Apps
az containerapp list -g $rg

# Get HTTP endpoint
az containerapp show -n "ca-iu-http-prod" -g $rg --query "properties.configuration.ingress.fqdn"

# Check logs
az containerapp logs show -n "ca-iu-http-prod" -g $rg --follow
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Azure Container Apps                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐    ┌──────────────────────┐   │
│  │   HTTP Collector     │    │ Service Bus          │   │
│  │   Container App      │    │ Processor            │   │
│  │   (Ingress: Public)  │    │ (Ingress: Private)   │   │
│  │   0.25 CPU           │    │ 0.25 CPU             │   │
│  │   0.5 GB Memory      │    │ 0.5 GB Memory        │   │
│  │   Scale: 1-10        │    │ Scale: 1-5           │   │
│  └──────────────────────┘    └──────────────────────┘   │
│           │                           │                  │
│           └───┬───────────────────────┘                  │
│               │                                          │
└───────────────┼──────────────────────────────────────────┘
                │
        ┌───────┴──────────┐
        │                  │
   ┌────▼─────┐    ┌──────▼────┐
   │ Service  │    │ Log       │
   │ Bus      │    │ Analytics │
   │ Namespace│    │ Workspace │
   └──────────┘    └───────────┘
        │                │
   ┌────▼────────────────▼──┐
   │ Key Vault & App Config │
   │ (Config/Secrets)       │
   └───────────────────────┘
```

## Configuration

### HTTP Collector Container App

**Environment Variables:**
- `APPCONFIG_ENDPOINT` - Azure App Configuration endpoint
- `KeyVaultUri` - Azure Key Vault URI
- `IntuneUp__ServiceBus__QueueName` - Service Bus queue name
- `APPLICATIONINSIGHTS_INSTRUMENTATIONKEY` - App Insights key

**Port:** 7071 (HTTP)  
**Ingress:** Public (internet-facing)  
**Auth:** mTLS client certificate (inherited from HTTP function code)

### Service Bus Processor Container App

**Environment Variables:**
- Same as HTTP Collector (except queue name is derived from binding)

**Port:** 7071 (internal, no ingress)  
**Ingress:** Private (internal only)  
**Trigger:** Service Bus queue messages

## Monitoring

### View Logs

```powershell
# HTTP Collector logs
az containerapp logs show -n "ca-iu-http-prod" -g $rg --follow --tail 50

# Service Bus Processor logs
az containerapp logs show -n "ca-iu-sb-prod" -g $rg --follow --tail 50
```

### Check Revisions

```powershell
az containerapp revision list -n "ca-iu-http-prod" -g $rg
```

### Scaling Status

```powershell
# Check active replicas
az containerapp show -n "ca-iu-http-prod" -g $rg --query "properties.template.scale"
```

## Troubleshooting

### Container App won't start

1. Check logs: `az containerapp logs show -n <name> -g $rg --follow`
2. Verify image URL is correct
3. Check RBAC permissions (Managed Identity)
4. Verify environment variables in deployment

### Image not found

1. Verify image URL: `az acr repository list -n <registry>`
2. Check image tag: `az acr repository show-tags -n <registry> --repository <image>`
3. Ensure registry is in same subscription

### Connection errors to Key Vault / Service Bus

1. Check Managed Identity has correct RBAC roles
2. Verify Key Vault network rules allow access
3. Check firewall settings

## Cost

Container Apps pricing is based on:
- **vCPU allocation**: 0.25 vCPU = ~$0.02/hour
- **Memory allocation**: 0.5 GB = included
- **Duration**: Only charged when running

**Estimated monthly cost** (with 1 replica, 24/7):
- HTTP Collector: ~$14.40/month
- Service Bus Processor: ~$14.40/month
- Total: ~$29/month (similar to Functions)

## Differences from Functions

### What's the same:
- ✅ Same code (CollectFunction.cs, etc.)
- ✅ Same RBAC/Managed Identity
- ✅ Same app settings structure
- ✅ Same telemetry (App Insights)

### What's different:
- 🔧 Runs in container (Dockerfile required)
- 📦 Images built and pushed to ACR
- 🔄 Deployment includes registry/environment
- 🎯 Port 7071 exposed explicitly
- 📊 Different scaling rules (replicas instead of instances)

## Rollback

To rollback to Functions (once quota is available):

```powershell
# Use original template
az deployment group create \
    --resource-group $rg \
    --template-file infrastructure/bicep/main.bicep \
    --parameters baseName=iu environment=prod location=eastus
```

## Next Steps

1. ✅ Build containers
2. ✅ Push to ACR
3. ✅ Deploy with Bicep
4. 📝 Run end-to-end tests
5. 📊 Monitor telemetry
