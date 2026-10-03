<#
.SYNOPSIS
    Lints Clean Architecture layer boundaries and Clean Code metrics deterministically.
.DESCRIPTION
    Validates that source files adhere to declarative architectural boundary rules
    (e.g. Domain layer must not import Infrastructure, Database, or UI) and Clean Code metrics
    (file size limits, nesting depth) with zero LLM tokens.
.PARAMETER RulesPath
    Optional custom path to clean-architecture.json rules file.
.PARAMETER TargetPath
    Path to scan. Defaults to current directory.
.PARAMETER StagedOnly
    Switch to scan only git staged files.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-clean-architecture.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-clean-architecture.ps1 -StagedOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RulesPath,

    [Parameter(Mandatory = $false)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false)]
    [switch]$StagedOnly,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if (-not $TargetPath) {
    $TargetPath = (Get-Location).Path
}

# 1. Resolve rules file
if (-not $RulesPath) {
    $candidateRules = @(
        (Join-Path $repoRoot ".agent-lint.json"),
        (Join-Path $repoRoot "rules\clean-architecture.json"),
        (Join-Path $repoRoot "_agents\rules\clean-architecture.json"),
        (Join-Path $repoRoot ".agents\rules\clean-architecture.json")
    )
    foreach ($cand in $candidateRules) {
        if (Test-Path $cand) {
            $RulesPath = $cand
            break
        }
    }
}

$rules = $null
if ($RulesPath -and (Test-Path $RulesPath)) {
    try {
        $rules = Get-Content -Path $RulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
}

$maxFileLines = if ($rules -and $rules.metrics.max_file_lines) { [int]$rules.metrics.max_file_lines } else { 500 }
$maxNesting = if ($rules -and $rules.metrics.max_nesting_depth) { [int]$rules.metrics.max_nesting_depth } else { 4 }
$layerBoundaries = if ($rules -and $rules.layer_boundaries) { $rules.layer_boundaries } else { @() }

# 2. Collect files
$filesToScan = [System.Collections.Generic.List[string]]::new()
$srcExts = @(".rs", ".cs", ".ts", ".js", ".py", ".go")

if ($StagedOnly) {
    $staged = git -C $TargetPath diff --name-only --cached 2>$null
    foreach ($f in ($staged -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($f)) {
            $full = Join-Path $TargetPath $f
            if ((Test-Path $full) -and ($srcExts -contains [System.IO.Path]::GetExtension($full).ToLowerInvariant())) {
                $filesToScan.Add($full)
            }
        }
    }
} else {
    $allFiles = Get-ChildItem -Path $TargetPath -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
        $_.FullName -notmatch '[\\/]target[\\/]' -and
        $_.FullName -notmatch '[\\/]bin[\\/]' -and
        $_.FullName -notmatch '[\\/]obj[\\/]' -and
        ($srcExts -contains $_.Extension.ToLowerInvariant())
    }
    foreach ($f in $allFiles) {
        $filesToScan.Add($f.FullName)
    }
}

$violations = [System.Collections.Generic.List[PSCustomObject]]::new()

# Import regex patterns across languages (use, import, using, from)
$importRegex = '^\s*(use\s+|import\s+|using\s+|from\s+)([^;]+)'

foreach ($filePath in $filesToScan) {
    $relPath = $filePath.Replace($TargetPath + "\", "").Replace($TargetPath + "/", "")
    $lines = Get-Content -Path $filePath -Encoding UTF8

    # Metric 1: Max file lines
    if ($lines.Length -gt $maxFileLines) {
        $violations.Add([PSCustomObject]@{
            Type = "FileSizeLimit"
            File = $relPath
            Line = $lines.Length
            Severity = "Warning"
            Message = "File exceeds $maxFileLines lines ($($lines.Length) lines); consider modular decomposition"
        })
    }

    # Match active layer rules
    $activeLayerRules = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($lb in $layerBoundaries) {
        if ($relPath -match $lb.path_pattern) {
            $activeLayerRules.Add($lb)
        }
    }

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]

        # Metric 2: Max nesting depth
        if ($line -match '^\s*(if|for|while|match|switch)\b') {
            $leadingSpaces = ($line -replace '^(\s*).*', '$1').Length
            $depth = [math]::Floor($leadingSpaces / 4)
            if ($depth -gt $maxNesting) {
                $violations.Add([PSCustomObject]@{
                    Type = "DeepNesting"
                    File = $relPath
                    Line = $i + 1
                    Severity = "Warning"
                    Message = "Control block nesting depth of $depth exceeds recommended limit of $maxNesting"
                })
            }
        }

        # Check Layer Boundaries
        if ($activeLayerRules.Count -gt 0 -and $line -match $importRegex) {
            $importTarget = $matches[2].ToLowerInvariant()
            foreach ($rule in $activeLayerRules) {
                foreach ($forbidden in $rule.forbidden_imports) {
                    if ($importTarget -match "\b$forbidden\b" -or $importTarget -match $forbidden) {
                        $violations.Add([PSCustomObject]@{
                            Type = "LayerBoundaryViolation"
                            File = $relPath
                            Line = $i + 1
                            Severity = "Error"
                            Message = "Layer '$($rule.layer)' illegally imports '$forbidden': $($rule.message)"
                        })
                    }
                }
            }
        }
    }
}

$hasErrors = ($violations | Where-Object { $_.Severity -eq "Error" }).Count -gt 0
$isPass = (-not $hasErrors)

$result = [ordered]@{
    status = if ($isPass) { "pass" } else { "fail" }
    scanned_source_files = $filesToScan.Count
    violations_count = $violations.Count
    error_count = ($violations | Where-Object { $_.Severity -eq "Error" }).Count
    warning_count = ($violations | Where-Object { $_.Severity -eq "Warning" }).Count
    violations = $violations.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Deterministic Clean Architecture & Code Linter" -ForegroundColor Cyan
    Write-Host "Scanned Source Files: $($filesToScan.Count) | Violations: $($violations.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($isPass) {
        Write-Host "Clean Architecture Status: PASS (0 architectural boundary errors)" -ForegroundColor Green
    } else {
        Write-Host "Clean Architecture Status: FAIL ($($result.error_count) errors, $($result.warning_count) warnings)" -ForegroundColor Red
        foreach ($v in $violations) {
            $color = if ($v.Severity -eq "Error") { "Red" } else { "Yellow" }
            Write-Host "  [$($v.Severity): $($v.Type)] $($v.File):$($v.Line) - $($v.Message)" -ForegroundColor $color
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if ($hasErrors) {
    exit 1
}
