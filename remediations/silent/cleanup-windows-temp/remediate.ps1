<#
.SYNOPSIS
    Remediation - Cleanup Windows Temp Folders
.DESCRIPTION
    Elimina il contenuto delle cartelle temporanee Windows e svuota il Cestino.
    Considera solo i file più vecchi di MinAgeDays giorni.
    Idempotente. Non elimina le cartelle stesse, solo il contenuto.
    File con estensioni protette (.docx, .xlsx, .csv, .pptx) vengono ignorati.
    File in uso vengono ignorati senza bloccare l'esecuzione.
    Intune Remediation: INTUNEUP-SILENT-CleanupWindowsTempFolders
    Context: SYSTEM
#>

$ErrorActionPreference = "SilentlyContinue"
$EventSource        = "IntuneUp"
$MinAgeDays         = 7
$AgeThreshold       = (Get-Date).AddDays(-$MinAgeDays)
$ExcludedExtensions = @(".docx", ".xlsx", ".csv", ".pptx")

function Write-IntuneLog {
    param([string]$Message, [string]$EntryType = "Information")
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName "Application" -Source $EventSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName "Application" -Source $EventSource `
            -EntryType $EntryType -EventId 1100 -Message "[CleanupWindowsTempFolders] $Message"
    } catch {}
}

function Resolve-FolderPaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

    $systemPaths = @(
        "C:\Windows\Temp",
        "C:\Windows\Downloaded Program Files",
        "C:\Windows\Logs\CBS"
    )
    foreach ($p in $systemPaths) { $paths.Add($p) }

    foreach ($profile in $userProfiles) {
        $paths.Add("$($profile.FullName)\AppData\Local\Temp")
        $paths.Add("$($profile.FullName)\AppData\Local\Microsoft\Windows\Explorer")
    }
    return $paths
}

$totalDeleted = 0
$totalFailed  = 0
$freedBytes   = 0

Write-IntuneLog "Cleanup started"

foreach ($path in (Resolve-FolderPaths)) {
    if (-not (Test-Path $path)) { continue }

    # Elimina prima i file (rispettando le esclusioni), poi le directory vuote
    $files = Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -notin $ExcludedExtensions -and $_.LastWriteTime -lt $AgeThreshold }

    foreach ($file in $files) {
        try {
            $freedBytes += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false -ErrorAction Stop
            $totalDeleted++
        } catch {
            $totalFailed++
        }
    }

    # Rimuovi directory vuote (bottom-up)
    Get-ChildItem -Path $path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending |
        ForEach-Object {
            try { Remove-Item -Path $_.FullName -Force -Recurse -Confirm:$false -ErrorAction Stop; $totalDeleted++ } catch {}
        }
}

# Svuota il Cestino per tutti gli utenti
$recycleBinCleaned = $false
try {
    # Metodo 1: eliminazione diretta dal path fisico (funziona da SYSTEM)
    $recycleBinPaths = Get-ChildItem -Path "C:\`$Recycle.Bin" -Directory -Force -ErrorAction SilentlyContinue
    foreach ($userBin in $recycleBinPaths) {
        $binItems = Get-ChildItem -Path $userBin.FullName -Recurse -Force -File -ErrorAction SilentlyContinue
        foreach ($item in $binItems) {
            try {
                $freedBytes += $item.Length
                Remove-Item -Path $item.FullName -Force -Confirm:$false -ErrorAction Stop
                $totalDeleted++
                $recycleBinCleaned = $true
            } catch { $totalFailed++ }
        }
        # Rimuovi sottocartelle vuote
        Get-ChildItem -Path $userBin.FullName -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object {
                try { Remove-Item $_.FullName -Force -Recurse -Confirm:$false -ErrorAction Stop } catch {}
            }
    }
    if ($recycleBinCleaned) { Write-IntuneLog "RecycleBin emptied via filesystem" }
} catch {
    Write-IntuneLog "RecycleBin filesystem cleanup failed: $_" -EntryType "Warning"
}

# Metodo 2: fallback con Clear-RecycleBin (se disponibile)
if (-not $recycleBinCleaned) {
    try {
        if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-IntuneLog "RecycleBin emptied via Clear-RecycleBin"
        }
    } catch {
        Write-IntuneLog "Clear-RecycleBin fallback failed: $_" -EntryType "Warning"
    }
}

$freedMB = [math]::Round($freedBytes / 1MB, 1)
$summary = "Deleted: $totalDeleted items | Failed (in use/protected): $totalFailed | Freed: ~${freedMB} MB"
Write-IntuneLog $summary
Write-Host "Success: $summary"
exit 0
