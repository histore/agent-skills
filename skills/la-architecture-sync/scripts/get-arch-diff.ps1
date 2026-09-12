#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes git deltas since the last architectural sync checkpoint and detects relevant code changes.

.DESCRIPTION
    Inspects git changes between the checkpoint commit recorded in .arch-sync.json and HEAD.
    Filters out non-architectural files (tests, assets, markdown, generated code).
    Outputs a structured JSON payload for consumption by the la-architecture-sync subagent.
    Consumes 0 LLM tokens during inspection and filtering.

.PARAMETER StateFile
    Path to the JSON state file storing the last analyzed commit hash.
    Default: docs/architecture/.arch-sync.json

.PARAMETER UpdateCheckpoint
    Switch to record current HEAD into the state file as the new baseline checkpoint.

.PARAMETER Init
    Switch to scaffold the initial docs/architecture directory structure, templates, and baseline checkpoint.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -Init
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -UpdateCheckpoint
#>

[CmdletBinding()]
param(
    [string]$StateFile = "docs/architecture/.arch-sync.json",
    [switch]$UpdateCheckpoint,
    [switch]$Init
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GitHeadCommit {
    $commit = git rev-parse HEAD 2>$null
    if (-not $commit) {
        throw "Not inside a valid git repository or git is unavailable."
    }
    return $commit.Trim()
}

$headCommit = Get-GitHeadCommit

# Handle checkpoint update request
if ($UpdateCheckpoint) {
    $stateDir = Split-Path -Path $StateFile -Parent
    if ($stateDir -and -not (Test-Path -Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $payload = @{
        last_synced_commit = $headCommit
        last_synced_at     = $timestamp
    } | ConvertTo-Json -Depth 4

    # Ensure LF line endings
    $fullPath = if ([System.IO.Path]::IsPathRooted($StateFile)) { $StateFile } else { Join-Path (Get-Location) $StateFile }
    [System.IO.File]::WriteAllText($fullPath, ($payload.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Architecture sync checkpoint updated to $headCommit ($timestamp)"
    exit 0
}

# Handle initialization request
if ($Init) {
    $archDir = Split-Path -Path $StateFile -Parent
    if (-not $archDir) { $archDir = "docs/architecture" }
    $modulesDir = Join-Path $archDir "modules"
    $adrDir = Join-Path $archDir "adr"

    if (-not (Test-Path -Path $modulesDir)) {
        New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    }
    if (-not (Test-Path -Path $adrDir)) {
        New-Item -ItemType Directory -Path $adrDir -Force | Out-Null
    }

    $overviewPath = Join-Path $archDir "overview.md"
    if (-not (Test-Path -Path $overviewPath)) {
        $overviewTemplate = @"
# Architecture Overview

## System Purpose & Scope
High-level description of system capabilities, primary user workflows, and boundaries.

## Architecture & Layers
- **Domain / Models**: Core entities and domain logic.
- **Services / Contracts**: Application interfaces and business operations.
- **Presentation / UI**: ViewModels and Views.

## Cross-Cutting Concerns
- Error handling, logging, and localization.
- Performance, concurrency, and security.

## Modules Index
See [modules/](file:///modules/) for detailed specifications.
"@
        [System.IO.File]::WriteAllText((Join-Path (Get-Location) $overviewPath), ($overviewTemplate.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $payload = @{
        last_synced_commit = $headCommit
        last_synced_at     = $timestamp
    } | ConvertTo-Json -Depth 4

    $fullPath = if ([System.IO.Path]::IsPathRooted($StateFile)) { $StateFile } else { Join-Path (Get-Location) $StateFile }
    [System.IO.File]::WriteAllText($fullPath, ($payload.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)

    Write-Host "[OK] Architecture structure initialized in $archDir (Baseline: $headCommit)"
    exit 0
}

# Check if state file exists
if (-not (Test-Path -Path $StateFile)) {
    $initialResult = [PSCustomObject]@{
        has_changes          = $true
        is_initial_baseline  = $true
        last_synced_commit   = $null
        head_commit          = $headCommit
        reason               = "INITIAL_BASELINE_REQUIRED"
        message              = "No sync state found at $StateFile. Baseline documentation should be established."
        affected_files       = @()
    }
    $initialResult | ConvertTo-Json -Depth 5
    exit 0
}

# Read existing state
try {
    $stateContent = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
    $lastCommit = $stateContent.last_synced_commit
} catch {
    $lastCommit = $null
}

if (-not $lastCommit) {
    $invalidResult = [PSCustomObject]@{
        has_changes          = $true
        is_initial_baseline  = $true
        last_synced_commit   = $null
        head_commit          = $headCommit
        reason               = "INVALID_STATE_FILE"
        message              = "State file exists but contains no valid last_synced_commit."
        affected_files       = @()
    }
    $invalidResult | ConvertTo-Json -Depth 5
    exit 0
}

# Verify if last commit exists in history
git cat-file -e $lastCommit 2>$null
if ($LASTEXITCODE -ne 0) {
    $missingResult = [PSCustomObject]@{
        has_changes          = $true
        is_initial_baseline  = $true
        last_synced_commit   = $lastCommit
        head_commit          = $headCommit
        reason               = "COMMIT_NOT_IN_HISTORY"
        message              = "Last synced commit $lastCommit is not reachable. Re-baseline required."
        affected_files       = @()
    }
    $missingResult | ConvertTo-Json -Depth 5
    exit 0
}

# Identical commit: already up to date
if ($lastCommit -eq $headCommit) {
    $upToDateResult = [PSCustomObject]@{
        has_changes        = $false
        last_synced_commit = $lastCommit
        head_commit        = $headCommit
        reason             = "UP_TO_DATE"
        message            = "Documentation is already up to date with HEAD ($headCommit)."
        affected_files     = @()
    }
    $upToDateResult | ConvertTo-Json -Depth 5
    exit 0
}

# Inspect raw changed files
$rawDiff = git diff --name-status "$lastCommit..$headCommit"
if (-not $rawDiff) {
    $noDeltaResult = [PSCustomObject]@{
        has_changes        = $false
        last_synced_commit = $lastCommit
        head_commit        = $headCommit
        reason             = "NO_FILES_CHANGED"
        message            = "No file changes between $lastCommit and $headCommit."
        affected_files     = @()
    }
    $noDeltaResult | ConvertTo-Json -Depth 5
    exit 0
}

# Filter architectural files
$sourceExtensions = @("cs", "rs", "go", "ts", "js", "py", "cpp", "c", "h", "java", "kt", "swift")
$excludePatterns = @("test", "spec", "mock", "\.g\.cs$", "\.Designer\.cs$", "bin/", "obj/", "node_modules/")

$affectedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
$ignoredCount = 0

foreach ($line in ($rawDiff -split "`n")) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

    $parts = $trimmed -split "`t+"
    if ($parts.Count -lt 2) { continue }

    $status = $parts[0]
    $filePath = $parts[1]

    # Check extension
    $ext = [System.IO.Path]::GetExtension($filePath).TrimStart(".").ToLowerInvariant()
    $isSource = $sourceExtensions -contains $ext

    # Check exclusions
    $isExcluded = $false
    foreach ($pattern in $excludePatterns) {
        if ($filePath -match $pattern) {
            $isExcluded = $true
            break
        }
    }

    if ($isSource -and -not $isExcluded) {
        # Determine likely module or subsystem based on path
        $pathParts = $filePath -split "[\\/]"
        $module = if ($pathParts.Count -gt 1) { $pathParts[0] } else { "root" }

        $affectedFiles.Add([PSCustomObject]@{
            status   = $status
            path     = $filePath
            module   = $module
        })
    } else {
        $ignoredCount++
    }
}

if ($affectedFiles.Count -eq 0) {
    $noArchChangesResult = [PSCustomObject]@{
        has_changes          = $false
        last_synced_commit   = $lastCommit
        head_commit          = $headCommit
        reason               = "NO_ARCH_CHANGES"
        message              = "Changes detected, but none affect architectural source files ($ignoredCount non-architectural files ignored)."
        affected_files       = @()
    }
    $noArchChangesResult | ConvertTo-Json -Depth 5
    exit 0
}

# Changes require architectural sync
$syncResult = [PSCustomObject]@{
    has_changes          = $true
    is_initial_baseline  = $false
    last_synced_commit   = $lastCommit
    head_commit          = $headCommit
    reason               = "ARCH_CHANGES_DETECTED"
    message              = "$($affectedFiles.Count) architectural source file(s) modified across $(($affectedFiles | Select-Object -ExpandProperty module -Unique).Count) module(s)."
    affected_files_count = $affectedFiles.Count
    ignored_files_count  = $ignoredCount
    affected_files       = $affectedFiles
}

$syncResult | ConvertTo-Json -Depth 5
exit 0
