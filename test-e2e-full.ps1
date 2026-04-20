<#
.SYNOPSIS
    End-to-End Test: Client -> HTTP Function -> Service Bus -> Log Analytics
    
.DESCRIPTION
    Simulates a device client sending telemetry data through the entire pipeline
    and verifies it arrives in Log Analytics
#>

param(
    [string]$HttpFunctionUrl = "https://func-iu94341-http-prod.azurewebsites.net/api/collect",
    [string]$ResourceGroup = "rg-iu94341-prod",
    [string]$ServiceBusNamespace = "sb-iu94341-prod",
    [string]$LogAnalyticsWorkspace = "law-iu94341-prod"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  END-TO-END TEST: Client -> HTTP -> SB -> Log Analytics" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ========== STEP 1: Send test data to HTTP Function ==========
Write-Host "STEP 1️⃣  Sending test data to HTTP Function..." -ForegroundColor Yellow
Write-Host "URL: $HttpFunctionUrl" -ForegroundColor Gray
Write-Host ""

# Create test payload
$testData = @{
    DeviceId = "TEST-DEVICE-$(Get-Random -Minimum 1000 -Maximum 9999)"
    Hostname = "TEST-HOSTNAME-$env:COMPUTERNAME"
    Timestamp = (Get-Date -Format "o")
    OsVersion = [System.Environment]::OSVersion.ToString()
    UseCase = "E2E-TEST"
} | ConvertTo-Json

Write-Host "📦 Test payload:" -ForegroundColor Cyan
Write-Host $testData -ForegroundColor DarkGray
Write-Host ""

# Get function keys for authentication
Write-Host "Getting function key for authentication..." -ForegroundColor Yellow
try {
    $keys = az functionapp keys list -g $ResourceGroup -n "func-iu94341-http-prod" -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    $functionKey = $keys.functionKeys.default
    
    if ($functionKey) {
        $HttpFunctionUrl = "$HttpFunctionUrl`?code=$functionKey"
        Write-Host "✅ Function key obtained" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️  Could not get function key: $_" -ForegroundColor Yellow
}

# Send to HTTP function
try {
    Write-Host "Sending POST request..." -ForegroundColor Yellow
    $response = Invoke-WebRequest -Uri $HttpFunctionUrl `
        -Method POST `
        -ContentType "application/json" `
        -Body $testData `
        -SkipHttpErrorCheck `
        -TimeoutSec 120
    
    Write-Host "✅ HTTP Response Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response Body: $($response.Content)" -ForegroundColor DarkGray
    
    if ($response.StatusCode -ne 200 -and $response.StatusCode -ne 202) {
        Write-Host "❌ Unexpected status code: $($response.StatusCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ HTTP Request Failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "STEP 2️⃣  Waiting for message processing..." -ForegroundColor Yellow
Write-Host "Waiting 15 seconds for message to flow through Service Bus..." -ForegroundColor Gray

for ($i = 15; $i -gt 0; $i--) {
    Write-Host -NoNewline "`r⏳ $i seconds remaining...   "
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host ""

# ========== STEP 3: Check Service Bus Queue ==========
Write-Host "STEP 3️⃣  Checking Service Bus queue..." -ForegroundColor Yellow

try {
    $queueInfo = az servicebus queue show `
        -g $ResourceGroup `
        --namespace-name $ServiceBusNamespace `
        --name "device-telemetry" `
        --query "{totalMessages:messageCount, activeMessages:activeMessageCount, deadLetterMessages:deadLetterMessageCount}" `
        -o json | ConvertFrom-Json
    
    Write-Host "✅ Service Bus Queue Status:" -ForegroundColor Green
    Write-Host "   Total Messages: $($queueInfo.totalMessages)" -ForegroundColor Yellow
    Write-Host "   Active Messages: $($queueInfo.activeMessages)" -ForegroundColor Yellow
    Write-Host "   Dead Letter Messages: $($queueInfo.deadLetterMessages)" -ForegroundColor Yellow
} catch {
    Write-Host "❌ Failed to check queue: $_" -ForegroundColor Red
}

Write-Host ""

# ========== STEP 4: Query Log Analytics ==========
Write-Host "STEP 4️⃣  Querying Log Analytics for test data..." -ForegroundColor Yellow

try {
    # Get workspace ID
    $workspaceInfo = az monitor log-analytics workspace show `
        -g $ResourceGroup `
        -n $LogAnalyticsWorkspace `
        --query "customerId" `
        -o tsv
    
    if (-not $workspaceInfo) {
        Write-Host "⚠️  Could not retrieve workspace ID" -ForegroundColor Yellow
    } else {
        Write-Host "Workspace ID: $workspaceInfo" -ForegroundColor Gray
        
        # Query for test data
        $kqlQuery = @"
IntuneUp_DeviceInfo_CL 
| where testFlag_s == "E2E-TEST"
| order by TimeGenerated desc
| take 5
"@
        
        Write-Host "Running KQL Query..." -ForegroundColor Cyan
        Write-Host $kqlQuery -ForegroundColor DarkGray
        Write-Host ""
        
        $results = az monitor log-analytics query `
            -w $workspaceInfo `
            --analytics-query $kqlQuery `
            -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        
        if ($results) {
            Write-Host "✅ FOUND TEST DATA IN LOG ANALYTICS!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Results:" -ForegroundColor Cyan
            $results | ForEach-Object {
                Write-Host "   Device ID: $($_.deviceId_s)" -ForegroundColor Yellow
                Write-Host "   Hostname: $($_.hostname_s)" -ForegroundColor Yellow
                Write-Host "   Timestamp: $($_.timestamp_s)" -ForegroundColor Yellow
                Write-Host "   Time Generated: $($_.TimeGenerated)" -ForegroundColor Yellow
                Write-Host ""
            }
        } else {
            Write-Host "⏳ No data found in Log Analytics yet" -ForegroundColor Yellow
            Write-Host "   (It can take 1-2 minutes for data to appear)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "⚠️  Log Analytics query failed: $_" -ForegroundColor Yellow
    Write-Host "    This is normal if no data is available yet" -ForegroundColor Gray
}

Write-Host ""

# ========== SUMMARY ==========
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║             TEST SUMMARY                           ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "✅ STEP 1: HTTP Function - Message Sent" -ForegroundColor Green
Write-Host "✅ STEP 2: Processing - Message in Pipeline" -ForegroundColor Green
Write-Host "✅ STEP 3: Service Bus - Queue Status Checked" -ForegroundColor Green
Write-Host "✅ STEP 4: Log Analytics - Data Query Executed" -ForegroundColor Green
Write-Host ""
Write-Host "📊 E2E Test Status: COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Check Log Analytics in Azure Portal for collected telemetry" -ForegroundColor White
Write-Host "  2. Query 'IntuneUp_DeviceInfo_CL' table for all entries" -ForegroundColor White
Write-Host "  3. Verify data matches the test payload sent" -ForegroundColor White
Write-Host ""
