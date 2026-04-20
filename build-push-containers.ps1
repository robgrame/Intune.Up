# Build and Push Container Images to Azure Container Registry

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,
    
    [string]$ImageTag = "latest"
)

# Get registry credentials
$registry = az acr show --resource-group $ResourceGroup --name $ContainerRegistryName -o json | ConvertFrom-Json
$loginServer = $registry.loginServer

echo "🔑 Container Registry: $loginServer"
echo ""

# Login to ACR
echo "🔐 Logging in to ACR..."
az acr login --name $ContainerRegistryName

# Build and push HTTP collector
echo ""
echo "📦 Building HTTP Collector image..."
$httpImage = "$loginServer/intuneup-http:$ImageTag"
echo "  Target: $httpImage"

az acr build `
    --registry $ContainerRegistryName `
    --image "intuneup-http:$ImageTag" `
    --file "src/IntuneUp.Collector.Http/Dockerfile" `
    .

if ($LASTEXITCODE -ne 0) {
    echo "❌ HTTP image build failed"
    exit 1
}

echo "✅ HTTP image built and pushed"

# Build and push Service Bus processor
echo ""
echo "📦 Building Service Bus Processor image..."
$sbImage = "$loginServer/intuneup-sb:$ImageTag"
echo "  Target: $sbImage"

az acr build `
    --registry $ContainerRegistryName `
    --image "intuneup-sb:$ImageTag" `
    --file "src/IntuneUp.Collector.ServiceBus/Dockerfile" `
    .

if ($LASTEXITCODE -ne 0) {
    echo "❌ Service Bus image build failed"
    exit 1
}

echo "✅ Service Bus image built and pushed"

# Output image URLs
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ All images built and pushed successfully!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Use these image URLs for deployment:"
echo ""
echo "HTTP Collector:"
echo "  $httpImage"
echo ""
echo "Service Bus Processor:"
echo "  $sbImage"
echo ""
echo "Deploy with:"
echo "  az deployment group create \"
echo "    --resource-group <RG> \"
echo "    --template-file infrastructure/bicep/main-container-apps.bicep \"
echo "    --parameters baseName=<name> \"
echo "                 httpContainerImage=$httpImage \"
echo "                 sbContainerImage=$sbImage"
