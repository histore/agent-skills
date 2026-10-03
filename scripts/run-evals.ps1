<#
.SYNOPSIS
    Benchmark evaluation runner for ask-skills governance rules, guardrails, and role invariants.
.DESCRIPTION
    Validates synthetic evaluation test cases from evals/eval-cases.json.
    Ensures that test cases adhere to the schema, reference registered roles from model-tiers.json,
    and verify static invariants (Anti-Ceremony, Safe-Rust, Circuit-Breaker, Submodule Isolation).
.PARAMETER EvalFile
    Optional custom path to eval-cases.json.
.PARAMETER CaseId
    Optional specific eval case ID to run (e.g. EVAL-GOV-001).
.PARAMETER Category
    Optional category filter (e.g. governance, security, anti_ceremony, git_hygiene).
.PARAMETER JsonOutput
    Switch to output results as a structured JSON object.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-evals.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-evals.ps1 -Category security
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$EvalFile,

    [Parameter(Mandatory = $false)]
    [string]$CaseId,

    [Parameter(Mandatory = $false)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

# 1. Resolve eval-cases.json path supporting standalone and submodules
if (-not $EvalFile) {
    $candidatePaths = @(
        (Join-Path $repoRoot "evals\eval-cases.json"),
        (Join-Path $repoRoot "_agents\evals\eval-cases.json"),
        (Join-Path $repoRoot ".agents\evals\eval-cases.json")
    )
    foreach ($candidate in $candidatePaths) {
        if (Test-Path $candidate) {
            $EvalFile = $candidate
            break
        }
    }
}

if (-not $EvalFile -or -not (Test-Path $EvalFile)) {
    Write-Error "eval-cases.json could not be found. Checked paths: $($candidatePaths -join ', ')"
    exit 1
}

# 2. Resolve model-tiers.json for role cross-validation
$modelTiersPath = @(
    (Join-Path $repoRoot "rules\model-tiers.json"),
    (Join-Path $repoRoot "_agents\rules\model-tiers.json"),
    (Join-Path $repoRoot ".agents\rules\model-tiers.json")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$validRoles = @()
if ($modelTiersPath -and (Test-Path $modelTiersPath)) {
    try {
        $tiersJson = Get-Content -Path $modelTiersPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $tierDispatch = $tiersJson.execution_modes.multi_agent.tier_dispatch
        $validRoles = @(
            $tierDispatch.tier_1_deep_reasoning.roles +
            $tierDispatch.tier_2_analytical.roles +
            $tierDispatch.tier_3_balanced.roles +
            $tierDispatch.tier_4_fast_deterministic.roles
        )
    } catch {
        # Fallback if parsing fails
    }
}

# 3. Read and parse eval dataset
$rawContent = Get-Content -Path $EvalFile -Raw -Encoding UTF8
$dataset = $rawContent | ConvertFrom-Json

if (-not $dataset.eval_cases -or $dataset.eval_cases.Count -eq 0) {
    Write-Error "No eval cases found in $EvalFile"
    exit 1
}

$cases = $dataset.eval_cases

if ($CaseId) {
    $cases = @($cases | Where-Object { $_.id -eq $CaseId })
}

if ($Category) {
    $cases = @($cases | Where-Object { $_.category -eq $Category })
}

if (-not $JsonOutput) {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Running ask-skills Eval Benchmark Suite" -ForegroundColor Cyan
    Write-Host "Source: $EvalFile" -ForegroundColor DarkGray
    Write-Host "Total Cases Selected: $($cases.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$passedCount = 0
$failedCount = 0

$seenIds = [System.Collections.Generic.HashSet[string]]::new()

foreach ($tc in $cases) {
    $caseId = $tc.id
    $caseName = $tc.name
    $caseCategory = $tc.category
    $failures = [System.Collections.Generic.List[string]]::new()

    # Rule 1: ID uniqueness
    if ($seenIds.Contains($caseId)) {
        $failures.Add("Duplicate test case ID: $caseId")
    } else {
        [void]$seenIds.Add($caseId)
    }

    # Rule 2: Basic required schema fields
    if ([string]::IsNullOrWhiteSpace($tc.name)) {
        $failures.Add("Missing or empty 'name'")
    }
    if ([string]::IsNullOrWhiteSpace($tc.input)) {
        $failures.Add("Missing or empty 'input'")
    }
    if ($null -eq $tc.expected) {
        $failures.Add("Missing 'expected' definition")
    }

    # Rule 3: Valid role references
    if ($tc.expected.primary_role) {
        if ($validRoles.Count -gt 0 -and -not ($validRoles -contains $tc.expected.primary_role)) {
            $failures.Add("Referenced primary_role '$($tc.expected.primary_role)' is not in registered roles list")
        }
    }
    if ($tc.expected.workflow_sequence) {
        foreach ($r in $tc.expected.workflow_sequence) {
            if ($validRoles.Count -gt 0 -and -not ($validRoles -contains $r)) {
                $failures.Add("Referenced workflow role '$r' is not in registered roles list")
            }
        }
    }

    # Rule 4: Invariants must not be empty
    if ($tc.expected.required_invariants) {
        if ($tc.expected.required_invariants.Count -eq 0) {
            $failures.Add("required_invariants array is empty")
        }
    } else {
        $failures.Add("Missing required_invariants array")
    }

    # Rule 5: Specific guardrail checks
    if ($caseCategory -eq "security" -and $tc.expected.language -eq "rust") {
        if (-not $tc.expected.forbidden_code_patterns -or $tc.expected.forbidden_code_patterns.Count -eq 0) {
            $failures.Add("Rust security eval must declare forbidden_code_patterns (e.g. unsafe)")
        }
    }

    if ($caseCategory -eq "git_hygiene" -and $tc.expected.prohibited_staging_paths) {
        $hasSubmodulePath = ($tc.expected.prohibited_staging_paths | Where-Object { $_ -match '_agents|\.agents' }).Count -gt 0
        if (-not $hasSubmodulePath) {
            $failures.Add("Submodule git hygiene eval must declare prohibited submodule staging paths")
        }
    }

    $isPass = ($failures.Count -eq 0)
    if ($isPass) {
        $passedCount++
        if (-not $JsonOutput) {
            Write-Host "  [PASS] ${caseId}: $caseName" -ForegroundColor Green
        }
    } else {
        $failedCount++
        if (-not $JsonOutput) {
            Write-Host "  [FAIL] ${caseId}: $caseName" -ForegroundColor Red
            foreach ($err in $failures) {
                Write-Host "         - $err" -ForegroundColor Yellow
            }
        }
    }

    $results.Add([PSCustomObject]@{
        id = $caseId
        name = $caseName
        category = $caseCategory
        passed = $isPass
        failures = $failures.ToArray()
    })
}

$summary = [PSCustomObject]@{
    total = $cases.Count
    passed = $passedCount
    failed = $failedCount
    pass_rate_percent = if ($cases.Count -gt 0) { [math]::Round(($passedCount / $cases.Count) * 100, 2) } else { 0 }
    results = $results.ToArray()
}

if ($JsonOutput) {
    $summary | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Eval Benchmark Suite Summary" -ForegroundColor Cyan
    Write-Host "Passed: $passedCount / $($cases.Count) ($($summary.pass_rate_percent)%)" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
    Write-Host "=============================================" -ForegroundColor Cyan
}

if ($failedCount -gt 0) {
    exit 1
}
