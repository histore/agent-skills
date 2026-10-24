<#
.SYNOPSIS
    Inspects, queries, and scaffolds modular living feature specifications with zero token overhead.
.DESCRIPTION
    Implements the Lazy-Loading & Living Modular Documentation protocol:
    - Lists registered features, phases, and lifecycle statuses across docs/features/*.md and docs/ROADMAP.md.
    - Filters features strictly by Phase or ID so AI agents avoid reading/parsing the entire corpus.
    - Scaffolds new isolated feature specs from template and updates the roadmap index with zero LLM tokens.
    - Performs hash-based drift checks (.spec-state.json) to detect modified specifications deterministically.
.PARAMETER RepoRoot
    Root repository path. Defaults to current directory.
.PARAMETER List
    Lists all discovered feature specifications.
.PARAMETER Phase
    Filters feature specifications for a specific phase (e.g. 1, 2, "Foundation").
.PARAMETER Id
    Looks up a specific feature specification by its ID (e.g. FEAT-AUTH-001).
.PARAMETER New
    Scaffolds a new feature specification from template.
.PARAMETER Title
    Title of the feature when creating with -New.
.PARAMETER Scope
    Domain/module scope identifier (e.g. AUTH, CORE, UI, API).
.PARAMETER TargetRelease
    Target release version (e.g. v0.1.0).
.PARAMETER CheckDrift
    Calculates SHA-256 hashes of feature specs to detect changes without parsing.
.PARAMETER UpdateState
    When used with -CheckDrift, persists current hashes to docs/.spec-state.json.
.PARAMETER JsonOutput
    Outputs results formatted as JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -List
.EXAMPLE
    pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -Phase 1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -New -Id "FEAT-AUTH-002" -Title "OAuth2 Login" -Phase 1 -Scope "AUTH"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$List,

    [Parameter(Mandatory = $false)]
    [string]$Phase,

    [Parameter(Mandatory = $false)]
    [string]$Id,

    [Parameter(Mandatory = $false)]
    [switch]$New,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Scope = "CORE",

    [Parameter(Mandatory = $false)]
    [string]$TargetRelease = "v0.1.0",

    [Parameter(Mandatory = $false)]
    [switch]$CheckDrift,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateState,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$featuresDir = Join-Path $RepoRoot "docs\features"
$roadmapFile = Join-Path $RepoRoot "docs\ROADMAP.md"
$stateFile = Join-Path $RepoRoot "docs\.spec-state.json"

# Resolve feature template
$templatePaths = @(
    (Join-Path $RepoRoot "docs\templates\FEATURE_SPEC_TEMPLATE.md"),
    (Join-Path $RepoRoot "_agents\docs\templates\FEATURE_SPEC_TEMPLATE.md"),
    (Join-Path $RepoRoot ".agents\docs\templates\FEATURE_SPEC_TEMPLATE.md")
)
$resolvedTemplate = $templatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

# Helper to parse YAML-like frontmatter or header
function Get-FeatureMetadata {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    $relPath = $FilePath.Replace($RepoRoot + "\", "").Replace($RepoRoot + "/", "").Replace("\", "/")

    $featId = [regex]::Match($content, '(?m)^\s*id:\s*["'']?([A-Za-z0-9_\-]+)["'']?').Groups[1].Value
    if (-not $featId) {
        $featId = [regex]::Match($content, '(?m)^\s*#{1,3}\s+.*?(FEAT-[A-Za-z0-9_\-]+|REQ-[A-Za-z0-9_\-]+)').Groups[1].Value
    }
    if (-not $featId) {
        $featId = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    }

    $featTitle = [regex]::Match($content, '(?m)^\s*title:\s*["'']?(.*?)["'']?\s*$').Groups[1].Value
    if (-not $featTitle) {
        $firstHeading = [regex]::Match($content, '(?m)^\s*#\s+(?:Feature Specification:\s*)?(?:`?[^`\r\n]+`?\s*)?(.*)$').Groups[1].Value
        $featTitle = if ($firstHeading) { $firstHeading.Trim() } else { [System.IO.Path]::GetFileNameWithoutExtension($FilePath) }
    }

    $featPhase = [regex]::Match($content, '(?m)^\s*phase:\s*["'']?(.*?)["'']?\s*$').Groups[1].Value
    if (-not $featPhase) {
        $featPhase = [regex]::Match($content, '(?m)\*\*Phase\*\*:\s*`?([0-9A-Za-z_-]+)`?').Groups[1].Value
        if (-not $featPhase) { $featPhase = "1" }
    }

    $featStatus = [regex]::Match($content, '(?m)^\s*status:\s*["'']?([A-Za-z_]+)["'']?').Groups[1].Value
    if (-not $featStatus) {
        $featStatus = [regex]::Match($content, '(?m)\*\*Status\*\*:\s*`?([A-Z_]+)`?').Groups[1].Value
        if (-not $featStatus) { $featStatus = "PROPOSED" }
    }

    $featScope = [regex]::Match($content, '(?m)^\s*scope:\s*["'']?([A-Za-z0-9_]+)["'']?').Groups[1].Value
    if (-not $featScope) { $featScope = "CORE" }

    $featRelease = [regex]::Match($content, '(?m)^\s*target_release:\s*["'']?(.*?)["'']?\s*$').Groups[1].Value
    if (-not $featRelease) { $featRelease = "v0.1.0" }

    return [PSCustomObject]@{
        Id = $featId.Trim()
        Title = $featTitle.Trim()
        Phase = $featPhase.Trim()
        Status = $featStatus.Trim()
        Scope = $featScope.Trim()
        TargetRelease = $featRelease.Trim()
        FilePath = $relPath
        FullPath = $FilePath
    }
}

# 1. Scaffolding Mode (-New)
if ($New) {
    if (-not $Id) {
        Write-Error "-Id is required when creating a new feature specification."
        exit 1
    }
    if (-not $Title) {
        $Title = "Feature $Id"
    }
    if (-not $Phase) {
        $Phase = "1"
    }

    $slug = ($Title -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
    $fileName = "$Id-$slug.md"
    
    if (-not (Test-Path $featuresDir)) {
        New-Item -ItemType Directory -Path $featuresDir -Force | Out-Null
    }

    $targetFile = Join-Path $featuresDir $fileName
    if (Test-Path $targetFile) {
        Write-Error "Feature specification file already exists: $targetFile"
        exit 1
    }

    $templateContent = if ($resolvedTemplate -and (Test-Path $resolvedTemplate)) {
        Get-Content -Path $resolvedTemplate -Raw -Encoding UTF8
    } else {
        @"
# Feature Specification: <Feature Title>

```yaml
---
id: <FEAT-ID>
title: "<Feature Title>"
phase: <PHASE>
status: PROPOSED
target_release: "<TARGET_RELEASE>"
scope: "<SCOPE>"
depends_on: []
---
```

> **Specification Path**: docs/features/<FILE_NAME>  
> **Parent Hub**: docs/ROADMAP.md

## 1. Executive Summary
Feature specification for <Feature Title>.

## 2. User Story
> **As a** user, **I want** <capability>, **so that** <value>.

## 3. Acceptance Criteria
- [ ] **AC-1**: **Given** condition, **When** action, **Then** result.

## 4. Non-Goals
- Deferred to later phases.
"@
    }

    $newContent = $templateContent.
        Replace("FEAT-<SCOPE>-XXX", $Id).
        Replace("<FEAT-ID>", $Id).
        Replace("<Feature Title>", $Title).
        Replace("<SCOPE>", $Scope).
        Replace("<PHASE>", $Phase).
        Replace("phase: 1", "phase: $Phase").
        Replace("<TARGET_RELEASE>", $TargetRelease).
        Replace("<e.g. v0.1.0>", $TargetRelease).
        Replace("<slug>", $slug).
        Replace("<FILE_NAME>", $fileName)

    # Ensure LF line endings
    $newContentLf = $newContent.Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($targetFile, $newContentLf, [System.Text.UTF8Encoding]::new($false))

    # Append to docs/ROADMAP.md if present
    $roadmapUpdated = $false
    if (Test-Path $roadmapFile) {
        $relPath = "docs/features/$fileName"
        $newRow = "| Phase $Phase | `$Id` | $Title | PROPOSED | `$Scope` | [$relPath]($relPath) | `$TargetRelease` |"
        $rmContent = Get-Content -Path $roadmapFile -Raw -Encoding UTF8
        if ($rmContent -match '\| :--- \| :--- \|') {
            $rmContent = $rmContent.TrimEnd() + "`n" + $newRow + "`n"
            [System.IO.File]::WriteAllText($roadmapFile, $rmContent.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
            $roadmapUpdated = $true
        }
    }

    $result = [PSCustomObject]@{
        status = "created"
        id = $Id
        title = $Title
        phase = $Phase
        file = "docs/features/$fileName"
        roadmap_updated = $roadmapUpdated
    }

    if ($JsonOutput) {
        $result | ConvertTo-Json -Compress
    } else {
        Write-Host "Created feature specification: docs/features/$fileName" -ForegroundColor Green
        if ($roadmapUpdated) {
            Write-Host "Appended feature entry to: docs/ROADMAP.md" -ForegroundColor DarkGray
        }
    }
    exit 0
}

# Collect all feature files
$allSpecs = [System.Collections.Generic.List[PSCustomObject]]::new()
if (Test-Path $featuresDir) {
    Get-ChildItem -Path $featuresDir -Filter "*.md" -File | ForEach-Object {
        $meta = Get-FeatureMetadata -FilePath $_.FullName
        $allSpecs.Add($meta)
    }
}

# Also scan docs/requirements/modules/*.md if present
$modulesDir = Join-Path $RepoRoot "docs\requirements\modules"
if (Test-Path $modulesDir) {
    Get-ChildItem -Path $modulesDir -Filter "*.md" -File | ForEach-Object {
        $meta = Get-FeatureMetadata -FilePath $_.FullName
        $allSpecs.Add($meta)
    }
}

# 2. Check Drift Mode (-CheckDrift)
if ($CheckDrift) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $currentState = @{}

    foreach ($spec in $allSpecs) {
        $bytes = [System.IO.File]::ReadAllBytes($spec.FullPath)
        $hashBytes = $sha.ComputeHash($bytes)
        $hashStr = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
        $currentState[$spec.FilePath] = @{
            id = $spec.Id
            hash = $hashStr
            phase = $spec.Phase
            status = $spec.Status
        }
    }

    $driftDetected = $false
    $changedFiles = @()

    if (Test-Path $stateFile) {
        $savedState = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in $currentState.Keys) {
            $prev = $savedState.$key
            if ($null -eq $prev -or $prev.hash -ne $currentState[$key].hash) {
                $driftDetected = $true
                $changedFiles += $key
            }
        }
    } else {
        $driftDetected = ($allSpecs.Count -gt 0)
        $changedFiles = $currentState.Keys
    }

    if ($UpdateState) {
        $jsonState = $currentState | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($stateFile, $jsonState.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    }

    $driftResult = [PSCustomObject]@{
        status = if ($driftDetected) { "drift_detected" } else { "synchronized" }
        drift_count = $changedFiles.Count
        changed_files = $changedFiles
        total_specs = $allSpecs.Count
    }

    if ($JsonOutput) {
        $driftResult | ConvertTo-Json -Compress
    } else {
        Write-Host "Feature Spec State: $($driftResult.status) ($($driftResult.drift_count) modified, $($driftResult.total_specs) total)" -ForegroundColor $(if ($driftDetected) { "Yellow" } else { "Green" })
    }
    exit 0
}

# 3. Filter by ID (-Id)
if ($Id) {
    $found = $allSpecs | Where-Object { $_.Id -eq $Id.Trim() } | Select-Object -First 1
    if (-not $found) {
        $found = $allSpecs | Where-Object { $_.FilePath -like "*$Id*" } | Select-Object -First 1
    }

    if ($found) {
        if ($JsonOutput) {
            $found | ConvertTo-Json -Compress
        } else {
            Write-Host "Feature: $($found.Id) - $($found.Title)" -ForegroundColor Cyan
            Write-Host "  Phase:   $($found.Phase)"
            Write-Host "  Status:  $($found.Status)"
            Write-Host "  Scope:   $($found.Scope)"
            Write-Host "  Path:    $($found.FilePath)"
        }
        exit 0
    } else {
        if ($JsonOutput) {
            [PSCustomObject]@{ status = "not_found"; id = $Id } | ConvertTo-Json -Compress
        } else {
            Write-Host "Feature '$Id' not found." -ForegroundColor Red
        }
        exit 1
    }
}

# 4. Filter by Phase (-Phase)
if ($Phase) {
    $filtered = @($allSpecs | Where-Object { $_.Phase -eq $Phase.Trim() -or $_.Phase -like "*$Phase*" })
    if ($JsonOutput) {
        if ($filtered.Count -eq 0) { "[]" } else { $filtered | ConvertTo-Json -Compress }
    } else {
        Write-Host "=== Features for Phase $Phase ($($filtered.Count) found) ===" -ForegroundColor Cyan
        foreach ($f in $filtered) {
            Write-Host "  [$($f.Id)] $($f.Title) | Status: $($f.Status) | Path: $($f.FilePath)"
        }
    }
    exit 0
}

# 5. Default List View (-List or no args)
if ($JsonOutput) {
    if ($allSpecs.Count -eq 0) { "[]" } else { $allSpecs | ConvertTo-Json -Compress }
} else {
    Write-Host "=== Discovered Feature Specifications ($($allSpecs.Count) total) ===" -ForegroundColor Cyan
    if ($allSpecs.Count -eq 0) {
        Write-Host "  No feature specifications found in docs/features/ or docs/requirements/modules/." -ForegroundColor DarkGray
    } else {
        foreach ($f in $allSpecs) {
            Write-Host "  [$($f.Id)] Phase $($f.Phase) | $($f.Title) | Status: $($f.Status) | Path: $($f.FilePath)"
        }
    }
}
exit 0
