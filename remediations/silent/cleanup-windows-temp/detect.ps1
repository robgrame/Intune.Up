<#
.SYNOPSIS
    Detection - Cleanup Windows Temp Folders
.DESCRIPTION
    Verifica se le cartelle temporanee contengono file da eliminare (escluse estensioni protette).
    Considera solo i file più vecchi di MinAgeDays giorni.
    Non compliant se almeno una cartella contiene file eleggibili.
    Il Cestino viene controllato senza filtro di età.
    Intune Remediation: INTUNEUP-SILENT-CleanupWindowsTempFolders
    Schedule: 2 volte a settimana
    Context: SYSTEM
#>

$ErrorActionPreference = "SilentlyContinue"

# Solo file più vecchi di questa soglia (giorni)
$MinAgeDays         = 7
$AgeThreshold       = (Get-Date).AddDays(-$MinAgeDays)

# Estensioni escluse dalla pulizia
$ExcludedExtensions = @(".docx", ".xlsx", ".csv", ".pptx")

# Cartelle da controllare (per path utente: enumera tutti i profili in C:\Users)
function Resolve-FolderPaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

    $rawList = @(
        "C:\Windows\Temp",
        "C:\Windows\Downloaded Program Files",
        "C:\Windows\Logs\CBS"
        # Le path utente vengono espanse sotto
    )
    foreach ($p in $rawList) { $paths.Add($p) }

    foreach ($profile in $userProfiles) {
        $paths.Add("$($profile.FullName)\AppData\Local\Temp")
        $paths.Add("$($profile.FullName)\AppData\Local\Microsoft\Windows\Explorer")
    }
    return $paths
}

$hasContent = $false
$report     = [System.Collections.Generic.List[string]]::new()

foreach ($path in (Resolve-FolderPaths)) {
    if (-not (Test-Path $path)) { continue }
    try {
        $items = Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -notin $ExcludedExtensions -and $_.LastWriteTime -lt $AgeThreshold }
        if ($items.Count -gt 0) {
            $hasContent = $true
            $report.Add("$path ($($items.Count) items)")
        }
    } catch {}
}

# Controlla il Cestino
try {
    $shell    = New-Object -ComObject Shell.Application
    $recycleBin = $shell.Namespace(0xA)  # CSIDL_BITBUCKET
    if ($recycleBin.Items().Count -gt 0) {
        $hasContent = $true
        $report.Add("RecycleBin ($($recycleBin.Items().Count) items)")
    }
} catch {}

if ($hasContent) {
    Write-Host "Non compliant - folders with content: $($report -join '; ')"
    exit 1
}

Write-Host "Compliant - all temp folders are clean"
exit 0
