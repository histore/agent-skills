#Requires -Version 5.1
<#
.SYNOPSIS
    Deterministic zero-token PreToolUse guardrail hook for both Antigravity (AGY) and GitHub Copilot CLI.
.DESCRIPTION
    Reads a PreToolUse JSON event payload from stdin (or -PayloadFile), auto-detects AGY vs. Copilot CLI schema,
    and deterministically enforces critical non-negotiable safety invariants:
      1. Destructive Git Guard (blocks 'git push --force'/'-f' and 'git reset --hard'; allows '--force-with-lease').
      2. Submodule Isolation Guard (blocks staging/committing '_agents' or '.agents' submodule paths).
      3. Safe Rust Guard (blocks 'unsafe' constructs and Rust 2024 '#[unsafe(...)]' attributes in '*.rs' writes/edits).
    Pure code formatters are intentionally excluded to preserve the Deferred-Format / No-Premature-Tests invariant.
.PARAMETER Format
    Target hook response format: 'auto' (default), 'agy', or 'copilot'.
.PARAMETER PayloadFile
    Optional path to a JSON payload file (used for deterministic testing instead of stdin).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/hook-pre-tool-guard.ps1 -Format copilot
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('auto', 'agy', 'copilot')]
    [string]$Format = 'auto',

    [Parameter(Mandatory = $false)]
    [string]$PayloadFile
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-HookResponse {
    param(
        [string]$ClientFormat,
        [bool]$Deny,
        [string]$Reason
    )
    if ($ClientFormat -eq 'copilot') {
        if ($Deny) {
            [ordered]@{
                permissionDecision = 'deny'
                reason             = $Reason
            } | ConvertTo-Json -Compress
        } else {
            '{}'
        }
    } else {
        if ($Deny) {
            [ordered]@{
                decision = 'deny'
                reason   = $Reason
            } | ConvertTo-Json -Compress
        } else {
            [ordered]@{
                decision = 'allow'
            } | ConvertTo-Json -Compress
        }
    }
}

$rawPayload = ''
if ($PayloadFile -and (Test-Path -LiteralPath $PayloadFile)) {
    $rawPayload = [System.IO.File]::ReadAllText($PayloadFile, [System.Text.Encoding]::UTF8)
} else {
    try {
        if ([Console]::IsInputRedirected) {
            $rawPayload = [Console]::In.ReadToEnd()
        }
    } catch {
        $rawPayload = ''
    }
}

$resolvedFormat = if ($Format -eq 'auto') { 'agy' } else { $Format }
if ([string]::IsNullOrWhiteSpace($rawPayload)) {
    Write-Output (Write-HookResponse -ClientFormat $resolvedFormat -Deny $false -Reason '')
    exit 0
}

$payload = $null
try {
    $payload = $rawPayload | ConvertFrom-Json
} catch {
    Write-Output (Write-HookResponse -ClientFormat $resolvedFormat -Deny $false -Reason '')
    exit 0
}

if ($Format -eq 'auto') {
    if ($null -ne $payload.toolCall -or $null -ne $payload.hookEventName) {
        $resolvedFormat = 'agy'
    } elseif ($null -ne $payload.toolName -or $null -ne $payload.toolArgs) {
        $resolvedFormat = 'copilot'
    }
}

$argsObj = $null
if ($null -ne $payload.toolCall -and $null -ne $payload.toolCall.args) {
    $argsObj = $payload.toolCall.args
} elseif ($null -ne $payload.toolArgs) {
    $argsObj = $payload.toolArgs
}

$commandText = ''
$targetPath = ''
$writtenParts = [System.Collections.Generic.List[string]]::new()

if ($null -ne $argsObj) {
    if ($argsObj.CommandLine) { $commandText = [string]$argsObj.CommandLine }
    elseif ($argsObj.command) { $commandText = [string]$argsObj.command }

    if ($argsObj.Path) { $targetPath = [string]$argsObj.Path }
    elseif ($argsObj.path) { $targetPath = [string]$argsObj.path }
    elseif ($argsObj.file_path) { $targetPath = [string]$argsObj.file_path }

    foreach ($prop in @('Replacement', 'Content', 'new_str', 'file_text', 'content')) {
        $val = $argsObj.$prop
        if (-not [string]::IsNullOrEmpty($val)) {
            $writtenParts.Add([string]$val)
        }
    }
}

$denyReason = ''

# 1. Destructive Git Guard
if (-not [string]::IsNullOrWhiteSpace($commandText)) {
    if (($commandText -match '(?i)\bgit\b[^\r\n;|&]*\bpush\b[^\r\n;|&]*((?<![-\w])--force(?![-\w])|(?<![-\w])-f(?![-\w]))') -and ($commandText -notmatch '(?i)--force-with-lease')) {
        $denyReason = "Destructive 'git push --force' is blocked by agent-skills PreToolUse guardrail. Use '--force-with-lease' only after explicit user confirmation."
    } elseif ($commandText -match '(?i)\bgit\b[^\r\n;|&]*\breset\b[^\r\n;|&]*--hard\b') {
        $denyReason = "Destructive 'git reset --hard' is blocked by agent-skills PreToolUse guardrail. Create a safety snapshot via diagnose-git-state and confirm with the user first."
    }
    # 2. Submodule Isolation Guard
    elseif ($commandText -match '(?i)\bgit\b[^\r\n;|&]*\b(add|stage|commit)\b[^\r\n;|&]*(^|[\s"''/\\])(_agents|\.agents)($|[\s"''/\\])') {
        $denyReason = "Submodule Isolation Guardrail: staging or committing '_agents' or '.agents' submodule paths in host workspace commits is prohibited."
    }
}

# 3. Safe Rust Guard (zero unsafe in *.rs edits/writes)
if ([string]::IsNullOrWhiteSpace($denyReason) -and $targetPath -match '(?i)\.rs$' -and $writtenParts.Count -gt 0) {
    $combinedWrite = ($writtenParts -join "`n")
    if ($combinedWrite -match '(?m)(^|[^\w])unsafe\s*(\{|fn\b|trait\b|impl\b|extern\b)|#\[unsafe\(') {
        $denyReason = "Safe Rust Invariant: 'unsafe' constructs and Rust 2024 '#[unsafe(...)]' attributes are strictly prohibited in Rust codebases."
    }
}

if (-not [string]::IsNullOrWhiteSpace($denyReason)) {
    Write-Output (Write-HookResponse -ClientFormat $resolvedFormat -Deny $true -Reason $denyReason)
} else {
    Write-Output (Write-HookResponse -ClientFormat $resolvedFormat -Deny $false -Reason '')
}
exit 0
