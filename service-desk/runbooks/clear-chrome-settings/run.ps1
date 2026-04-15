<#
.SYNOPSIS
    L1 Service Desk - Clear Chrome Settings
.DESCRIPTION
    Pulizia completa delle impostazioni e dati di navigazione di Google Chrome
    per tutti i profili utente presenti sul device.
    Cancella: browsing history, cookies, cache, temp files, session data.
    NON cancella: password salvate, preferiti (bookmarks), estensioni.

    Utilizzo: Run Remediation on-demand da portale Intune (Service Desk L1)
    Intune Remediation: INTUNEUP-MANUAL-ClearChromeSettings
    Context: SYSTEM
    Detection: sempre non-compliant (trigger manuale)
#>

$ErrorActionPreference = "SilentlyContinue"
$EventSource = "IntuneUp"

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName "Application" -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName "Application" -Source $EventSource `
            -EntryType $EntryType -EventId 1200 -Message "[ClearChromeSettings] $Message"
    } catch {}
}

# Cartelle da pulire per ogni profilo Chrome (relative a AppData\Local\Google\Chrome\User Data\{Profile})
$ChromeCleanTargets = @(
    "Cache",
    "Cache2\entries",
    "Cookies",
    "History",
    "History-journal",
    "Network Action Predictor",
    "Network Action Predictor-journal",
    "Top Sites",
    "Top Sites-journal",
    "Visited Links",
    "Web Data",
    "Web Data-journal",
    "Session Storage",
    "Sessions",
    "GPUCache",
    "Media Cache",
    "Application Cache"
)

Write-IntuneLog "Clear Chrome Settings started"

# Chiudi Chrome se in esecuzione
$chromeWasRunning = $false
$chromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
if ($chromeProcs) {
    $chromeWasRunning = $true
    Write-IntuneLog "Chrome is running, stopping processes"
    $chromeProcs | ForEach-Object {
        try { $_.CloseMainWindow() | Out-Null } catch {}
    }
    Start-Sleep -Seconds 3
    # Forza chiusura se ancora attivo
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Seconds 2
}

$totalDeleted = 0
$totalFailed  = 0
$freedBytes   = 0

# Enumera tutti i profili utente
$userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

foreach ($userProfile in $userProfiles) {
    $chromeUserDataPath = "$($userProfile.FullName)\AppData\Local\Google\Chrome\User Data"
    if (-not (Test-Path $chromeUserDataPath)) { continue }

    Write-IntuneLog "Processing Chrome data for user: $($userProfile.Name)"

    # Trova tutti i profili Chrome (Default + Profile 1, Profile 2, ...)
    $chromeProfiles = @(Get-ChildItem -Path $chromeUserDataPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' })

    foreach ($chromeProfile in $chromeProfiles) {
        foreach ($target in $ChromeCleanTargets) {
            $targetPath = Join-Path $chromeProfile.FullName $target
            if (-not (Test-Path $targetPath)) { continue }

            $isDir = (Get-Item $targetPath -ErrorAction SilentlyContinue) -is [System.IO.DirectoryInfo]
            if ($isDir) {
                $files = Get-ChildItem -Path $targetPath -Recurse -Force -File -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    try { $freedBytes += $f.Length; Remove-Item $f.FullName -Force -ErrorAction Stop; $totalDeleted++ }
                    catch { $totalFailed++ }
                }
            } else {
                try {
                    $freedBytes += (Get-Item $targetPath -ErrorAction SilentlyContinue).Length
                    Remove-Item $targetPath -Force -ErrorAction Stop
                    $totalDeleted++
                } catch { $totalFailed++ }
            }
        }
    }

    # Pulizia Cookies cartella radice (file singolo fuori dai profili Chrome)
    $rootCookies = "$chromeUserDataPath\Cookies"
    if (Test-Path $rootCookies) {
        try { Remove-Item $rootCookies -Force -ErrorAction Stop; $totalDeleted++ } catch { $totalFailed++ }
    }
}

$freedMB = [math]::Round($freedBytes / 1MB, 1)
$summary = "Deleted: $totalDeleted items | Failed (in use): $totalFailed | Freed: ~${freedMB} MB"
Write-IntuneLog $summary
Write-Host "Success: $summary"
exit 0
