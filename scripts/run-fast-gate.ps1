<#
.SYNOPSIS
    Executes a Stage-1 deterministic Fast-Gate (build, test, lint) with log compaction.
.DESCRIPTION
    Runs native compilation, targeted/quiet tests, and linter based on auto-detected tech stack.
    On success, outputs a minimal single-line confirmation (zero token noise).
    On failure, compacts raw terminal output to only the relevant error messages.
.PARAMETER ProjectRoot
    Optional root directory of the project. Defaults to current directory.
.PARAMETER TestFilter
    Optional filter targeting only the affected test class or function.
.PARAMETER SkipLint
    Switch to bypass the linter check.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-fast-gate.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-fast-gate.ps1 -TestFilter "UserMapperTests"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $false)]
    [string]$TestFilter,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLint,

    [Parameter(Mandatory = $false)]
    [switch]$SkipGuardrails,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failedStep = $null
$failureLogs = [System.Collections.Generic.List[string]]::new()

# 1. Detect tech stack in-process (zero subprocess spawn overhead)
$detectScript = Join-Path $scriptDir "detect-tech-stack.ps1"
$stackInfo = [ordered]@{
    stack = "unknown"
    build_cmd = ""
    test_cmd = ""
    lint_cmd = ""
}

if (Test-Path $detectScript) {
    try {
        $rawStack = & $detectScript -ProjectRoot $ProjectRoot -JsonOutput | ConvertFrom-Json
        $stackInfo = $rawStack
    } catch {}
}

# Helper to execute command and collect errors with context lines
function Invoke-GateStep {
    param([string]$StepName, [string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $true }
    
    $stdoutFile = Join-Path ([System.IO.Path]::GetTempPath()) "gate_stdout_${PID}_$([guid]::NewGuid().ToString('N')).log"
    $stderrFile = Join-Path ([System.IO.Path]::GetTempPath()) "gate_stderr_${PID}_$([guid]::NewGuid().ToString('N')).log"
    try {
        $proc = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", "Set-Location '$ProjectRoot'; $CommandLine" -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue

        if ($exitCode -ne 0) {
            $combined = ($stderr + "`n" + $stdout) -split "`r?`n"
            # Compact errors with up to 2 trailing context lines for assertion/location clarity
            $matchedIndices = [System.Collections.Generic.HashSet[int]]::new()
            for ($i = 0; $i -lt $combined.Length; $i++) {
                if ($combined[$i] -match '(?i)error|failed|exception|assert|fatal|panicked') {
                    for ($ctx = [Math]::Max(0, $i - 1); $ctx -le [Math]::Min($combined.Length - 1, $i + 2); $ctx++) {
                        if (-not [string]::IsNullOrWhiteSpace($combined[$ctx])) {
                            [void]$matchedIndices.Add($ctx)
                        }
                    }
                    if ($matchedIndices.Count -ge 25) { break }
                }
            }
            if ($matchedIndices.Count -gt 0) {
                foreach ($idx in ($matchedIndices | Sort-Object)) {
                    $script:failureLogs.Add($combined[$idx].Trim())
                }
            } else {
                $tailLines = $combined | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 12
                foreach ($tl in $tailLines) { $script:failureLogs.Add($tl.Trim()) }
            }
            $script:failedStep = $StepName
            return $false
        }
        return $true
    } catch {
        $script:failureLogs.Add("Execution exception in $StepName : $_")
        $script:failedStep = $StepName
        return $false
    }
}

# 2. Run Build, Test, Lint if executable stack is present
$buildSuccess = $true
$testSuccess = $true
$lintSuccess = $true

if ($stackInfo.stack -ne "unknown") {
    if ($stackInfo.build_cmd) {
        $buildSuccess = Invoke-GateStep -StepName "Build" -CommandLine $stackInfo.build_cmd
    }
    if ($buildSuccess -and $stackInfo.test_cmd) {
        $testCmd = $stackInfo.test_cmd
        if ($TestFilter -and $stackInfo.test_filter_syntax) {
            $testCmd = $stackInfo.test_filter_syntax.Replace("{filter}", $TestFilter)
        }
        $testSuccess = Invoke-GateStep -StepName "Test" -CommandLine $testCmd
    }
    if ($buildSuccess -and $testSuccess -and -not $SkipLint -and $stackInfo.lint_cmd) {
        $lintSuccess = Invoke-GateStep -StepName "Lint" -CommandLine $stackInfo.lint_cmd
    }
}

# 3. Consolidated Guardrails & Clean Architecture Check (in-process, zero extra tool roundtrips)
$guardrailsSuccess = $true
if ($buildSuccess -and $testSuccess -and $lintSuccess -and -not $SkipGuardrails) {
    $archScript = Join-Path $scriptDir "lint-clean-architecture.ps1"
    if (Test-Path $archScript) {
        try {
            $archRes = & $archScript -TargetPath $ProjectRoot -StagedOnly -JsonOutput | ConvertFrom-Json
            if ($archRes.status -eq "fail") {
                $guardrailsSuccess = $false
                $failedStep = "CleanArchitecture"
                foreach ($v in $archRes.violations | Where-Object { $_.Severity -eq "Error" }) {
                    $failureLogs.Add("[$($v.Type)] $($v.File):$($v.Line) - $($v.Message)")
                }
            }
        } catch {}
    }

    $scanScript = Join-Path $scriptDir "scan-guardrails.ps1"
    if ($guardrailsSuccess -and (Test-Path $scanScript)) {
        try {
            $scanRes = & $scanScript -ScanPath $ProjectRoot -StagedOnly -JsonOutput | ConvertFrom-Json
            if ($scanRes.status -eq "fail") {
                $guardrailsSuccess = $false
                $failedStep = "Guardrails"
                foreach ($v in $scanRes.violations) {
                    $failureLogs.Add("[$($v.Rule)] $($v.File):$($v.Line) - $($v.Message)")
                }
            }
        } catch {}
    }
}

$sw.Stop()
$overallPass = ($buildSuccess -and $testSuccess -and $lintSuccess -and $guardrailsSuccess)

$result = [ordered]@{
    status = if ($overallPass) { "pass" } else { "fail" }
    failed_step = $failedStep
    duration_ms = $sw.ElapsedMilliseconds
    errors = if (-not $overallPass) { $failureLogs.ToArray() } else { @() }
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 4 -Compress
} else {
    if ($overallPass) {
        Write-Host "Stage-1 Fast-Gate: PASS ($($sw.ElapsedMilliseconds)ms) - Zero errors" -ForegroundColor Green
    } else {
        Write-Host "Stage-1 Fast-Gate: FAIL at step '$failedStep' ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Red
        foreach ($err in $failureLogs) {
            Write-Host "  - $err" -ForegroundColor Yellow
        }
    }
}

if (-not $overallPass) {
    exit 1
}
