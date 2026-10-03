<#
.SYNOPSIS
    Displays and summarizes lifecycle telemetry metrics for ask-skills.
.DESCRIPTION
    Parses telemetry.jsonl and outputs a structured summary of phase durations,
    profile usage, and circuit-breaker triggers.
.PARAMETER Limit
    Number of recent telemetry records to display. Default is 25.
.PARAMETER SessionId
    Optional filter for a specific session ID.
.PARAMETER JsonOutput
    Switch to output results as JSON.
.PARAMETER TelemetryPath
    Optional custom path to the telemetry.jsonl file.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/show-telemetry.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/show-telemetry.ps1 -Limit 10
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Limit = 25,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput,

    [Parameter(Mandatory = $false)]
    [string]$TelemetryPath
)

$ErrorActionPreference = 'Stop'

if (-not $TelemetryPath) {
    if ($IsWindows -or $env:OS -match 'Windows') {
        $baseDir = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE "AppData\Local" } else { "." }
    } else {
        $baseDir = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } elseif ($env:HOME) { Join-Path $env:HOME ".cache" } else { "." }
    }
    $TelemetryPath = Join-Path (Join-Path $baseDir "agent-skills") "telemetry.jsonl"
}

if (-not (Test-Path $TelemetryPath)) {
    if ($JsonOutput) {
        @{ total_records = 0; records = @() } | ConvertTo-Json
    } else {
        Write-Host "No telemetry records found at: $TelemetryPath" -ForegroundColor Yellow
    }
    exit 0
}

$lines = Get-Content -Path $TelemetryPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$records = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($line in $lines) {
    try {
        $rec = $line | ConvertFrom-Json
        if (-not $SessionId -or $rec.session_id -eq $SessionId) {
            $records.Add($rec)
        }
    } catch {
        # ignore corrupted lines
    }
}

$recentRecords = @($records | Select-Object -Last $Limit)

if ($JsonOutput) {
    [PSCustomObject]@{
        total_records = $records.Count
        displayed_records = $recentRecords.Count
        records = $recentRecords
    } | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "ask-skills Lifecycle Telemetry Dashboard" -ForegroundColor Cyan
Write-Host "Log: $TelemetryPath" -ForegroundColor DarkGray
Write-Host "Total Records: $($records.Count) | Showing: $($recentRecords.Count)" -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Cyan

if ($recentRecords.Count -gt 0) {
    $tableData = foreach ($r in $recentRecords) {
        [PSCustomObject]@{
            Timestamp   = $r.timestamp
            Phase       = $r.phase
            Event       = $r.event
            Status      = $r.status
            DurationMs  = $r.duration_ms
            Profile     = if ($r.profile) { $r.profile } else { "-" }
        }
    }
    $tableData | Format-Table -AutoSize

    # Phase summary statistics
    $phaseGroups = $records | Where-Object { $_.duration_ms -gt 0 } | Group-Object -Property phase
    if ($phaseGroups.Count -gt 0) {
        Write-Host "--- Phase Duration Metrics ---" -ForegroundColor Yellow
        $metrics = foreach ($g in $phaseGroups) {
            $durations = $g.Group | ForEach-Object { [int]$_.duration_ms }
            $avg = ($durations | Measure-Object -Average).Average
            $total = ($durations | Measure-Object -Sum).Sum
            [PSCustomObject]@{
                Phase = $g.Name
                Executions = $g.Count
                AvgDurationMs = [math]::Round($avg, 0)
                TotalDurationMs = $total
            }
        }
        $metrics | Format-Table -AutoSize
    }
}
