#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes git deltas since the last architectural sync checkpoint and detects relevant code changes.

.DESCRIPTION
    Inspects git changes between the checkpoint commit recorded in .arch-sync.json and HEAD.
    Filters out non-architectural files (tests, assets, markdown, generated code).
    Outputs a structured JSON payload for consumption by the ask-architecture-sync subagent.
    Consumes 0 LLM tokens during inspection and filtering.
    Supports internal (project-local) and external (out-of-tree) documentation storage with
    project-level configuration (via .git/config) and full CLI / environment override capability.

.PARAMETER DocDir
    Explicit path to the architecture documentation directory. Overrides git config and env vars.

.PARAMETER Mode
    Storage mode: 'internal' or 'external'.

.PARAMETER StateFile
    Explicit path to the JSON state file storing the last analyzed commit hash.

.PARAMETER UpdateCheckpoint
    Switch to record current HEAD into the state file as the new baseline checkpoint.

.PARAMETER Init
    Switch to scaffold the directory structure, templates, and baseline checkpoint.

.PARAMETER SetDocDir
    Sets the project-level local git config 'arch-sync.doc-dir' (stored in .git/config with 0 project footprint) and exits.

.PARAMETER SetMode
    Sets the project-level local git config 'arch-sync.mode' ('internal' or 'external') and exits.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -SetDocDir "C:/docs/my-project"
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -DocDir "D:/custom/path"
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -Init
    powershell -ExecutionPolicy Bypass -File ./get-arch-diff.ps1 -UpdateCheckpoint
#>

[CmdletBinding()]
param(
    [string]$DocDir = $null,
    [ValidateSet("internal", "external")][string]$Mode = $null,
    [string]$StateFile = $null,
    [switch]$UpdateCheckpoint,
    [switch]$Init,
    [string]$SetDocDir = $null,
    [ValidateSet("internal", "external")][string]$SetMode = $null
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

# Handle local git config helper commands
if ($SetDocDir) {
    git config --local arch-sync.doc-dir "$SetDocDir"
    Write-Host "[OK] Project-level arch-sync.doc-dir set to: $SetDocDir (stored in .git/config, 0 project footprint)"
    exit 0
}

if ($SetMode) {
    git config --local arch-sync.mode "$SetMode"
    Write-Host "[OK] Project-level arch-sync.mode set to: $SetMode (stored in .git/config, 0 project footprint)"
    exit 0
}

function Resolve-ArchDocConfig {
    param(
        [string]$CliDocDir,
        [string]$CliMode,
        [string]$CliStateFile
    )

    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) {
        throw "Not inside a valid git repository or git is unavailable."
    }
    $repoRoot = $repoRoot.Trim().Replace('\', '/')
    $repoName = Split-Path -Leaf $repoRoot

    $resolvedDocDir = $null
    $resolvedMode = "internal"
    $resolvedFrom = "default"

    # 1. CLI Override (-DocDir or -StateFile)
    if ($CliDocDir) {
        $resolvedDocDir = $CliDocDir
        $resolvedFrom = "cli_override"
        $resolvedMode = if ($CliMode) { $CliMode } else { "external" }
    } elseif ($CliStateFile) {
        $resolvedDocDir = Split-Path -Parent $CliStateFile
        if (-not $resolvedDocDir) { $resolvedDocDir = "." }
        $resolvedFrom = "cli_state_file"
        $resolvedMode = if ($CliMode) { $CliMode } else { "external" }
    }
    # 2. Environment Variable ($env:ARCH_SYNC_DOC_DIR)
    elseif ($env:ARCH_SYNC_DOC_DIR) {
        $resolvedDocDir = $env:ARCH_SYNC_DOC_DIR
        $resolvedFrom = "env_var"
        $resolvedMode = if ($env:ARCH_SYNC_MODE) { $env:ARCH_SYNC_MODE } else { "external" }
    }
    # 3. Project-Level Git Config (git config --local --get arch-sync.doc-dir)
    else {
        $gitLocalDocDir = git config --local --get arch-sync.doc-dir 2>$null
        $gitLocalMode = git config --local --get arch-sync.mode 2>$null

        if ($gitLocalDocDir) {
            $resolvedDocDir = $gitLocalDocDir.Trim()
            $resolvedFrom = "git_local_config"
            $resolvedMode = if ($gitLocalMode) { $gitLocalMode.Trim() } else { "external" }
        }
        # 4. User Global Git Config (git config --global --get arch-sync.external-base-dir)
        else {
            $gitGlobalBaseDir = git config --global --get arch-sync.external-base-dir 2>$null
            if ($gitGlobalBaseDir) {
                $resolvedDocDir = Join-Path $gitGlobalBaseDir.Trim() $repoName
                $resolvedFrom = "git_global_config"
                $resolvedMode = "external"
            }
            # 5. Default Fallback: internal in repo
            else {
                $resolvedDocDir = Join-Path $repoRoot "docs/architecture"
                $resolvedFrom = "default"
                $resolvedMode = "internal"
            }
        }
    }

    # Normalize path
    if (-not [System.IO.Path]::IsPathRooted($resolvedDocDir)) {
        $resolvedDocDir = Join-Path $repoRoot $resolvedDocDir
    }
    $resolvedDocDir = [System.IO.Path]::GetFullPath($resolvedDocDir).Replace('\', '/')

    # Determine storage mode based on repo root location
    if ($resolvedDocDir.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $CliMode -and $resolvedFrom -eq "default") {
            $resolvedMode = "internal"
        }
    } else {
        $resolvedMode = "external"
    }

    if ($CliMode) {
        $resolvedMode = $CliMode
    }

    $stateFilePath = if ($CliStateFile) { 
        [System.IO.Path]::GetFullPath((if ([System.IO.Path]::IsPathRooted($CliStateFile)) { $CliStateFile } else { Join-Path $repoRoot $CliStateFile })).Replace('\', '/')
    } else { 
        Join-Path $resolvedDocDir ".arch-sync.json" 
    }

    return [PSCustomObject]@{
        DocDir        = $resolvedDocDir
        StateFile     = $stateFilePath
        StorageMode   = $resolvedMode
        ResolvedFrom  = $resolvedFrom
        RepoRoot      = $repoRoot
    }
}

$cfg = Resolve-ArchDocConfig -CliDocDir $DocDir -CliMode $Mode -CliStateFile $StateFile
$headCommit = Get-GitHeadCommit

# Handle checkpoint update request
if ($UpdateCheckpoint) {
    $stateDir = Split-Path -Path $cfg.StateFile -Parent
    if ($stateDir -and -not (Test-Path -Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $payload = @{
        last_synced_commit = $headCommit
        last_synced_at     = $timestamp
        storage_mode       = $cfg.StorageMode
        doc_dir            = $cfg.DocDir
    } | ConvertTo-Json -Depth 4

    # Ensure LF line endings
    [System.IO.File]::WriteAllText($cfg.StateFile, ($payload.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Architecture sync checkpoint updated to $headCommit ($timestamp) at $($cfg.StateFile)"
    exit 0
}

# Handle initialization request
if ($Init) {
    $modulesDir = Join-Path $cfg.DocDir "modules"
    $adrDir = Join-Path $cfg.DocDir "adr"

    if (-not (Test-Path -Path $modulesDir)) {
        New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    }
    if (-not (Test-Path -Path $adrDir)) {
        New-Item -ItemType Directory -Path $adrDir -Force | Out-Null
    }

    $overviewPath = Join-Path $cfg.DocDir "overview.md"
    if (-not (Test-Path -Path $overviewPath)) {
        $overviewTemplate = @"
# Architecture Overview

## System Purpose & Scope
High-level description of system capabilities, primary user workflows, and boundaries.

## Architecture & Layers
- **Domain / Models**: Core entities, value objects, and domain logic.
- **Services / Contracts**: Application interfaces and business operations.
- **Presentation / UI**: ViewModels and Views.

## Cross-Cutting Concerns
- Error handling, logging, and localization.
- Performance, concurrency, and security.

## Modules Index
Detailed component specifications are maintained incrementally under [modules/](file:///modules/):
- *List modules here*
"@
        [System.IO.File]::WriteAllText($overviewPath, ($overviewTemplate.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)
    }

    # Only create ARCHITECTURE.md in repo root if storage mode is internal (preserve 0 project footprint when external)
    if ($cfg.StorageMode -eq "internal") {
        $rootArchPath = Join-Path $cfg.RepoRoot "ARCHITECTURE.md"
        if (-not (Test-Path -Path $rootArchPath)) {
            $rootArchTemplate = @"
# Architecture Documentation

This project's architecture is maintained under [docs/architecture/](file:///docs/architecture/):
- **Overview**: [overview.md](file:///docs/architecture/overview.md)
- **Module Specs**: [modules/](file:///docs/architecture/modules/)
"@
            [System.IO.File]::WriteAllText($rootArchPath, ($rootArchTemplate.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)
        }
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $payload = @{
        last_synced_commit = $headCommit
        last_synced_at     = $timestamp
        storage_mode       = $cfg.StorageMode
        doc_dir            = $cfg.DocDir
    } | ConvertTo-Json -Depth 4

    [System.IO.File]::WriteAllText($cfg.StateFile, ($payload.Replace("`r`n", "`n") + "`n"), [System.Text.Encoding]::UTF8)

    Write-Host "[OK] Architecture structure initialized at $($cfg.DocDir) [Mode: $($cfg.StorageMode), Source: $($cfg.ResolvedFrom)] (Baseline: $headCommit)"
    exit 0
}

# Check if state file exists
if (-not (Test-Path -Path $cfg.StateFile)) {
    $initialResult = [PSCustomObject]@{
        has_changes          = $true
        is_initial_baseline  = $true
        last_synced_commit   = $null
        head_commit          = $headCommit
        doc_dir              = $cfg.DocDir
        storage_mode         = $cfg.StorageMode
        resolved_from        = $cfg.ResolvedFrom
        reason               = "INITIAL_BASELINE_REQUIRED"
        message              = "No sync state found at $($cfg.StateFile). Baseline documentation should be established."
        affected_files       = @()
    }
    $initialResult | ConvertTo-Json -Depth 5
    exit 0
}

# Read existing state
try {
    $stateContent = Get-Content -Raw -Path $cfg.StateFile | ConvertFrom-Json
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
        doc_dir              = $cfg.DocDir
        storage_mode         = $cfg.StorageMode
        resolved_from        = $cfg.ResolvedFrom
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
        doc_dir              = $cfg.DocDir
        storage_mode         = $cfg.StorageMode
        resolved_from        = $cfg.ResolvedFrom
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
        doc_dir            = $cfg.DocDir
        storage_mode       = $cfg.StorageMode
        resolved_from      = $cfg.ResolvedFrom
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
        doc_dir            = $cfg.DocDir
        storage_mode       = $cfg.StorageMode
        resolved_from      = $cfg.ResolvedFrom
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
        doc_dir              = $cfg.DocDir
        storage_mode         = $cfg.StorageMode
        resolved_from        = $cfg.ResolvedFrom
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
    doc_dir              = $cfg.DocDir
    storage_mode         = $cfg.StorageMode
    resolved_from        = $cfg.ResolvedFrom
    reason               = "ARCH_CHANGES_DETECTED"
    message              = "$($affectedFiles.Count) architectural source file(s) modified across $(($affectedFiles | Select-Object -ExpandProperty module -Unique).Count) module(s)."
    affected_files_count = $affectedFiles.Count
    ignored_files_count  = $ignoredCount
    affected_files       = $affectedFiles
}

$syncResult | ConvertTo-Json -Depth 5
exit 0
