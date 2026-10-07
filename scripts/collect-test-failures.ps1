#Requires -Version 5.1
<#
.SYNOPSIS
    Deterministic test failure diagnostics and stack trace extractor.
.DESCRIPTION
    Inspects test runner output artifacts (*.trx, JUnit *.xml) or runs tests with
    structured logging to extract concise failure diagnostics with zero token bloat:
    - Failed test name and declaring class
    - Exception message / assertion failure text
    - Compact application stack trace (filters out test runner framework internals)
.PARAMETER RepoRoot
    Optional path to the project repository root. Defaults to current directory.
.PARAMETER ResultsPath
    Explicit path to a .trx or .xml test report file or directory.
.PARAMETER Run
    Switch to execute the project's native test runner with structured logger and parse results.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/collect-test-failures.ps1
    pwsh -NoProfile -File ./scripts/collect-test-failures.ps1 -Run
    pwsh -NoProfile -File ./scripts/collect-test-failures.ps1 -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$ResultsPath,

    [Parameter(Mandatory = $false)]
    [switch]$Run,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

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

# 1. Optionally run test runner with structured logger
if ($Run) {
    $isDotnet = (Get-ChildItem -Path $RepoRoot -Filter "*.sln" -Depth 2 2>$null | Select-Object -First 1) -ne $null -or
                (Get-ChildItem -Path $RepoRoot -Filter "*.csproj" -Depth 3 2>$null | Select-Object -First 1) -ne $null
    
    if ($isDotnet) {
        $trxDir = Join-Path $RepoRoot "TestResults"
        if (-not (Test-Path $trxDir)) { New-Item -ItemType Directory -Path $trxDir -Force | Out-Null }
        $trxFile = Join-Path $trxDir "run_diagnostics.trx"
        if (Test-Path $trxFile) { Remove-Item $trxFile -Force }

        $proc = Start-Process -FilePath "dotnet" -ArgumentList @("test", "--logger", "trx;LogFileName=run_diagnostics.trx", "--verbosity", "quiet") -WorkingDirectory $RepoRoot -NoNewWindow -PassThru -Wait
        $ResultsPath = $trxFile
    }
}

# 2. Locate test result files
$reportFiles = [System.Collections.Generic.List[string]]::new()
if ($ResultsPath) {
    if (Test-Path $ResultsPath) {
        if ((Get-Item $ResultsPath) -is [System.IO.DirectoryInfo]) {
            Get-ChildItem -Path $ResultsPath -Include "*.trx", "*junit*.xml", "*test*.xml" -Recurse -File | ForEach-Object { $reportFiles.Add($_.FullName) }
        } else {
            $reportFiles.Add((Resolve-Path $ResultsPath).Path)
        }
    }
} else {
    # Auto-discover recent result files
    $candidateDirs = @(
        (Join-Path $RepoRoot "TestResults"),
        (Join-Path $RepoRoot "test-results"),
        (Join-Path $RepoRoot "target/surefire-reports"),
        (Join-Path $RepoRoot ".pytest_cache")
    )

    foreach ($cd in $candidateDirs) {
        if (Test-Path $cd) {
            Get-ChildItem -Path $cd -Include "*.trx", "*.xml" -Recurse -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 3 |
                ForEach-Object { $reportFiles.Add($_.FullName) }
        }
    }
}

$failures = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalTests = 0
$totalFailed = 0
$totalPassed = 0

function Clean-StackTrace {
    param([string]$RawStack)
    if (-not $RawStack) { return "" }
    $lines = $RawStack -split "`r?`n"
    $filtered = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        # Filter out deep framework internals
        if ($trimmed -match 'System\.Runtime\.' -or
            $trimmed -match 'Microsoft\.VisualStudio\.TestPlatform\.' -or
            $trimmed -match 'Xunit\.Sdk\.' -or
            $trimmed -match 'NUnit\.Framework\.Internal\.') {
            continue
        }
        $filtered.Add($trimmed)
        if ($filtered.Count -ge 8) { break }
    }
    return ($filtered -join "`n")
}

# 3. Parse report files
foreach ($rf in $reportFiles) {
    if (-not (Test-Path $rf)) { continue }
    try {
        [xml]$xml = Get-Content -Path $rf -Raw -Encoding UTF8

        # 3a. MSTest / VSTest .trx format
        if ($xml.TestRun) {
            $resultsNode = $xml.TestRun.Results
            if ($resultsNode) {
                foreach ($utr in $resultsNode.UnitTestResult) {
                    $totalTests++
                    $outcome = $utr.outcome
                    if ($outcome -eq "Passed") {
                        $totalPassed++
                    } elseif ($outcome -eq "Failed") {
                        $totalFailed++
                        $errMsg = ""
                        $stack = ""
                        if ($utr.Output -and $utr.Output.ErrorInfo) {
                            $errMsg = [string]$utr.Output.ErrorInfo.Message
                            $stack = Clean-StackTrace ([string]$utr.Output.ErrorInfo.StackTrace)
                        }
                        $failures.Add([PSCustomObject]@{
                            TestName = $utr.testName
                            Outcome = "Failed"
                            Duration = $utr.duration
                            ErrorMessage = $errMsg.Trim()
                            StackTrace = $stack
                            ReportFile = [System.IO.Path]::GetFileName($rf)
                        })
                    }
                }
            }
        }
        # 3b. JUnit / xUnit XML format
        elseif ($xml.testsuites -or $xml.testsuite) {
            $suites = if ($xml.testsuites) { $xml.testsuites.testsuite } else { @($xml.testsuite) }
            foreach ($ts in $suites) {
                foreach ($tc in $ts.testcase) {
                    $totalTests++
                    if ($tc.failure) {
                        $totalFailed++
                        $msg = if ($tc.failure.message) { $tc.failure.message } else { [string]$tc.failure }
                        $stack = Clean-StackTrace ([string]$tc.failure)
                        $failures.Add([PSCustomObject]@{
                            TestName = "$($tc.classname).$($tc.name)"
                            Outcome = "Failed"
                            Duration = $tc.time
                            ErrorMessage = [string]$msg
                            StackTrace = $stack
                            ReportFile = [System.IO.Path]::GetFileName($rf)
                        })
                    } else {
                        $totalPassed++
                    }
                }
            }
        }
    } catch {
        # skip malformed xml
    }
}

$isPass = ($failures.Count -eq 0)

$result = [ordered]@{
    status = if ($isPass) { "pass" } else { "fail" }
    reports_scanned = $reportFiles.Count
    total_tests = $totalTests
    passed_count = $totalPassed
    failed_count = $failures.Count
    failures = $failures.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Test Failure Diagnostics Collector" -ForegroundColor Cyan
    Write-Host "Reports: $($reportFiles.Count) | Tests: $totalTests | Failed: $($failures.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($isPass) {
        Write-Host "Diagnostics Status: PASS (0 test failures detected)" -ForegroundColor Green
    } else {
        Write-Host "Diagnostics Status: FAIL ($($failures.Count) test failures detected)" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host "`n  [FAILED] $($f.TestName)" -ForegroundColor Yellow
            if ($f.ErrorMessage) {
                Write-Host "  Error : $($f.ErrorMessage)" -ForegroundColor DarkYellow
            }
            if ($f.StackTrace) {
                Write-Host "  Stack :" -ForegroundColor DarkGray
                foreach ($line in ($f.StackTrace -split "`n")) {
                    Write-Host "    $line" -ForegroundColor DarkGray
                }
            }
        }
    }
    Write-Host "`n=============================================" -ForegroundColor Cyan
}

if (-not $isPass) {
    exit 1
}
