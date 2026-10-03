<#
.SYNOPSIS
    Parses test coverage reports deterministically and verifies coverage thresholds.
.DESCRIPTION
    Scans repository for common coverage reports (Cobertura XML, LCOV, coverage-summary JSON),
    extracts line and branch coverage rates, and verifies against a target threshold.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Threshold
    Minimum line coverage percentage required (default: 80.0).
.PARAMETER ReportPath
    Explicit path to a coverage report file (optional).
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/check-test-coverage.ps1 -Threshold 80 -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [double]$Threshold = 80.0,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$foundFile = $null
$format = "none"

# 1. Locate coverage report
if ($ReportPath) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $RepoRoot $ReportPath }
    if (Test-Path $fullPath) {
        $foundFile = $fullPath
    }
} else {
    # Scan for common patterns
    $candidates = @(
        "coverage.cobertura.xml",
        "cobertura.xml",
        "TestResults/**/coverage.cobertura.xml",
        "coverage/lcov.info",
        "lcov.info",
        "coverage/coverage-summary.json",
        "tarpaulin-report.json"
    )

    foreach ($pattern in $candidates) {
        $match = Get-ChildItem -Path $RepoRoot -Filter (Split-Path $pattern -Leaf) -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch '[\\/](\.git|_agents|\.agents)[\\/]' } |
                 Select-Object -First 1
        if ($match) {
            $foundFile = $match.FullName
            break
        }
    }
}

$lineCoveragePct = 0.0
$branchCoveragePct = 0.0
$hasBranch = $false
$coverageFound = $false

if ($foundFile -and (Test-Path $foundFile)) {
    $coverageFound = $true
    $fileName = Split-Path $foundFile -Leaf

    # Cobertura XML
    if ($fileName -match '(?i)cobertura.*\.xml$') {
        $format = "cobertura"
        try {
            [xml]$xml = Get-Content -Path $foundFile -Raw
            if ($xml.coverage -and $xml.coverage.'line-rate') {
                $lineRate = [double]$xml.coverage.'line-rate'
                $lineCoveragePct = [Math]::Round($lineRate * 100, 2)
            }
            if ($xml.coverage -and $xml.coverage.'branch-rate') {
                $branchRate = [double]$xml.coverage.'branch-rate'
                $branchCoveragePct = [Math]::Round($branchRate * 100, 2)
                $hasBranch = $true
            }
        } catch {
            $format = "corrupt"
        }
    }
    # LCOV
    elseif ($fileName -match '(?i)lcov\.info$') {
        $format = "lcov"
        $linesFound = 0
        $linesHit = 0
        $branchesFound = 0
        $branchesHit = 0

        Get-Content -Path $foundFile | ForEach-Object {
            if ($_ -match '^LF:(\d+)') { $linesFound += [int]$Matches[1] }
            elseif ($_ -match '^LH:(\d+)') { $linesHit += [int]$Matches[1] }
            elseif ($_ -match '^BRF:(\d+)') { $branchesFound += [int]$Matches[1] }
            elseif ($_ -match '^BRH:(\d+)') { $branchesHit += [int]$Matches[1] }
        }

        if ($linesFound -gt 0) {
            $lineCoveragePct = [Math]::Round(($linesHit / $linesFound) * 100, 2)
        }
        if ($branchesFound -gt 0) {
            $branchCoveragePct = [Math]::Round(($branchesHit / $branchesFound) * 100, 2)
            $hasBranch = $true
        }
    }
    # JSON Summary (Istanbul / Jest)
    elseif ($fileName -match '(?i)coverage-summary\.json$') {
        $format = "istanbul-json"
        try {
            $json = Get-Content -Path $foundFile -Raw | ConvertFrom-Json
            if ($json.total -and $json.total.lines -and $null -ne $json.total.lines.pct) {
                $lineCoveragePct = [Math]::Round([double]$json.total.lines.pct, 2)
            }
            if ($json.total -and $json.total.branches -and $null -ne $json.total.branches.pct) {
                $branchCoveragePct = [Math]::Round([double]$json.total.branches.pct, 2)
                $hasBranch = $true
            }
        } catch {
            $format = "corrupt"
        }
    }
}

$status = "pass"
$message = ""

if (-not $coverageFound) {
    $status = "pass"
    $message = "No test coverage artifacts found (cobertura, lcov, or coverage-summary.json)."
} else {
    if ($lineCoveragePct -lt $Threshold) {
        $status = "fail"
        $message = "Line coverage ($lineCoveragePct%) is below the required threshold ($Threshold%)."
    } else {
        $status = "pass"
        $message = "Line coverage ($lineCoveragePct%) meets or exceeds the required threshold ($Threshold%)."
    }
}

$result = [ordered]@{
    status              = $status
    coverage_found      = $coverageFound
    format              = $format
    report_file         = if ($foundFile) { [System.IO.Path]::GetRelativePath($RepoRoot, $foundFile).Replace('\', '/') } else { $null }
    line_coverage_pct   = $lineCoveragePct
    branch_coverage_pct = if ($hasBranch) { $branchCoveragePct } else { $null }
    threshold_pct       = $Threshold
    message             = $message
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Test Coverage Check Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq "pass") { "Green" } else { "Red" })
    Write-Host "Report Found: $coverageFound"
    if ($coverageFound) {
        Write-Host "Format: $format"
        Write-Host "Report File: $($result.report_file)"
        Write-Host "Line Coverage: $lineCoveragePct% (Threshold: $Threshold%)"
        if ($hasBranch) { Write-Host "Branch Coverage: $branchCoveragePct%" }
    }
    Write-Host "Message: $message"
}

if ($status -ne "pass") {
    exit 1
} else {
    exit 0
}
