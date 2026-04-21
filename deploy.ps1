<#
.SYNOPSIS
    Intune.Up - Full deployment script
    Executes: Build -> Publish -> Bicep infra -> Zip deploy function apps

.PARAMETER Environment
    Target environment: dev, test, prod (default: dev)

.PARAMETER Location
    Azure region for deployment (default: westeurope)
    Note: Use westeurope for this subscription (VM quota in eastus is limited)

.PARAMETER ResourceGroup
    Azure Resource Group (default: rg-intuneup-<Environment>)

.PARAMETER BaseName
    Base name for resource naming (default: intuneup)

.PARAMETER AllowedIssuerThumbprints
    Comma-separated CA thumbprints for mTLS validation.
    If omitted and Bicep runs, you will be prompted.

.PARAMETER SkipBuild
    Skip dotnet build/publish (reuse existing publish/ output)

.PARAMETER SkipBicep
    Skip Bicep infrastructure deployment

.PARAMETER SkipFunctionDeploy
    Skip zip deploy of function apps

.EXAMPLE
    .\deploy.ps1 -Environment dev -AllowedIssuerThumbprints 'ABC123...'
    .\deploy.ps1 -Environment dev -SkipBuild
    .\deploy.ps1 -Environment prod -Location westeurope
    .\deploy.ps1 -Environment dev -SkipBicep -SkipBuild
#>
[CmdletBinding()]
param(
    [ValidateSet('dev','test','prod')]
    [string]$Environment = 'dev',

    [string]$Location = 'westeurope',

    [string]$ResourceGroup = '',

    [string]$BaseName = 'intuneup',

    [string]$AllowedIssuerThumbprints = '',

    [switch]$SkipBuild,
    [switch]$SkipBicep,
    [switch]$SkipFunctionDeploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$m) Write-Host "`n>> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "   OK  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "   WARN $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "   FAIL $m" -ForegroundColor Red; exit 1 }

# Derived paths and names — force lowercase for Azure resource naming consistency
$BaseName    = $BaseName.ToLower()
$Environment = $Environment.ToLower()
$Location    = $Location.ToLower()
if (-not $ResourceGroup) { $ResourceGroup = "rg-$BaseName-$Environment" }
$ResourceGroup = $ResourceGroup.ToLower()

$RepoRoot    = $PSScriptRoot
$SrcDir      = Join-Path $RepoRoot 'src'
$BicepDir    = Join-Path $RepoRoot 'infrastructure\bicep'
$PublishDir  = Join-Path $RepoRoot 'publish'
$HttpProj    = Join-Path $SrcDir 'IntuneUp.Collector.Http\IntuneUp.Collector.Http.csproj'
$SbProj      = Join-Path $SrcDir 'IntuneUp.Collector.ServiceBus\IntuneUp.Collector.ServiceBus.csproj'
$HttpOut     = Join-Path $PublishDir 'http'
$SbOut       = Join-Path $PublishDir 'sb'
$HttpZip     = Join-Path $PublishDir 'http.zip'
$SbZip       = Join-Path $PublishDir 'sb.zip'
$MainBicep   = Join-Path $BicepDir 'main.bicep'
$FuncHttp    = "func-$BaseName-http-$Environment"
$FuncSb      = "func-$BaseName-sb-$Environment"

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host '   Intune.Up - Full Deploy Script           ' -ForegroundColor DarkCyan
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host "  Environment   : $Environment"
Write-Host "  Location      : $Location"
Write-Host "  ResourceGroup : $ResourceGroup"
Write-Host "  BaseName      : $BaseName"
Write-Host "  HTTP Function : $FuncHttp"
Write-Host "  SB Function   : $FuncSb"
Write-Host "  SkipBuild     : $SkipBuild"
Write-Host "  SkipBicep     : $SkipBicep"
Write-Host "  SkipFuncDeploy: $SkipFunctionDeploy"
Write-Host ''

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
Write-Step 'Pre-flight checks'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Fail 'Azure CLI not found. Install from https://aka.ms/installazurecliwindows'
}

$accountJson = az account show -o json 2>$null
if (-not $accountJson) { Write-Fail 'Not logged in to Azure. Run: az login' }
$account = $accountJson | ConvertFrom-Json
Write-Ok "Azure: $($account.name) ($($account.id))"

if (-not $SkipBuild) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Fail '.NET SDK not found. Install from https://dotnet.microsoft.com/download/dotnet/10.0'
    }
    $sdkVer = dotnet --version
    Write-Ok ".NET SDK: $sdkVer"
    if (-not $sdkVer.StartsWith('10.')) {
        Write-Warn ".NET version $sdkVer detected - expected 10.x. Build may fail."
    }
}

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -ne 'true') { 
    Write-Step "Creating resource group: $ResourceGroup in $Location"
    az group create --name $ResourceGroup --location $Location --output none
    Write-Ok "Resource group created: $ResourceGroup"
} else {
    Write-Ok "Resource group already exists: $ResourceGroup"
}

if ((-not $SkipBicep) -and (-not $AllowedIssuerThumbprints)) {
    Write-Warn 'AllowedIssuerThumbprints not provided.'
    $AllowedIssuerThumbprints = Read-Host '  Enter CA thumbprint(s), comma-separated (ENTER to skip)'
    if (-not $AllowedIssuerThumbprints) {
        Write-Warn 'Deploying without thumbprints - mTLS certificate validation will be DISABLED.'
    }
}

# --------------------------------------------------------------------------
# Step 1: Build + Publish
# --------------------------------------------------------------------------
if (-not $SkipBuild) {

    Write-Step 'Building solution (Release)'
    Push-Location $RepoRoot
    try {
        dotnet build $SrcDir -c Release --nologo
        if ($LASTEXITCODE -ne 0) { Write-Fail 'dotnet build failed.' }
    } finally { Pop-Location }
    Write-Ok 'Build succeeded'

    Write-Step 'Publishing HTTP function'
    if (Test-Path $HttpOut) { Remove-Item $HttpOut -Recurse -Force }
    dotnet publish $HttpProj -c Release -o $HttpOut --no-build --nologo
    if ($LASTEXITCODE -ne 0) { Write-Fail 'Publish HTTP failed.' }
    Write-Ok "Published to $HttpOut"

    Write-Step 'Publishing ServiceBus function'
    if (Test-Path $SbOut) { Remove-Item $SbOut -Recurse -Force }
    dotnet publish $SbProj -c Release -o $SbOut --no-build --nologo
    if ($LASTEXITCODE -ne 0) { Write-Fail 'Publish SB failed.' }
    Write-Ok "Published to $SbOut"

    Write-Step 'Creating ZIP packages'
    if (Test-Path $HttpZip) { Remove-Item $HttpZip -Force }
    if (Test-Path $SbZip)   { Remove-Item $SbZip -Force }
    Compress-Archive -Path "$HttpOut\*" -DestinationPath $HttpZip
    Compress-Archive -Path "$SbOut\*"   -DestinationPath $SbZip
    $httpMB = [math]::Round((Get-Item $HttpZip).Length / 1MB, 1)
    $sbMB   = [math]::Round((Get-Item $SbZip).Length   / 1MB, 1)
    Write-Ok "http.zip: ${httpMB} MB"
    Write-Ok "sb.zip  : ${sbMB} MB"

} else {
    Write-Warn 'SkipBuild: using existing publish/ output'
    if (-not (Test-Path $HttpZip)) { Write-Fail 'http.zip not found. Run without -SkipBuild first.' }
    if (-not (Test-Path $SbZip))   { Write-Fail 'sb.zip not found. Run without -SkipBuild first.' }
    Write-Ok 'Existing ZIPs found'
}

# --------------------------------------------------------------------------
# Step 2: Bicep infrastructure
# --------------------------------------------------------------------------
if (-not $SkipBicep) {

    Write-Step 'Deploying Bicep infrastructure'
    Write-Host "  Template: $MainBicep"
    Write-Host "  Location: $Location"

    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file  $MainBicep `
        --parameters     environment=$Environment `
                         baseName=$BaseName `
                         location=$Location `
                         allowedIssuerThumbprints=$AllowedIssuerThumbprints `
        --output table

    if ($LASTEXITCODE -ne 0) { Write-Fail 'Bicep deployment failed.' }
    Write-Ok 'Infrastructure deployed'

    Write-Step 'Assigning deployer RBAC (Table Data Contributor on password-expiry storage)'
    $deployerObjectId = az ad signed-in-user show --query "id" -o tsv 2>$null
    $peStorageId = az storage account show -g $ResourceGroup -n "st${BaseName}pe${Environment}" --query "id" -o tsv 2>$null
    if ($deployerObjectId -and $peStorageId) {
        az role assignment create --assignee $deployerObjectId --role "Storage Table Data Contributor" --scope $peStorageId -o none 2>$null
        Write-Ok "Deployer RBAC assigned on password-expiry storage"
    } else {
        Write-Warn "Could not assign deployer RBAC (non-blocking)"
    }

    Write-Step 'Waiting for RBAC propagation (90 seconds)'
    Write-Host '  Storage role assignments need time to propagate before function runtime can start.'
    Start-Sleep -Seconds 90
    Write-Ok 'RBAC propagation wait complete'

} else {
    Write-Warn 'SkipBicep: infrastructure deployment skipped'
}

# --------------------------------------------------------------------------
# Step 3: Zip deploy function apps (with retry for transient 5xx errors)
# --------------------------------------------------------------------------
function Deploy-FunctionZip {
    param([string]$RG, [string]$AppName, [string]$ZipPath, [int]$MaxRetries = 3)
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Host "  Attempt $attempt of $MaxRetries..." -ForegroundColor Gray
        az functionapp deployment source config-zip `
            --resource-group $RG --name $AppName --src $ZipPath --timeout 180 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
        
        if ($attempt -lt $MaxRetries) {
            $wait = $attempt * 20
            Write-Warn "Deploy failed (attempt $attempt). Retrying in ${wait}s..."
            Start-Sleep -Seconds $wait
        }
    }
    return $false
}

if (-not $SkipFunctionDeploy) {

    Write-Step "Deploying HTTP function: $FuncHttp"
    if (-not (Deploy-FunctionZip -RG $ResourceGroup -AppName $FuncHttp -ZipPath $HttpZip)) {
        Write-Fail "HTTP function deploy failed after retries."
    }
    Write-Ok "$FuncHttp deployed"

    Write-Step "Deploying ServiceBus function: $FuncSb"
    if (-not (Deploy-FunctionZip -RG $ResourceGroup -AppName $FuncSb -ZipPath $SbZip)) {
        Write-Fail "SB function deploy failed after retries."
    }
    Write-Ok "$FuncSb deployed"

} else {
    Write-Warn 'SkipFunctionDeploy: function app deployment skipped'
}

# --------------------------------------------------------------------------
# Step 4: Deploy Automation Runbook content
# --------------------------------------------------------------------------
$runbookScript = Join-Path $RepoRoot 'service-desk\runbooks\server-side\Write-PasswordExpiryTriggers.ps1'
$aaName = "aa-$BaseName-$Environment"

if (Test-Path $runbookScript) {
    Write-Step "Deploying Automation Runbook: Write-PasswordExpiryTriggers"

    az automation runbook replace-content `
        --resource-group $ResourceGroup `
        --automation-account-name $aaName `
        --name 'Write-PasswordExpiryTriggers' `
        --content "@$runbookScript" `
        -o none 2>$null

    if ($LASTEXITCODE -eq 0) {
        az automation runbook publish `
            --resource-group $ResourceGroup `
            --automation-account-name $aaName `
            --name 'Write-PasswordExpiryTriggers' `
            -o none 2>$null
        Write-Ok "Runbook published"
    } else {
        Write-Warn "Runbook content upload failed (non-blocking)"
    }
} else {
    Write-Warn "Runbook script not found at $runbookScript"
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host '   Deploy completed successfully!           ' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green
Write-Host ''
Write-Host "  HTTP : https://$FuncHttp.azurewebsites.net/api/collect"
Write-Host "  SB   : $FuncSb"
Write-Host "  KV   : kv-$BaseName-$Environment"
Write-Host ''
