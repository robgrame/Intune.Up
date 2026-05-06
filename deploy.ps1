<#
.SYNOPSIS
    Intune.Up - Full deployment script
    Executes: Build -> Publish -> Bicep infra -> Zip deploy function apps -> Runbook

.PARAMETER Environment
    Target environment: dev, test, prod (default: dev)

.PARAMETER Location
    Azure region for deployment (default: westeurope)

.PARAMETER ResourceGroup
    Azure Resource Group (default: rg-{BaseName}-{Environment})

.PARAMETER BaseName
    Base name for resource naming (default: intuneup)

.PARAMETER SubscriptionId
    Azure Subscription ID. If provided, all az commands use this subscription.
    Prevents accidental deployment to wrong subscription.

.PARAMETER AllowedIssuerThumbprints
    Comma-separated CA thumbprints for mTLS validation.
    If omitted and Bicep runs, you will be prompted.

.PARAMETER SkipBuild
    Skip dotnet build/publish (reuse existing publish/ output)

.PARAMETER SkipBicep
    Skip Bicep infrastructure deployment

.PARAMETER SkipFunctionDeploy
    Skip zip deploy of function apps

.PARAMETER SkipRunbook
    Skip automation runbook deployment

.EXAMPLE
    .\deploy.ps1 -BaseName iu001 -Environment test
    .\deploy.ps1 -BaseName iu001 -Environment test -SubscriptionId 'b45c5b53-...'
    .\deploy.ps1 -BaseName iu001 -Environment test -SkipBuild -SkipBicep
    .\deploy.ps1 -BaseName iu001 -Environment test -SkipBuild -SkipBicep -SkipFunctionDeploy
#>
[CmdletBinding()]
param(
    [ValidateSet('dev','dev2','test','prod')]
    [string]$Environment = 'dev',

    [string]$Location = 'westeurope',

    [string]$ResourceGroup = '',

    [string]$BaseName = 'intuneup',

    [string]$SubscriptionId = '',

    [string]$AllowedIssuerThumbprints = '',

    [switch]$DeployApim,
    [switch]$DeployTimerFunction,
    [switch]$NoAutomationAccount,

    [switch]$SkipBuild,
    [switch]$SkipBicep,
    [switch]$SkipFunctionDeploy,
    [switch]$SkipRunbook
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$m) Write-Host "`n>> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "   OK  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "   WARN $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "   FAIL $m" -ForegroundColor Red; exit 1 }

# Force lowercase for Azure resource naming consistency
$BaseName    = $BaseName.ToLower()
$Environment = $Environment.ToLower()
$Location    = $Location.ToLower()
if (-not $ResourceGroup) { $ResourceGroup = "rg-$BaseName-$Environment" }
$ResourceGroup = $ResourceGroup.ToLower()

# Build --subscription flag for all az commands
$subParam = @()
if ($SubscriptionId) { $subParam = @('--subscription', $SubscriptionId) }

$RepoRoot    = $PSScriptRoot
$SrcDir      = Join-Path $RepoRoot 'src'
$BicepDir    = Join-Path $RepoRoot 'infrastructure\bicep'
$PublishDir  = Join-Path $RepoRoot 'publish'
$HttpProj    = Join-Path $SrcDir 'IntuneUp.Collector.Http\IntuneUp.Collector.Http.csproj'
$SbProj      = Join-Path $SrcDir 'IntuneUp.Collector.ServiceBus\IntuneUp.Collector.ServiceBus.csproj'
$TimerProj   = Join-Path $SrcDir 'IntuneUp.Jobs.PasswordExpiry\IntuneUp.Jobs.PasswordExpiry.csproj'
$HttpOut     = Join-Path $PublishDir 'http'
$SbOut       = Join-Path $PublishDir 'sb'
$TimerOut    = Join-Path $PublishDir 'timer'
$HttpZip     = Join-Path $PublishDir 'http.zip'
$SbZip       = Join-Path $PublishDir 'sb.zip'
$TimerZip    = Join-Path $PublishDir 'timer.zip'
$MainBicep   = Join-Path $BicepDir 'main.bicep'
$FuncHttp    = "func-$BaseName-http-$Environment"
$FuncSb      = "func-$BaseName-sb-$Environment"
$FuncTimer   = "func-$BaseName-timer-$Environment"
$AAName      = "aa-$BaseName-$Environment"
$ScriptVersion = (Get-Content (Join-Path $RepoRoot 'VERSION') -ErrorAction SilentlyContinue).Trim()

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host "   Intune.Up - Full Deploy Script  v$ScriptVersion" -ForegroundColor DarkCyan
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host "  Environment   : $Environment"
Write-Host "  Location      : $Location"
Write-Host "  ResourceGroup : $ResourceGroup"
Write-Host "  BaseName      : $BaseName"
$subDisplay = $(if ($SubscriptionId) { $SubscriptionId } else { '(current default)' })
Write-Host "  Subscription  : $subDisplay"
Write-Host "  HTTP Function : $FuncHttp"
Write-Host "  SB Function   : $FuncSb"
Write-Host "  SkipBuild     : $SkipBuild"
Write-Host "  SkipBicep     : $SkipBicep"
Write-Host "  SkipFuncDeploy: $SkipFunctionDeploy"
Write-Host "  SkipRunbook   : $SkipRunbook"
Write-Host ''

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
Write-Step 'Pre-flight checks'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Fail 'Azure CLI not found. Install from https://aka.ms/installazurecliwindows'
}

# Set and verify subscription
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to set subscription: $SubscriptionId" }
}

$accountJson = az account show -o json
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

$rgExists = az group exists --name $ResourceGroup @subParam
if ($rgExists -ne 'true') { 
    Write-Step "Creating resource group: $ResourceGroup in $Location"
    az group create --name $ResourceGroup --location $Location @subParam --output none
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to create resource group: $ResourceGroup" }
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

    Write-Step 'Publishing Timer function (PasswordExpiry)'
    if (Test-Path $TimerOut) { Remove-Item $TimerOut -Recurse -Force }
    dotnet publish $TimerProj -c Release -o $TimerOut --no-build --nologo
    if ($LASTEXITCODE -ne 0) { Write-Fail 'Publish Timer failed.' }
    Write-Ok "Published to $TimerOut"

    Write-Step 'Creating ZIP packages'
    if (Test-Path $HttpZip)  { Remove-Item $HttpZip -Force }
    if (Test-Path $SbZip)    { Remove-Item $SbZip -Force }
    if (Test-Path $TimerZip) { Remove-Item $TimerZip -Force }
    Compress-Archive -Path "$HttpOut\*"  -DestinationPath $HttpZip
    Compress-Archive -Path "$SbOut\*"    -DestinationPath $SbZip
    Compress-Archive -Path "$TimerOut\*" -DestinationPath $TimerZip
    $httpMB  = [math]::Round((Get-Item $HttpZip).Length / 1MB, 1)
    $sbMB    = [math]::Round((Get-Item $SbZip).Length   / 1MB, 1)
    $timerMB = [math]::Round((Get-Item $TimerZip).Length / 1MB, 1)
    Write-Ok "http.zip : ${httpMB} MB"
    Write-Ok "sb.zip   : ${sbMB} MB"
    Write-Ok "timer.zip: ${timerMB} MB"

} else {
    Write-Warn 'SkipBuild: using existing publish/ output'
    if (-not (Test-Path $HttpZip))  { Write-Fail 'http.zip not found. Run without -SkipBuild first.' }
    if (-not (Test-Path $SbZip))    { Write-Fail 'sb.zip not found. Run without -SkipBuild first.' }
    if (-not (Test-Path $TimerZip)) { Write-Fail 'timer.zip not found. Run without -SkipBuild first.' }
    Write-Ok 'Existing ZIPs found'
}

# --------------------------------------------------------------------------
# Step 2: Bicep infrastructure
# --------------------------------------------------------------------------
if (-not $SkipBicep) {

    Write-Step 'Deploying Bicep infrastructure'
    Write-Host "  Template: $MainBicep"
    Write-Host "  Location: $Location"

    $bicepDeployApim = if ($DeployApim) { 'true' } else { 'false' }
    $bicepDeployTimer = if ($DeployTimerFunction) { 'true' } else { 'false' }
    $bicepDeployAA = if ($NoAutomationAccount) { 'false' } else { 'true' }

    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file  $MainBicep `
        --parameters     environment=$Environment `
                         baseName=$BaseName `
                         location=$Location `
                         allowedIssuerThumbprints=$AllowedIssuerThumbprints `
                         deployApim=$bicepDeployApim `
                         deployTimerFunction=$bicepDeployTimer `
                         deployAutomationAccount=$bicepDeployAA `
        @subParam `
        --output table

    if ($LASTEXITCODE -ne 0) { Write-Fail 'Bicep deployment failed.' }
    Write-Ok 'Infrastructure deployed'

    Write-Step 'Assigning deployer RBAC (Table Data Contributor on password-expiry storage)'
    $deployerObjectId = az ad signed-in-user show --query "id" -o tsv
    $peStorageName = "st${BaseName}pe${Environment}"
    $peStorageId = az storage account show -g $ResourceGroup -n $peStorageName @subParam --query "id" -o tsv
    if ($deployerObjectId -and $peStorageId) {
        az role assignment create --assignee $deployerObjectId --role "Storage Table Data Contributor" --scope $peStorageId -o none
        Write-Ok "Deployer RBAC assigned on $peStorageName"
    } else {
        Write-Warn "Could not assign deployer RBAC (deployer OID: $deployerObjectId, storage: $peStorageId)"
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
            --resource-group $RG --name $AppName --src $ZipPath --timeout 180 @subParam 2>&1
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

    Write-Step "Deploying Timer function: $FuncTimer"
    if (-not (Deploy-FunctionZip -RG $ResourceGroup -AppName $FuncTimer -ZipPath $TimerZip)) {
        Write-Warn "Timer function deploy failed (may not exist if deployTimerFunction=false in Bicep)."
    } else {
        Write-Ok "$FuncTimer deployed"
    }

} else {
    Write-Warn 'SkipFunctionDeploy: function app deployment skipped'
}

# --------------------------------------------------------------------------
# Step 4: Deploy Automation Runbook content
# --------------------------------------------------------------------------
if (-not $SkipRunbook) {

    $runbookScript = Join-Path $RepoRoot 'service-desk\runbooks\server-side\Write-PasswordExpiryTriggers.ps1'

    if (Test-Path $runbookScript) {
        Write-Step "Deploying Automation Runbook: Write-PasswordExpiryTriggers"

        az automation runbook replace-content `
            --resource-group $ResourceGroup `
            --automation-account-name $AAName `
            --name 'Write-PasswordExpiryTriggers' `
            --content "@$runbookScript" `
            @subParam `
            -o none

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Runbook content upload failed"
        } else {
            az automation runbook publish `
                --resource-group $ResourceGroup `
                --automation-account-name $AAName `
                --name 'Write-PasswordExpiryTriggers' `
                @subParam `
                -o none

            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Runbook publish failed"
            } else {
                Write-Ok "Runbook published"

                # Create daily schedule and link to runbook with parameters
                $scheduleName = "Daily-PasswordExpiry"
                $peStorageName = "st${BaseName}pe${Environment}"
                $scheduleStart = (Get-Date).AddDays(1).ToString("yyyy-MM-ddT06:00:00+00:00")

                Write-Step "Creating daily schedule and linking to runbook"

                # Create schedule (ignore if already exists)
                az automation schedule create `
                    --resource-group $ResourceGroup `
                    --automation-account-name $AAName `
                    --name $scheduleName `
                    --frequency Day --interval 1 `
                    --start-time $scheduleStart `
                    --time-zone "W. Europe Standard Time" `
                    @subParam `
                    -o none 2>&1 | Out-Null

                # Link schedule to runbook with parameters via REST API
                $aaId = az automation account show -g $ResourceGroup -n $AAName @subParam --query "id" -o tsv
                $jobScheduleId = [guid]::NewGuid().ToString()
                $linkBody = @{
                    properties = @{
                        schedule = @{ name = $scheduleName }
                        runbook  = @{ name = "Write-PasswordExpiryTriggers" }
                        parameters = @{
                            StorageAccountName = $peStorageName
                            MaxPasswordAgeDays = "90"
                            ThresholdDays      = "10"
                        }
                    }
                } | ConvertTo-Json -Depth 4

                az rest --method PUT `
                    --uri "$aaId/jobSchedules/$($jobScheduleId)?api-version=2023-11-01" `
                    --body $linkBody `
                    -o none 2>&1 | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    Write-Ok "Schedule '$scheduleName' linked to runbook with parameters"
                    Write-Host "    StorageAccountName=$peStorageName MaxPasswordAgeDays=90 ThresholdDays=10" -ForegroundColor Gray
                } else {
                    Write-Warn "Schedule link failed — configure manually in Azure Portal"
                }
            }
        }
    } else {
        Write-Warn "Runbook script not found at $runbookScript"
    }

} else {
    Write-Warn 'SkipRunbook: runbook deployment skipped'
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host '   Deploy completed successfully!           ' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green
Write-Host ''
Write-Host "  HTTP     : https://$FuncHttp.azurewebsites.net/api/collect"
Write-Host "  SB       : $FuncSb"
Write-Host "  KV       : kv-$BaseName-$Environment"
Write-Host "  Runbook  : $AAName / Write-PasswordExpiryTriggers"
$versionText = (Get-Content (Join-Path $RepoRoot 'VERSION') -ErrorAction SilentlyContinue)
Write-Host "  Version  : $versionText"
Write-Host ''
$testCmd = ".\test-e2e-full.ps1 -BaseName $BaseName -Environment $Environment"
if ($SubscriptionId) { $testCmd += " -SubscriptionId $SubscriptionId" }
Write-Host "  Test E2E : $testCmd"
Write-Host ''
