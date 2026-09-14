<#
.SYNOPSIS
    Detects the current AI execution environment, available model catalog, and optimal execution mode.
.DESCRIPTION
    Inspects whether Antigravity CLI (agy), GitHub Copilot (gh copilot), or generic LLM environments are active.
    Outputs a structured JSON object specifying the detected platform, execution mode (multi_agent vs. sequential_persona),
    and available model tiers without consuming cloud tokens.
.PARAMETER OutputPath
    Optional file path to persist the detected configuration.
.EXAMPLE
    pwsh -File ./scripts/detect-models.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

$result = [ordered]@{
    timestamp        = (Get-Date).ToUniversalTime().ToString("o")
    platform         = "generic"
    execution_mode   = "sequential_persona"
    supports_subagents = $false
    detected_models  = @()
    recommended_tiers = [ordered]@{}
}

# 1. Probe for Antigravity CLI (agy)
$agyCmd = Get-Command agy -ErrorAction SilentlyContinue
if ($agyCmd) {
    $result.platform = "antigravity"
    $result.execution_mode = "multi_agent"
    $result.supports_subagents = $true

    $rawModels = & agy models 2>$null
    if ($rawModels) {
        $modelList = @()
        foreach ($line in ($rawModels -split "`r?`n")) {
            if ($line -match '^(\S+)\s+(.+)$' -and $matches[1] -ne "Fetching") {
                $modelList += [ordered]@{
                    id   = $matches[1]
                    name = $matches[2].Trim()
                }
            }
        }
        $result.detected_models = $modelList
    }

    $result.recommended_tiers = [ordered]@{
        tier_1 = [ordered]@{ model_class = "pro"; reasoning_effort = "high" }
        tier_2 = [ordered]@{ model_class = "flash"; reasoning_effort = "high" }
        tier_3 = [ordered]@{ model_class = "flash"; reasoning_effort = "medium" }
        tier_4 = [ordered]@{ model_class = "flash_lite"; fallback = "flash"; reasoning_effort = "low" }
    }
}
# 2. Probe for GitHub Copilot / gh CLI
elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    $result.platform = "copilot"
    $result.execution_mode = "sequential_persona"
    $result.supports_subagents = $false
    $result.recommended_tiers = [ordered]@{
        tier_1 = [ordered]@{ reasoning_effort = "high"; strategy = "maximum_thinking" }
        tier_2 = [ordered]@{ reasoning_effort = "high"; strategy = "analytical" }
        tier_3 = [ordered]@{ reasoning_effort = "medium"; strategy = "balanced" }
        tier_4 = [ordered]@{ reasoning_effort = "low"; strategy = "deterministic" }
    }
}
# 3. Generic LLM Fallback
else {
    $result.platform = "generic"
    $result.execution_mode = "sequential_persona"
    $result.supports_subagents = $false
    $result.recommended_tiers = [ordered]@{
        tier_1 = [ordered]@{ reasoning_effort = "high"; strategy = "deep_reasoning" }
        tier_2 = [ordered]@{ reasoning_effort = "high"; strategy = "focused_analysis" }
        tier_3 = [ordered]@{ reasoning_effort = "medium"; strategy = "implementation" }
        tier_4 = [ordered]@{ reasoning_effort = "low"; strategy = "fast_execution" }
    }
}

$jsonOutput = $result | ConvertTo-Json -Depth 5

if ($OutputPath) {
    $parentDir = Split-Path -Parent $OutputPath
    if ($parentDir -and !(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $jsonOutput, [System.Text.UTF8Encoding]::new($false))
}

Write-Output $jsonOutput
