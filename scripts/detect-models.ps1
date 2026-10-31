<#
.SYNOPSIS
    Detects the current AI execution environment, available model catalog, and optimal execution mode.
.DESCRIPTION
    Inspects whether Antigravity CLI (agy), GitHub Copilot (gh copilot), or generic LLM environments are active.
    Outputs a structured JSON object specifying the detected platform, execution mode (multi_agent vs. sequential_persona),
    and available model tiers without consuming cloud tokens.
    Persists detection results to a cross-session cache with a 24-hour TTL (configurable) to eliminate redundant probing.
.PARAMETER OutputPath
    Optional file path to persist the detected configuration.
.PARAMETER CachePath
    Optional custom path to the cache file. Defaults to %LOCALAPPDATA%/agent-skills/model-cache.json (Windows)
    or ~/.cache/agent-skills/model-cache.json (macOS/Linux).
.PARAMETER MaxAgeHours
    Cache time-to-live in hours. Default is 24.
.PARAMETER Force
    Switch to bypass the cache and force an immediate re-probe of the environment.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/detect-models.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/detect-models.ps1 -Force
.EXAMPLE
    pwsh -NoProfile -File ./scripts/detect-models.ps1 -MaxAgeHours 12
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$CachePath,

    [Parameter(Mandatory = $false)]
    [int]$MaxAgeHours = 24,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Determine persistent cache location across sessions & skills
if (-not $CachePath) {
    if ($IsWindows -or $env:OS -match 'Windows') {
        $baseDir = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE "AppData\Local" } else { "." }
        $cacheDir = Join-Path $baseDir "agent-skills"
    } else {
        $baseDir = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } elseif ($env:HOME) { Join-Path $env:HOME ".cache" } else { "." }
        $cacheDir = Join-Path $baseDir "agent-skills"
    }
    $CachePath = Join-Path $cacheDir "model-cache.json"
}

# 2. Check existing cache unless -Force was specified
if (-not $Force -and (Test-Path $CachePath)) {
    try {
        $cachedRaw = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
        $cachedObj = $cachedRaw | ConvertFrom-Json
        if ($cachedObj.timestamp) {
            $cacheTime = [DateTime]::Parse($cachedObj.timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $ageHours = ((Get-Date).ToUniversalTime() - $cacheTime).TotalHours
            if ($ageHours -ge 0 -and $ageHours -lt $MaxAgeHours) {
                # Attach/update cache metadata
                $cachedObj | Add-Member -MemberType NoteProperty -Name "cached" -Value $true -Force
                $cachedObj | Add-Member -MemberType NoteProperty -Name "cached_at" -Value $cachedObj.timestamp -Force
                $cachedObj | Add-Member -MemberType NoteProperty -Name "cache_expires_at" -Value ($cacheTime.AddHours($MaxAgeHours).ToString("o")) -Force
                $cachedObj | Add-Member -MemberType NoteProperty -Name "cache_file" -Value $CachePath -Force

                $jsonOutput = $cachedObj | ConvertTo-Json -Depth 5
                if ($OutputPath) {
                    $parentDir = Split-Path -Parent $OutputPath
                    if ($parentDir -and !(Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                    }
                    [System.IO.File]::WriteAllText($OutputPath, $jsonOutput, [System.Text.UTF8Encoding]::new($false))
                }
                Write-Output $jsonOutput
                return
            }
        }
    } catch {
        # On cache corruption or read failure, proceed with probe
    }
}

# 3. Perform fresh environment probe
$now = (Get-Date).ToUniversalTime()
$result = [ordered]@{
    timestamp          = $now.ToString("o")
    cached             = $false
    cache_expires_at   = $now.AddHours($MaxAgeHours).ToString("o")
    cache_file         = $CachePath
    platform           = "generic"
    execution_mode     = "sequential_persona"
    cost_efficiency    = $true
    cost_guardrail     = [ordered]@{
        enabled                            = $true
        max_routine_cost_class             = "versatile"
        flagship_threshold_input_per_m     = 4.00
        flagship_threshold_output_per_m    = 20.00
        throttle_routine_to_cost_efficient = $true
    }
    supports_subagents = $false
    detected_models    = @()
    recommended_tiers  = [ordered]@{}
}

# 3.1. Probe for Antigravity (agy CLI or Antigravity runtime environment)
$agyCmd = Get-Command agy -ErrorAction SilentlyContinue
$isAntigravityEnv = ($null -ne $agyCmd) -or ($null -ne $env:ANTIGRAVITY_CLI_ALIAS) -or (Test-Path (Join-Path $HOME ".gemini\antigravity")) -or (Test-Path (Join-Path $HOME ".gemini\antigravity-cli"))
if ($isAntigravityEnv) {
    $result.platform = "antigravity"
    $result.execution_mode = "multi_agent"
    $result.supports_subagents = $true

    $rawModels = $null
    if ($agyCmd) {
        try {
            $rawModels = & agy models 2>$null
        } catch {
            $rawModels = $null
        }
    }
    if ($rawModels) {
        $modelList = @()
        foreach ($item in $rawModels) {
            foreach ($line in ($item -split "`r?`n")) {
                if ($line -match '^(\S+)\s+(.+)$' -and $matches[1] -ne "Fetching") {
                    $modelList += [ordered]@{
                        id   = $matches[1]
                        name = $matches[2].Trim()
                    }
                }
            }
        }
        $result.detected_models = $modelList
    }

    $result.recommended_tiers = [ordered]@{
        tier_1 = [ordered]@{ model_class = "inherit"; fallback = "flash"; exception_model_class = "pro"; reasoning_effort = "high_extended" }
        tier_2 = [ordered]@{ model_class = "inherit"; fallback = "flash"; exception_model_class = "pro"; reasoning_effort = "high" }
        tier_3 = [ordered]@{ model_class = "inherit"; fallback = "flash"; reasoning_effort = "medium" }
        tier_4 = [ordered]@{ model_class = "flash"; fallback = "flash_lite"; reasoning_effort = "low" }
    }

    if ($modelList -and $modelList.Count -gt 0) {
        $flagshipHigh = ($modelList | Where-Object { $_.id -match '(opus|gemini-4|argon|pro|gpt-[56]|astra).*(high|extended)' -or $_.id -match 'opus|gemini-4.*pro|gpt-6.*astra' } | Select-Object -First 1).id
        $analyticalHigh = ($modelList | Where-Object { $_.id -match '(sonnet|gemini-4|argon|gpt-[56]|sol).*(high|medium)|gpt-6\.1-sol' } | Select-Object -First 1).id
        $flashHigh = ($modelList | Where-Object { $_.id -match '(flash|haiku|mini|luna).*high' } | Select-Object -First 1).id
        $flashMed = ($modelList | Where-Object { $_.id -match '(flash|argon|sonnet|gpt-6|sol).*medium|gpt-6\.1-sol' } | Select-Object -First 1).id
        $flashLow = ($modelList | Where-Object { $_.id -match '(flash|haiku|mini|luna).*low|gpt-6.*(mini|luna)' } | Select-Object -First 1).id

        $result.active_model_mapping = [ordered]@{
            tier_1_deep_reasoning = if ($flagshipHigh) { $flagshipHigh } elseif ($flashHigh) { $flashHigh } else { "inherit" }
            tier_2_analytical     = if ($analyticalHigh) { $analyticalHigh } elseif ($flashHigh) { $flashHigh } else { "inherit" }
            tier_3_balanced       = if ($flashMed) { $flashMed } elseif ($flashHigh) { $flashHigh } else { "inherit" }
            tier_4_deterministic  = if ($flashLow) { $flashLow } elseif ($flashMed) { $flashMed } else { "flash" }
        }
    }
}
# 3.2. Probe for standalone GitHub Copilot CLI ('copilot') or gh-copilot extension
elseif ((Get-Command copilot -ErrorAction SilentlyContinue) -or ($null -ne $env:COPILOT_CLI) -or (Test-Path (Join-Path $HOME ".copilot")) -or ((Get-Command gh -ErrorAction SilentlyContinue) -and ((& gh extension list 2>$null) -match 'gh-copilot'))) {
    $hasCopilotCli = ($null -ne (Get-Command copilot -ErrorAction SilentlyContinue))
    $result.platform = "copilot"
    $result.execution_mode = "sequential_persona"
    $result.supports_subagents = $hasCopilotCli
    $result.recommended_tiers = [ordered]@{
        tier_1 = [ordered]@{ reasoning_effort = "high"; strategy = "maximum_thinking"; preferred_family = "gpt-6-astra / gpt-6-high / claude-opus" }
        tier_2 = [ordered]@{ reasoning_effort = "high"; strategy = "analytical"; preferred_family = "gpt-6.1-sol / gpt-6 / claude-sonnet" }
        tier_3 = [ordered]@{ reasoning_effort = "medium"; strategy = "balanced"; preferred_family = "gpt-6.1-sol / gpt-6-medium / claude-sonnet" }
        tier_4 = [ordered]@{ reasoning_effort = "low"; strategy = "deterministic"; preferred_family = "gpt-6.1-luna / gpt-6-mini / gpt-5.4-mini" }
    }
}
# 3.3. Generic LLM Fallback
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

# 4. Save to persistent cache file
try {
    $cacheParent = Split-Path -Parent $CachePath
    if ($cacheParent -and !(Test-Path $cacheParent)) {
        New-Item -ItemType Directory -Path $cacheParent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($CachePath, $jsonOutput, [System.Text.UTF8Encoding]::new($false))
} catch {
    # If cache directory is unwritable, continue gracefully
}

# 5. Save to explicit OutputPath if requested
if ($OutputPath) {
    $parentDir = Split-Path -Parent $OutputPath
    if ($parentDir -and !(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $jsonOutput, [System.Text.UTF8Encoding]::new($false))
}

Write-Output $jsonOutput
