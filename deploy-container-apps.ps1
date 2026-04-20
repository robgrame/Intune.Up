#!/usr/bin/env pwsh
# Deploy Intune.Up to Azure using Container Apps
# This script handles the entire deployment process

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = "iu$(Get-Random -Minimum 10000 -Maximum 99999)",
    
    [switch]$SkipImageBuild
)

$ErrorActionPreference = "Stop"

Write-Host "╔════════════════════════════════════════════════════════════════╗"
Write-Host "║      Intune.Up Deployment - Azure Container Apps             ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# STEP 1: Initialize
# ═══════════════════════════════════════════════════════════════════════

Write-Host "📋 STEP 1: Initialize Deployment"
Write-Host "  BaseName: $BaseName"
Write-Host "  Environment: $Environment"
Write-Host "  Location: $Location"
Write-Host ""

$ResourceGroup = "rg-${BaseName}-${Environment}-$(Get-Date -Format 'yyMMdd')"
Write-Host "  Resource Group: $ResourceGroup"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# STEP 2: Create Resource Group
# ═══════════════════════════════════════════════════════════════════════

Write-Host "📍 STEP 2: Create Resource Group"
Write-Host "  Creating: $ResourceGroup in $Location..."
az group create --name $ResourceGroup --location $Location --output none
Write-Host "  ✅ Resource group created"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# STEP 3: Build and Push Container Images
# ═══════════════════════════════════════════════════════════════════════

if (-not $SkipImageBuild) {
    Write-Host "📦 STEP 3: Build and Push Container Images"
    Write-Host "  Building images and pushing to ACR..."
    Write-Host ""
    
    cd $PSScriptRoot
    
    # Run build script
    & ".\build-push-containers.ps1" -ResourceGroup $ResourceGroup -ContainerRegistryName "cr${BaseName}${Environment}"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Image build failed"
        exit 1
    }
    
    Write-Host ""
}
else {
    Write-Host "⏭️  STEP 3: Skipping image build (--SkipImageBuild)"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 4: Deploy Infrastructure
# ═══════════════════════════════════════════════════════════════════════

Write-Host "🚀 STEP 4: Deploy Infrastructure with Bicep"
Write-Host "  Template: main-container-apps.bicep"
Write-Host "  Resource Group: $ResourceGroup"
Write-Host ""

# Get container registry login server
$registryName = "cr${BaseName}${Environment}"
$registry = az acr show --resource-group $ResourceGroup --name $registryName -o json | ConvertFrom-Json
$loginServer = $registry.loginServer

$httpImage = "$loginServer/intuneup-http:latest"
$sbImage = "$loginServer/intuneup-sb:latest"

Write-Host "  Container Images:"
Write-Host "    HTTP: $httpImage"
Write-Host "    SB:   $sbImage"
Write-Host ""
Write-Host "  Deploying (this may take 5-10 minutes)..."

$start = Get-Date

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infrastructure/bicep/main-container-apps.bicep `
    --parameters baseName=$BaseName `
                 environment=$Environment `
                 location=$Location `
                 httpContainerImage=$httpImage `
                 sbContainerImage=$sbImage `
    --output none

$elapsed = (Get-Date) - $start

Write-Host "  ✅ Deployment completed in $($elapsed.TotalSeconds) seconds"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# STEP 5: Get Deployment Outputs
# ═══════════════════════════════════════════════════════════════════════

Write-Host "📊 STEP 5: Deployment Outputs"
Write-Host ""

$deployment = az deployment group show --resource-group $ResourceGroup --name main-container-apps -o json | ConvertFrom-Json
$outputs = $deployment.properties.outputs

Write-Host "  🌐 HTTP Endpoint:"
Write-Host "     $($outputs.httpContainerAppUrl.value)"
Write-Host ""
Write-Host "  🚌 Service Bus Namespace:"
Write-Host "     $($outputs.serviceBusNamespace.value)"
Write-Host ""
Write-Host "  🔑 Key Vault:"
Write-Host "     $($outputs.keyVaultName.value)"
Write-Host ""
Write-Host "  📊 App Insights:"
Write-Host "     $($outputs.appInsightsName.value)"
Write-Host ""
Write-Host "  📦 Container Registry:"
Write-Host "     $($outputs.containerRegistryLoginServer.value)"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# STEP 6: Save Deployment Info
# ═══════════════════════════════════════════════════════════════════════

Write-Host "💾 STEP 6: Save Deployment Info"

$deploymentInfo = @{
    ResourceGroup = $ResourceGroup
    BaseName = $BaseName
    Environment = $Environment
    Location = $Location
    DeploymentTime = $start.ToString("o")
    Duration = $elapsed.TotalSeconds
    HTTPEndpoint = $outputs.httpContainerAppUrl.value
    ServiceBusNamespace = $outputs.serviceBusNamespace.value
    KeyVault = $outputs.keyVaultName.value
    AppInsights = $outputs.appInsightsName.value
    ContainerRegistry = $outputs.containerRegistryLoginServer.value
}

$deploymentInfo | ConvertTo-Json | Out-File -FilePath "deployment-info.json"
Write-Host "  ✅ Saved to: deployment-info.json"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════
# Success Summary
# ═══════════════════════════════════════════════════════════════════════

Write-Host "╔════════════════════════════════════════════════════════════════╗"
Write-Host "║                   ✅ DEPLOYMENT SUCCESSFUL                     ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "🎉 Intune.Up is now deployed on Azure Container Apps!"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Test HTTP endpoint:"
Write-Host "     .\test-client-basic.ps1 -Url '$($outputs.httpContainerAppUrl.value)'"
Write-Host ""
Write-Host "  2. View logs:"
Write-Host "     az containerapp logs show -n 'ca-${BaseName}-http-${Environment}' -g $ResourceGroup --follow"
Write-Host ""
Write-Host "  3. Monitor telemetry:"
Write-Host "     az monitor app-insights show --name '$($outputs.appInsightsName.value)' -g $ResourceGroup"
Write-Host ""
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Total Time: $($elapsed.TotalSeconds) seconds"
Write-Host ""
