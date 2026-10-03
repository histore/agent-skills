<#
.SYNOPSIS
    Identifies unreferenced media assets and orphaned modular documentation files deterministically.
.DESCRIPTION
    Scans repository for images/assets (.png, .jpg, .svg, .gif, .webp, .ico) and checks whether they
    are referenced in Markdown, HTML, or source code. Also verifies that modular documentation files
    in docs/ are referenced by the root index files (ARCHITECTURE.md or REQUIREMENTS.md).
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Strict
    Switch to exit with non-zero exit code if orphaned assets are found.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/find-orphaned-assets.ps1 -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$Strict,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

# 1. Collect all asset files
$assetExtensions = @(".png", ".jpg", ".jpeg", ".svg", ".gif", ".webp", ".ico")
$allFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|bin|obj|node_modules|target)[\\/]' }

$assetFiles = $allFiles | Where-Object { $_.Extension.ToLower() -in $assetExtensions }
$textFiles = $allFiles | Where-Object { $_.Extension.ToLower() -in @(".md", ".html", ".htm", ".json", ".xml", ".yaml", ".yml", ".cs", ".rs", ".ts", ".js", ".py", ".go", ".css") }

# Build index of file contents (cache text for fast lookup)
$searchCorpus = [System.Collections.Generic.List[string]]::new()
foreach ($tf in $textFiles) {
    $c = Get-Content -Path $tf.FullName -Raw -ErrorAction SilentlyContinue
    if ($c) {
        $searchCorpus.Add($c)
    }
}

$orphanedAssets = [System.Collections.Generic.List[string]]::new()

# Check each asset
foreach ($asset in $assetFiles) {
    $leaf = $asset.Name
    $found = $false
    foreach ($text in $searchCorpus) {
        if ($text.IndexOf($leaf, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $found = $true
            break
        }
    }
    if (-not $found) {
        $relPath = [System.IO.Path]::GetRelativePath($RepoRoot, $asset.FullName).Replace('\', '/')
        $orphanedAssets.Add($relPath)
    }
}

# 2. Check orphaned modular doc files
$orphanedDocs = [System.Collections.Generic.List[string]]::new()
$archIndex = Join-Path $RepoRoot "ARCHITECTURE.md"
$reqIndex = Join-Path $RepoRoot "REQUIREMENTS.md"

$archContent = if (Test-Path $archIndex) { Get-Content -Path $archIndex -Raw } else { "" }
$reqContent = if (Test-Path $reqIndex) { Get-Content -Path $reqIndex -Raw } else { "" }

$modArchDir = Join-Path $RepoRoot "docs/architecture/modules"
if (Test-Path $modArchDir) {
    $modArchFiles = Get-ChildItem -Path $modArchDir -Filter "*.md" -File -ErrorAction SilentlyContinue
    foreach ($mf in $modArchFiles) {
        if ($archContent.IndexOf($mf.Name, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $mf.FullName).Replace('\', '/')
            $orphanedDocs.Add($rel)
        }
    }
}

$modReqDir = Join-Path $RepoRoot "docs/requirements/modules"
if (Test-Path $modReqDir) {
    $modReqFiles = Get-ChildItem -Path $modReqDir -Filter "*.md" -File -ErrorAction SilentlyContinue
    foreach ($rf in $modReqFiles) {
        if ($reqContent.IndexOf($rf.Name, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $rf.FullName).Replace('\', '/')
            $orphanedDocs.Add($rel)
        }
    }
}

$totalOrphans = $orphanedAssets.Count + $orphanedDocs.Count
$status = if ($totalOrphans -gt 0) { "warning" } else { "pass" }

$result = [ordered]@{
    status               = $status
    assets_scanned       = $assetFiles.Count
    orphaned_assets      = $orphanedAssets.ToArray()
    orphaned_docs        = $orphanedDocs.ToArray()
    total_orphaned_count = $totalOrphans
    message              = if ($totalOrphans -eq 0) { "No orphaned assets or modular documentation files detected." } else { "Found $totalOrphans orphaned file(s)." }
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Orphaned Assets & Modular Docs Audit Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq "pass") { "Green" } else { "Yellow" })
    Write-Host "Assets Scanned: $($assetFiles.Count)"
    Write-Host "Total Orphaned: $totalOrphans"
    if ($orphanedAssets.Count -gt 0) {
        Write-Host "Orphaned Assets:"
        foreach ($oa in $orphanedAssets) { Write-Host "  - $oa" -ForegroundColor Yellow }
    }
    if ($orphanedDocs.Count -gt 0) {
        Write-Host "Unindexed Modular Docs:"
        foreach ($od in $orphanedDocs) { Write-Host "  - $od" -ForegroundColor Yellow }
    }
}

if ($Strict -and $totalOrphans -gt 0) {
    exit 1
} else {
    exit 0
}
