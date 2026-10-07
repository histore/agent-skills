#Requires -Version 5.1
<#
.SYNOPSIS
    Unified Quality Gates runner executing all zero-token linters and stage-1 validation.
.DESCRIPTION
    Deterministically runs the complete suite of quality checks in a single call:
    1. Guardrails (CRLF line endings, secrets, safe-Rust, submodule leakage)
    2. Clean Architecture layer boundaries
    3. Documentation link integrity
    4. Requirements scoped IDs & zero collisions
    5. Stage-1 Fast-Gate (native build & quiet test runner)
.PARAMETER RepoRoot
    Path to project repository root. Defaults to current repository.
.PARAMETER StagedOnly
    Runs staged-only checks where applicable (guardrails, architecture).
.PARAMETER Fast
    Skips stage-1 build and test runner, executing only static zero-token linters.
.PARAMETER Fix
    Enables auto-remediation where available (e.g. normalizing CRLF line endings in scan-guardrails).
.PARAMETER JsonOutput
    Outputs consolidated results as JSON.
.EXAMPLE
    pwsh -NoProfile -File ./_agents/scripts/run-all-gates.ps1
    pwsh -NoProfile -File ./_agents/scripts/run-all-gates.ps1 -StagedOnly
    pwsh -NoProfile -File ./_agents/scripts/run-all-gates.ps1 -Fix
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$StagedOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Fast,

    [Parameter(Mandatory = $false)]
    [switch]$Fix,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'Stop'

function Get-HostRepoRoot {
    $superproject = git rev-parse --show-superproject-working-tree 2>$null
    if ($superproject) { return $superproject.Trim() }
    $toplevel = git rev-parse --show-toplevel 2>$null
    if ($toplevel) {
        $root = $toplevel.Trim()
        if ($root -match '[\\/](_agents|\.agents)$') {
            $root = Split-Path -Parent $root
        }
        return $root
    }
    return (Get-Location).Path
}

if (-not $RepoRoot) {
    $RepoRoot = Get-HostRepoRoot
}

$scriptDir = $PSScriptRoot
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

function Run-Gate {
    param(
        [string]$Name,
        [string]$ScriptFile,
        [string[]]$ScriptArgs,
        [bool]$Required = $true
    )

    $fullScript = Join-Path $scriptDir $ScriptFile
    if (-not (Test-Path $fullScript)) {
        return [PSCustomObject]@{
            Gate = $Name
            Status = "skipped"
            DurationMs = 0
            Message = "Script '$ScriptFile' not found"
        }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $cmdArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $fullScript) + $ScriptArgs
    
    $prevLocation = Get-Location
    $outputLines = @()
    $exitCode = 0
    try {
        Set-Location $RepoRoot
        $rawOutput = & pwsh @cmdArgs 2>&1
        $exitCode = $LASTEXITCODE
        if ($rawOutput) {
            $outputLines = @($rawOutput | ForEach-Object { "$_" })
        }
    } finally {
        Set-Location $prevLocation
    }
    $sw.Stop()

    $passed = ($exitCode -eq 0)
    $statusStr = if ($passed) { "pass" } else { "fail" }

    return [PSCustomObject]@{
        Gate = $Name
        Status = $statusStr
        DurationMs = $sw.ElapsedMilliseconds
        Message = if ($passed) { "Passed cleanly" } else { "Reported errors (exit code $exitCode)" }
        Output = ($outputLines -join "`n").Trim()
    }
}

# 1. Guardrails Scanner
$guardrailArgs = @()
if ($StagedOnly) { $guardrailArgs += "-StagedOnly" }
if ($Fix) { $guardrailArgs += "-Fix" }
$guardrailArgs += "-ScanPath"; $guardrailArgs += $RepoRoot
$results.Add((Run-Gate -Name "Guardrails (Secrets/CRLF/SafeRust)" -ScriptFile "scan-guardrails.ps1" -ScriptArgs $guardrailArgs))

# 2. Clean Architecture Linter
$archArgs = @("-TargetPath", $RepoRoot)
if ($StagedOnly) { $archArgs += "-StagedOnly" }
$results.Add((Run-Gate -Name "Clean Architecture Boundaries" -ScriptFile "lint-clean-architecture.ps1" -ScriptArgs $archArgs))

# 3. Documentation & Links
$results.Add((Run-Gate -Name "Documentation & Link Integrity" -ScriptFile "lint-docs.ps1" -ScriptArgs @("-RepoRoot", $RepoRoot)))

# 4. Requirements Consistency & Scoped IDs
$results.Add((Run-Gate -Name "Requirements Scoped IDs & Non-Duplication" -ScriptFile "lint-requirements.ps1" -ScriptArgs @("-RequirementsPath", $RepoRoot)))

# 5. Stage-1 Fast-Gate (Build & Quiet Tests)
if (-not $Fast) {
    $results.Add((Run-Gate -Name "Stage-1 Fast-Gate (Build & Tests)" -ScriptFile "run-fast-gate.ps1" -ScriptArgs @("-ProjectRoot", $RepoRoot)))
}

$swTotal.Stop()
$failedCount = ($results | Where-Object { $_.Status -eq "fail" }).Count
$passedCount = ($results | Where-Object { $_.Status -eq "pass" }).Count
$overallPass = ($failedCount -eq 0)

if ($JsonOutput) {
    [ordered]@{
        status = if ($overallPass) { "pass" } else { "fail" }
        total_duration_ms = $swTotal.ElapsedMilliseconds
        passed_gates = $passedCount
        failed_gates = $failedCount
        gates = $results.ToArray()
    } | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Unified Quality Gates Runner" -ForegroundColor Cyan
    Write-Host "Target: $RepoRoot | Duration: $($swTotal.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    foreach ($r in $results) {
        $color = if ($r.Status -eq "pass") { "Green" } elseif ($r.Status -eq "skipped") { "DarkGray" } else { "Red" }
        $mark = if ($r.Status -eq "pass") { "[PASS]" } elseif ($r.Status -eq "skipped") { "[SKIP]" } else { "[FAIL]" }
        Write-Host "  $mark $($r.Gate.PadRight(40)) : $($r.Status.ToUpper()) ($($r.DurationMs)ms)" -ForegroundColor $color
    }
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($overallPass) {
        Write-Host "Unified Gates Status: PASS ($passedCount/$($results.Count) gates passed)" -ForegroundColor Green
    } else {
        Write-Host "Unified Gates Status: FAIL ($failedCount/$($results.Count) gates failed)" -ForegroundColor Red
        foreach ($r in ($results | Where-Object { $_.Status -eq "fail" })) {
            if ($r.Output) {
                Write-Host "`n--- Output for failed gate: $($r.Gate) ---" -ForegroundColor Yellow
                Write-Host $r.Output -ForegroundColor DarkGray
            }
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if (-not $overallPass) {
    exit 1
}
