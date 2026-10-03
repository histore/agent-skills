<#
.SYNOPSIS
    Calculates next SemVer bump and draft changelog deterministically from Conventional Commits.
.DESCRIPTION
    Inspects git commit history since the latest tag (or entire history if no tags exist).
    Identifies breaking changes, new features, and fixes to determine next version (Major, Minor, Patch).
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/calculate-semver.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

# 1. Get latest tag
$latestTag = (git -C $RepoRoot describe --tags --abbrev=0 2>$null)
if (-not $latestTag) {
    $latestTag = "v0.0.0"
    $commits = git -C $RepoRoot log --oneline --no-merges 2>$null
} else {
    $commits = git -C $RepoRoot log "${latestTag}..HEAD" --oneline --no-merges 2>$null
}

# Parse current version
$cleanTag = $latestTag -replace '^v', ''
$parts = $cleanTag -split '\.'
$major = if ($parts.Length -gt 0) { [int]$parts[0] } else { 0 }
$minor = if ($parts.Length -gt 1) { [int]$parts[1] } else { 0 }
$patch = if ($parts.Length -gt 2) { [int]$parts[2] } else { 0 }

$bump = "none"
$breakingChanges = [System.Collections.Generic.List[string]]::new()
$features = [System.Collections.Generic.List[string]]::new()
$fixes = [System.Collections.Generic.List[string]]::new()
$others = [System.Collections.Generic.List[string]]::new()

$commitLines = if ($commits) { $commits -split "`r?`n" } else { @() }

foreach ($c in $commitLines) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    $msg = $c -replace '^[a-f0-9]+\s+', ''

    # Breaking change check
    if ($msg -match '(?i)BREAKING\s+CHANGE|!:') {
        $breakingChanges.Add($msg)
        $bump = "major"
    }
    # Feature check
    elseif ($msg -match '^feat(\([^\)]+\))?:') {
        $features.Add($msg)
        if ($bump -ne "major") { $bump = "minor" }
    }
    # Fix check
    elseif ($msg -match '^fix(\([^\)]+\))?:') {
        $fixes.Add($msg)
        if ($bump -ne "major" -and $bump -ne "minor") { $bump = "patch" }
    }
    else {
        $others.Add($msg)
        if ($bump -eq "none") { $bump = "patch" }
    }
}

if ($bump -eq "major") {
    $major++
    $minor = 0
    $patch = 0
} elseif ($bump -eq "minor") {
    $minor++
    $patch = 0
} elseif ($bump -eq "patch") {
    $patch++
}

$nextTag = "v$major.$minor.$patch"

$result = [ordered]@{
    current_version   = $latestTag
    next_version      = $nextTag
    bump_type         = $bump
    commits_analyzed  = $commitLines.Count
    breaking_changes  = $breakingChanges.ToArray()
    features          = $features.ToArray()
    fixes             = $fixes.ToArray()
    other_changes     = $others.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Deterministic SemVer Calculator" -ForegroundColor Cyan
    Write-Host "Current: $latestTag -> Next: $nextTag (Bump: $bump)" -ForegroundColor Green
    Write-Host "Commits Analyzed: $($commitLines.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($breakingChanges.Count -gt 0) {
        Write-Host "Breaking Changes ($($breakingChanges.Count)):" -ForegroundColor Red
        foreach ($b in $breakingChanges) { Write-Host "  ! $b" -ForegroundColor Red }
    }
    if ($features.Count -gt 0) {
        Write-Host "Features ($($features.Count)):" -ForegroundColor Yellow
        foreach ($f in $features) { Write-Host "  + $f" -ForegroundColor Yellow }
    }
    if ($fixes.Count -gt 0) {
        Write-Host "Fixes ($($fixes.Count)):" -ForegroundColor Cyan
        foreach ($fx in $fixes) { Write-Host "  * $fx" -ForegroundColor Cyan }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}
