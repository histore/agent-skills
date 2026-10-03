<#
.SYNOPSIS
    Records structured lifecycle telemetry and phase transitions for ask-skills.
.DESCRIPTION
    Appends a structured JSONL event to a local cross-session telemetry log.
    Captures phase transitions, durations, profile classifications, and circuit-breaker events
    with zero token overhead and minimal execution time (< 15ms).
.PARAMETER Phase
    The lifecycle phase (e.g. IntentClassification, Specification, Architecture, DeveloperInnerLoop, Verification, GitLifecycle).
.PARAMETER Event
    The type of telemetry event: phase_start, phase_end, checkpoint, circuit_breaker, anomaly_gate.
.PARAMETER Status
    Status of the phase or event: running, success, failed, escalated, bypassed.
.PARAMETER DurationMs
    Optional duration of the phase in milliseconds.
.PARAMETER Profile
    Optional active execution profile (Profile 0, Profile A, Profile B, Profile C).
.PARAMETER SessionId
    Optional session/conversation ID.
.PARAMETER Details
    Optional hashtable or JSON string with additional metrics.
.PARAMETER TelemetryPath
    Optional custom path to the telemetry.jsonl file.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/record-telemetry.ps1 -Phase "DeveloperInnerLoop" -Event "phase_end" -Status "success" -DurationMs 3400 -Profile "Profile A"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Phase,

    [Parameter(Mandatory = $true)]
    [ValidateSet('phase_start', 'phase_end', 'checkpoint', 'circuit_breaker', 'anomaly_gate')]
    [string]$Event,

    [Parameter(Mandatory = $false)]
    [ValidateSet('running', 'success', 'failed', 'escalated', 'bypassed')]
    [string]$Status = 'success',

    [Parameter(Mandatory = $false)]
    [int]$DurationMs = 0,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$Details,

    [Parameter(Mandatory = $false)]
    [string]$TelemetryPath
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Determine persistent telemetry location
if (-not $TelemetryPath) {
    if ($IsWindows -or $env:OS -match 'Windows') {
        $baseDir = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE "AppData\Local" } else { "." }
        $dir = Join-Path $baseDir "agent-skills"
    } else {
        $baseDir = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } elseif ($env:HOME) { Join-Path $env:HOME ".cache" } else { "." }
        $dir = Join-Path $baseDir "agent-skills"
    }
    if (-not (Test-Path $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    $TelemetryPath = Join-Path $dir "telemetry.jsonl"
}

# 2. Check for log rotation (Max 10 MB)
try {
    if (Test-Path $TelemetryPath) {
        $fileInfo = Get-Item $TelemetryPath
        if ($fileInfo.Length -gt 10MB) {
            $bakPath = "${TelemetryPath}.bak"
            if (Test-Path $bakPath) { Remove-Item -Path $bakPath -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $TelemetryPath -Destination $bakPath -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    # Silently proceed on rotation errors
}

# 3. Resolve session ID
if (-not $SessionId) {
    $SessionId = if ($env:CONVERSATION_ID) { $env:CONVERSATION_ID } else { "session-" + (Get-Date -Format "yyyyMMdd") }
}

# 4. Construct telemetry record
$record = [ordered]@{
    timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    session_id  = $SessionId
    phase       = $Phase
    event       = $Event
    status      = $Status
    duration_ms = $DurationMs
}

if ($Profile) {
    $record["profile"] = $Profile
}

if ($Details) {
    try {
        $parsed = $Details | ConvertFrom-Json
        $record["details"] = $parsed
    } catch {
        $record["details"] = $Details
    }
}

# 5. Atomic append to JSONL
try {
    $jsonLine = ($record | ConvertTo-Json -Compress) + "`n"
    [System.IO.File]::AppendAllText($TelemetryPath, $jsonLine, [System.Text.UTF8Encoding]::new($false))
} catch {
    # Non-blocking telemetry failure
}
