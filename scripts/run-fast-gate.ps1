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
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

# 1. Detect tech stack
$detectScript = Join-Path $scriptDir "detect-tech-stack.ps1"
$stackInfo = [ordered]@{
    stack = "unknown"
    build_cmd = ""
    test_cmd = ""
    lint_cmd = ""
}

if (Test-Path $detectScript) {
    try {
        $rawStack = pwsh -NoProfile -ExecutionPolicy Bypass -File $detectScript -ProjectRoot $ProjectRoot -JsonOutput | ConvertFrom-Json
        $stackInfo = $rawStack
    } catch {}
}

# If unknown stack and no test suite found, consider it pass (Profile A non-executable)
if ($stackInfo.stack -eq "unknown") {
    $result = [ordered]@{
        status = "pass"
        message = "No executable stack or testrunner detected; bypassing fast-gate"
        duration_ms = 0
    }
    if ($JsonOutput) { $result | ConvertTo-Json -Compress } else { Write-Host "Stage-1 Fast-Gate: Bypassed (no executable stack)" -ForegroundColor Gray }
    exit 0
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failedStep = $null
$failureLogs = [System.Collections.Generic.List[string]]::new()

# Helper to execute command and collect errors
function Invoke-GateStep {
    param([string]$StepName, [string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $true }
    
    $output = [System.Collections.Generic.List[string]]::new()
    try {
        $proc = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", "Set-Location '$ProjectRoot'; $CommandLine" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\gate_stdout.log" -RedirectStandardError "$env:TEMP\gate_stderr.log"
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        $stdout = if (Test-Path "$env:TEMP\gate_stdout.log") { Get-Content "$env:TEMP\gate_stdout.log" -Raw } else { "" }
        $stderr = if (Test-Path "$env:TEMP\gate_stderr.log") { Get-Content "$env:TEMP\gate_stderr.log" -Raw } else { "" }
        Remove-Item "$env:TEMP\gate_stdout.log", "$env:TEMP\gate_stderr.log" -Force -ErrorAction SilentlyContinue

        if ($exitCode -ne 0) {
            $combined = ($stderr + "`n" + $stdout) -split "`r?`n"
            # Compact errors: filter lines matching error indicators
            $errorLines = $combined | Where-Object { $_ -match '(?i)error|failed|exception|assert|fatal' } | Select-Object -First 15
            if ($errorLines.Count -eq 0) { $errorLines = $combined | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 10 }
            foreach ($el in $errorLines) { $script:failureLogs.Add($el.Trim()) }
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

# 2. Run Build
$buildSuccess = $true
if ($stackInfo.build_cmd) {
    $buildSuccess = Invoke-GateStep -StepName "Build" -CommandLine $stackInfo.build_cmd
}

# 3. Run Test
$testSuccess = $true
if ($buildSuccess -and $stackInfo.test_cmd) {
    $testCmd = $stackInfo.test_cmd
    if ($TestFilter -and $stackInfo.test_filter_syntax) {
        $testCmd = $stackInfo.test_filter_syntax.Replace("{filter}", $TestFilter)
    }
    $testSuccess = Invoke-GateStep -StepName "Test" -CommandLine $testCmd
}

# 4. Run Lint (if not skipped and build/test passed)
$lintSuccess = $true
if ($buildSuccess -and $testSuccess -and -not $SkipLint -and $stackInfo.lint_cmd) {
    $lintSuccess = Invoke-GateStep -StepName "Lint" -CommandLine $stackInfo.lint_cmd
}

$sw.Stop()
$overallPass = ($buildSuccess -and $testSuccess -and $lintSuccess)

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
