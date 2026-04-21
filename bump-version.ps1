<#
.SYNOPSIS
    Bumps the semantic version in VERSION file based on Conventional Commits.

.DESCRIPTION
    Reads the latest commit message and bumps:
    - MAJOR: commit contains "BREAKING CHANGE" or "!" after type (e.g., feat!:)
    - MINOR: commit type is "feat"
    - PATCH: commit type is "fix", "docs", "chore", "refactor", etc.

    Also creates a git tag and updates VERSION file.

.PARAMETER DryRun
    Show what would happen without making changes.

.EXAMPLE
    .\bump-version.ps1
    .\bump-version.ps1 -DryRun
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$versionFile = Join-Path $PSScriptRoot 'VERSION'
$currentVersion = (Get-Content $versionFile -Raw).Trim()

if ($currentVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
    Write-Host "❌ Invalid version format in VERSION file: '$currentVersion'" -ForegroundColor Red
    exit 1
}

$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]

# Get the latest commit message
$commitMsg = git log -1 --pretty=%B
if ($LASTEXITCODE -ne 0 -or -not $commitMsg) {
    Write-Host "❌ No git commits found" -ForegroundColor Red
    exit 1
}

$fullMsg = $commitMsg -join "`n"
$firstLine = ($commitMsg -split "`n")[0].Trim()

Write-Host "Current version: $currentVersion" -ForegroundColor Cyan
Write-Host "Last commit: $firstLine" -ForegroundColor Gray

# Determine bump type based on Conventional Commits
$bumpType = 'patch'

if ($fullMsg -match 'BREAKING CHANGE' -or $firstLine -match '^[a-z]+!:') {
    $bumpType = 'major'
} elseif ($firstLine -match '^feat(\(.+\))?:') {
    $bumpType = 'minor'
}

# Apply bump
switch ($bumpType) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    'patch' { $patch++ }
}

$newVersion = "$major.$minor.$patch"

Write-Host ""
Write-Host "Bump: $bumpType" -ForegroundColor Yellow
Write-Host "New version: $currentVersion → $newVersion" -ForegroundColor Green

if ($DryRun) {
    Write-Host ""
    Write-Host "(Dry run — no changes made)" -ForegroundColor Gray
    exit 0
}

# Update VERSION file
Set-Content -Path $versionFile -Value "$newVersion`n" -NoNewline
Write-Host "✅ Updated VERSION file" -ForegroundColor Green

# Stage, commit, and tag
git add $versionFile
git commit -m "chore: bump version to $newVersion" --no-verify
git tag -a "v$newVersion" -m "Release v$newVersion"

Write-Host "✅ Created tag v$newVersion" -ForegroundColor Green
$currentBranch = git rev-parse --abbrev-ref HEAD
Write-Host ""
Write-Host "To push: git push origin $currentBranch --tags" -ForegroundColor Cyan
