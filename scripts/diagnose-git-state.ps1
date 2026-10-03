<#
.SYNOPSIS
    Diagnoses Git repository state, anomalies, and creates safety snapshots deterministically.
.DESCRIPTION
    Inspects active Git workspace for anomalies (detached HEAD, merge conflicts, ongoing rebases,
    upstream divergence) and optionally creates safety snapshot backup branches before risky Git maneuvers.
.PARAMETER RepoRoot
    Optional path to the git repository root. Defaults to current directory.
.PARAMETER CreateSnapshot
    Switch to automatically create a backup safety snapshot branch.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/diagnose-git-state.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/diagnose-git-state.ps1 -CreateSnapshot
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$CreateSnapshot,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$rawBranch = (git -C $RepoRoot branch --show-current 2>$null)
$branch = if ($rawBranch) { $rawBranch.Trim() } else { "" }
$isDetached = ([string]::IsNullOrWhiteSpace($branch))

# Check conflict files
$conflicts = git -C $RepoRoot diff --name-only --diff-filter=U 2>$null
$conflictList = if ($conflicts) { $conflicts -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } } else { @() }
$hasConflicts = ($conflictList.Count -gt 0)

# Check git internal state files
$gitDir = git -C $RepoRoot rev-parse --git-dir 2>$null
if (-not $gitDir) { $gitDir = Join-Path $RepoRoot ".git" }
$isRebase = (Test-Path (Join-Path $gitDir "rebase-merge")) -or (Test-Path (Join-Path $gitDir "rebase-apply"))
$isMerge = (Test-Path (Join-Path $gitDir "MERGE_HEAD"))
$isCherryPick = (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD"))

# Working tree status
$porcelain = git -C $RepoRoot status --porcelain 2>$null
$uncommittedCount = if ($porcelain) { ($porcelain -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { 0 }

# Upstream tracking
$ahead = 0
$behind = 0
if ($branch) {
    $rawRev = git -C $RepoRoot rev-list --left-right --count "$branch...@{upstream}" 2>$null
    if ($rawRev) {
        $parts = $rawRev.Trim() -split '\s+'
        if ($parts.Length -ge 2) {
            $ahead = [int]$parts[0]
            $behind = [int]$parts[1]
        }
    }
}

$stateName = if ($hasConflicts) { "merge_conflict" }
             elseif ($isRebase) { "rebase_in_progress" }
             elseif ($isMerge) { "merge_in_progress" }
             elseif ($isCherryPick) { "cherry_pick_in_progress" }
             elseif ($isDetached) { "detached_head" }
             elseif ($ahead -gt 0 -and $behind -gt 0) { "diverged" }
             elseif ($uncommittedCount -gt 0) { "dirty" }
             else { "clean" }

$snapshotBranch = $null
if ($CreateSnapshot) {
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $safeBranchName = if ($branch) { $branch -replace '[^a-zA-Z0-9_-]', '-' } else { "detached" }
    $snapshotBranch = "safety-snapshot-${safeBranchName}-${timestamp}"
    git -C $RepoRoot branch $snapshotBranch 2>$null | Out-Null
}

$result = [ordered]@{
    state                   = $stateName
    branch                  = if ($branch) { $branch } else { "DETACHED_HEAD" }
    is_detached_head        = $isDetached
    has_conflicts           = $hasConflicts
    conflicted_files        = $conflictList
    is_rebase_in_progress   = $isRebase
    is_merge_in_progress    = $isMerge
    uncommitted_changes     = $uncommittedCount
    ahead_of_upstream       = $ahead
    behind_upstream         = $behind
    created_snapshot_branch = $snapshotBranch
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Deterministic Git State & Anomaly Diagnostics" -ForegroundColor Cyan
    Write-Host "Branch: $($result.branch) | State: $stateName" -ForegroundColor $(if ($stateName -eq "clean") { "Green" } else { "Yellow" })
    Write-Host "Uncommitted Changes: $uncommittedCount | Ahead: $ahead | Behind: $behind" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($hasConflicts) {
        Write-Host "Active Conflicts ($($conflictList.Count)):" -ForegroundColor Red
        foreach ($cf in $conflictList) { Write-Host "  ! $cf" -ForegroundColor Red }
    }
    if ($snapshotBranch) {
        Write-Host "Safety Snapshot Created: $snapshotBranch" -ForegroundColor Green
    }
}
