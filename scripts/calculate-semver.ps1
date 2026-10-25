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
    [switch]$CheckSync,

    [Parameter(Mandatory = $false)]
    [switch]$ExecuteTagAndPush,

    [Parameter(Mandatory = $false)]
    [string]$VersionOverride,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

# 1. Inspect branch and working tree state
$currentBranch = (git -C $RepoRoot branch --show-current 2>$null)
if (-not $currentBranch) { $currentBranch = "HEAD" }

$uncommitted = (git -C $RepoRoot status --porcelain 2>$null) | Where-Object {
    $_ -notmatch '^\s*[MADRCU?!\s]\s+(_agents|\.agents)(\/|$)'
}
$isClean = [string]::IsNullOrWhiteSpace($uncommitted)

$behindCount = 0
$aheadCount = 0
if ($CheckSync -or $ExecuteTagAndPush) {
    git -C $RepoRoot fetch origin main 2>$null
    $revCount = (git -C $RepoRoot rev-list --left-right --count main...origin/main 2>$null)
    if ($revCount -match '(\d+)\s+(\d+)') {
        $behindCount = [int]$matches[2]
        $aheadCount = [int]$matches[1]
    }
}

# 2. Get highest SemVer tag reliably
$rawTags = (git -C $RepoRoot tag -l "v[0-9]*" --sort=-v:refname 2>$null)
$latestTag = if ($rawTags -and $rawTags.Count -gt 0) { $rawTags[0] } else { $null }

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

$commitLines = if ($commits) { $commits -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } } else { @() }

foreach ($c in $commitLines) {
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

$nextTag = if ($VersionOverride) {
    if ($VersionOverride -match '^v') { $VersionOverride } else { "v$VersionOverride" }
} else {
    "v$major.$minor.$patch"
}

# Construct formatted release notes
$notes = [System.Text.StringBuilder]::new()
[void]$notes.AppendLine("## Release $nextTag")
if ($breakingChanges.Count -gt 0) {
    [void]$notes.AppendLine("### Breaking Changes")
    foreach ($b in $breakingChanges) { [void]$notes.AppendLine("- $b") }
}
if ($features.Count -gt 0) {
    [void]$notes.AppendLine("### Features")
    foreach ($f in $features) { [void]$notes.AppendLine("- $f") }
}
if ($fixes.Count -gt 0) {
    [void]$notes.AppendLine("### Bug Fixes")
    foreach ($fx in $fixes) { [void]$notes.AppendLine("- $fx") }
}
if ($others.Count -gt 0) {
    [void]$notes.AppendLine("### Maintenance & Documentation")
    foreach ($o in $others) { [void]$notes.AppendLine("- $o") }
}

$tagPushed = $false
if ($ExecuteTagAndPush) {
    if ($currentBranch -ne "main") {
        throw "Cannot tag release on branch '$currentBranch': releases must be created strictly on 'main'."
    }
    if (-not $isClean) {
        throw "Working tree has uncommitted host files. Commit or stash changes before releasing."
    }
    if ($behindCount -gt 0) {
        throw "Local branch is behind origin/main ($behindCount commits). Run 'git pull origin main' first."
    }
    
    $tagMsg = "Release $nextTag"
    git -C $RepoRoot tag -a $nextTag -m $tagMsg 2>$null
    git -C $RepoRoot push origin $nextTag 2>$null
    $tagPushed = ($LASTEXITCODE -eq 0)
}

$result = [ordered]@{
    current_branch    = $currentBranch
    is_main           = ($currentBranch -eq "main")
    is_clean          = $isClean
    behind_origin     = $behindCount
    ahead_origin      = $aheadCount
    current_version   = $latestTag
    next_version      = $nextTag
    bump_type         = $bump
    commits_analyzed  = $commitLines.Count
    breaking_changes  = $breakingChanges.ToArray()
    features          = $features.ToArray()
    fixes             = $fixes.ToArray()
    release_notes     = $notes.ToString().Trim()
    tag_pushed        = $tagPushed
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    if ($tagPushed) {
        Write-Host "Release Tag: SUCCESS $nextTag created and pushed on main" -ForegroundColor Green
    } else {
        Write-Host "SemVer Pre-Flight: $latestTag -> $nextTag (Bump: $bump, Commits: $($commitLines.Count), Branch: $currentBranch)" -ForegroundColor Cyan
        if ($breakingChanges.Count -gt 0) {
            Write-Host "  ! BREAKING CHANGES detected: $($breakingChanges.Count)" -ForegroundColor Red
        }
    }
}
