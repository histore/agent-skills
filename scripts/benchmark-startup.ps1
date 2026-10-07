#Requires -Version 5.1
<#
.SYNOPSIS
    Deterministic benchmark tool measuring application cold and warm startup times.
.DESCRIPTION
    Measures time from process launch to initial UI window handle creation or process readiness.
    Provides min, max, and average startup durations across multiple iterations without token cost.
.PARAMETER RepoRoot
    Optional path to repository root. Defaults to current directory.
.PARAMETER ExecutablePath
    Explicit path to the executable to benchmark. Auto-discovered if omitted.
.PARAMETER Iterations
    Number of benchmark iterations to execute. Defaults to 3.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for window handle readiness per run. Defaults to 15.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/benchmark-startup.ps1
    pwsh -NoProfile -File ./scripts/benchmark-startup.ps1 -Iterations 5
    pwsh -NoProfile -File ./scripts/benchmark-startup.ps1 -ExecutablePath "./bin/Release/net10.0/App.exe"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$ExecutablePath,

    [Parameter(Mandatory = $false)]
    [int]$Iterations = 3,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 15,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $superproject = git rev-parse --show-superproject-working-tree 2>$null
    if ($superproject) { $RepoRoot = $superproject.Trim() }
    else {
        $toplevel = git rev-parse --show-toplevel 2>$null
        if ($toplevel) {
            $root = $toplevel.Trim()
            if ($root -match '[\\/](_agents|\.agents)$') { $root = Split-Path -Parent $root }
            $RepoRoot = $root
        } else {
            $RepoRoot = (Get-Location).Path
        }
    }
}

# 1. Discover executable if not provided
if (-not $ExecutablePath) {
    $candidates = @()
    # Check publish/
    $candidates += Get-ChildItem -Path (Join-Path $RepoRoot "publish") -Filter "*.exe" -File 2>$null
    # Check bin/
    $candidates += Get-ChildItem -Path (Join-Path $RepoRoot "bin") -Filter "*.exe" -Recurse -File 2>$null | Where-Object { $_.FullName -notmatch 'testhost' }
    # Check MultiShell/bin/ or src/*/bin/
    $candidates += Get-ChildItem -Path $RepoRoot -Filter "*.exe" -Recurse -File -Depth 5 2>$null | Where-Object {
        $_.FullName -notmatch 'testhost' -and
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]obj[\\/]'
    }

    $targetExe = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($targetExe) {
        $ExecutablePath = $targetExe.FullName
    }
}

if (-not $ExecutablePath -or -not (Test-Path $ExecutablePath)) {
    if ($JsonOutput) {
        @{ status = "skipped"; message = "Executable not found. Build the project first."; executable = $null } | ConvertTo-Json
    } else {
        Write-Host "Benchmark Startup: SKIPPED (No executable found in $RepoRoot. Please build the project first.)" -ForegroundColor Yellow
    }
    exit 0
}

$exeName = [System.IO.Path]::GetFileName($ExecutablePath)
$runs = [System.Collections.Generic.List[PSCustomObject]]::new()

for ($iter = 1; $iter -le $Iterations; $iter++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $ExecutablePath
    $pinfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($ExecutablePath)
    $pinfo.UseShellExecute = $true

    $proc = $null
    $readyMs = 0
    $timedOut = $false

    try {
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $timeoutLimit = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

        while ([DateTime]::UtcNow -lt $timeoutLimit) {
            Start-Sleep -Milliseconds 50
            if ($proc.HasExited) {
                $readyMs = $sw.ElapsedMilliseconds
                break
            }
            $proc.Refresh()
            if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
                $readyMs = $sw.ElapsedMilliseconds
                break
            }
        }

        if ($readyMs -eq 0 -and (-not $proc.HasExited)) {
            $timedOut = $true
            $readyMs = $sw.ElapsedMilliseconds
        }
    } finally {
        $sw.Stop()
        if ($proc -and (-not $proc.HasExited)) {
            try {
                $proc.CloseMainWindow() | Out-Null
                Start-Sleep -Milliseconds 200
                if (-not $proc.HasExited) {
                    $proc.Kill()
                }
            } catch { }
        }
    }

    $runs.Add([PSCustomObject]@{
        Iteration = $iter
        DurationMs = $readyMs
        TimedOut = $timedOut
    })
    # Small pause between runs for cooldown
    Start-Sleep -Milliseconds 300
}

$validRuns = @($runs | Where-Object { -not $_.TimedOut })
$minMs = if ($validRuns.Count -gt 0) { ($validRuns | Measure-Object -Property DurationMs -Minimum).Minimum } else { 0 }
$maxMs = if ($validRuns.Count -gt 0) { ($validRuns | Measure-Object -Property DurationMs -Maximum).Maximum } else { 0 }
$avgMs = if ($validRuns.Count -gt 0) { [Math]::Round(($validRuns | Measure-Object -Property DurationMs -Average).Average, 1) } else { 0 }

$result = [ordered]@{
    status = if ($validRuns.Count -gt 0) { "pass" } else { "fail" }
    executable = $exeName
    iterations = $Iterations
    avg_duration_ms = $avgMs
    min_duration_ms = $minMs
    max_duration_ms = $maxMs
    runs = $runs.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Application Startup Benchmark" -ForegroundColor Cyan
    Write-Host "Target: $exeName | Iterations: $Iterations" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Average Startup : $avgMs ms" -ForegroundColor Green
    Write-Host "  Min Duration    : $minMs ms" -ForegroundColor Green
    Write-Host "  Max Duration    : $maxMs ms" -ForegroundColor Green
    Write-Host "---------------------------------------------" -ForegroundColor DarkGray
    foreach ($r in $runs) {
        $note = if ($r.TimedOut) { " (TIMED OUT)" } else { "" }
        Write-Host "  Iteration $($r.Iteration)     : $($r.DurationMs) ms$note" -ForegroundColor DarkGray
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if ($validRuns.Count -eq 0) {
    exit 1
}
