<#
.SYNOPSIS
    Lints documentation integrity, validates internal relative links, and checks architecture parity.
.DESCRIPTION
    Scans repository markdown files for broken relative links and anchors.
    Optionally audits architecture modular parity to ensure src/ modules have corresponding
    docs/architecture/modules/*.md specifications with zero LLM tokens.
.PARAMETER RepoRoot
    Optional root path of the repository. Defaults to current directory.
.PARAMETER CheckParity
    Switch to verify that src/ subdirectories have corresponding architecture module docs.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-docs.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-docs.ps1 -CheckParity
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$CheckParity,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$mdFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter "*.md" | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and
    $_.FullName -notmatch '[\\/]node_modules[\\/]'
}

$brokenLinks = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalLinksChecked = 0

# Match markdown links: [text](path)
$linkRegex = '\[([^\]]+)\]\(([^)]+)\)'

foreach ($file in $mdFiles) {
    $fileDir = $file.DirectoryName
    $relSource = $file.FullName.Replace($RepoRoot + "\", "").Replace($RepoRoot + "/", "")
    $lines = Get-Content -Path $file.FullName -Encoding UTF8

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $matches = [regex]::Matches($line, $linkRegex)
        foreach ($m in $matches) {
            $rawTarget = $m.Groups[2].Value.Trim()

            # Skip web URLs, mailto, or self-anchors
            if ($rawTarget -match '^(https?://|mailto:|#|file://)') {
                continue
            }

            # Strip anchor if present
            $targetPathOnly = ($rawTarget -split '#')[0]
            if ([string]::IsNullOrWhiteSpace($targetPathOnly)) { continue }

            # Strip query params if present
            $targetPathOnly = ($targetPathOnly -split '\?')[0]

            $totalLinksChecked++

            # Resolve relative to current markdown file
            $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $fileDir $targetPathOnly))
            if (-not (Test-Path $resolvedPath)) {
                $brokenLinks.Add([PSCustomObject]@{
                    SourceFile = $relSource
                    Line = $i + 1
                    Target = $rawTarget
                    Resolved = $resolvedPath
                })
            }
        }
    }
}

# Optional Architecture Parity check
$parityMismatches = [System.Collections.Generic.List[string]]::new()
if ($CheckParity) {
    $srcDir = Join-Path $RepoRoot "src"
    $archModDir = Join-Path $RepoRoot "docs\architecture\modules"
    if ((Test-Path $srcDir) -and (Test-Path $archModDir)) {
        $srcModules = Get-ChildItem -Path $srcDir -Directory | Select-Object -ExpandProperty Name
        foreach ($mod in $srcModules) {
            $expectedSpec = Join-Path $archModDir "$mod.md"
            if (-not (Test-Path $expectedSpec)) {
                $parityMismatches.Add("Module 'src/$mod' missing spec in docs/architecture/modules/$mod.md")
            }
        }
    }
}

$isPass = ($brokenLinks.Count -eq 0 -and $parityMismatches.Count -eq 0)

$result = [ordered]@{
    status               = if ($isPass) { "pass" } else { "fail" }
    scanned_markdowns    = $mdFiles.Count
    links_checked        = $totalLinksChecked
    broken_links_count   = $brokenLinks.Count
    broken_links         = $brokenLinks.ToArray()
    parity_mismatches    = $parityMismatches.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Deterministic Documentation & Link Integrity Linter" -ForegroundColor Cyan
    Write-Host "Markdown Files: $($mdFiles.Count) | Links Checked: $totalLinksChecked" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($isPass) {
        Write-Host "Documentation Status: PASS (0 broken relative links)" -ForegroundColor Green
    } else {
        Write-Host "Documentation Status: FAIL ($($brokenLinks.Count) broken links, $($parityMismatches.Count) parity gaps)" -ForegroundColor Red
        foreach ($bl in $brokenLinks) {
            Write-Host "  [Broken Link] $($bl.SourceFile):$($bl.Line) -> $($bl.Target)" -ForegroundColor Yellow
        }
        foreach ($pm in $parityMismatches) {
            Write-Host "  [Parity Gap] $pm" -ForegroundColor Yellow
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if (-not $isPass) {
    exit 1
}
