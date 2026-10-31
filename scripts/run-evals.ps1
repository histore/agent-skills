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
    [string]$TranscriptPath,

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

    # Rule 6: Verify actual skill, Copilot instruction, and governance files enforce the declared invariants
    $agentsFile = Join-Path $repoRoot "AGENTS.md"
    $agentsContent = if (Test-Path $agentsFile) { Get-Content -Path $agentsFile -Raw -Encoding UTF8 } else { "" }
    $copilotInstrFile = Join-Path $repoRoot ".github\copilot-instructions.md"
    $copilotContent = if (Test-Path $copilotInstrFile) { Get-Content -Path $copilotInstrFile -Raw -Encoding UTF8 } else { "" }
    foreach ($inv in $tc.expected.required_invariants) {
        switch ($inv) {
            "zero_git_operations" {
                if ($agentsContent -notmatch 'Zero Git operations' -or $copilotContent -notmatch 'Zero Git commands') {
                    $failures.Add("Invariant 'zero_git_operations' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "zero_test_execution" {
                if ($agentsContent -notmatch 'zero test execution' -or $copilotContent -notmatch 'zero test execution') {
                    $failures.Add("Invariant 'zero_test_execution' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "inner_loop_tdd" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'Inner-Loop TDD' -or $copilotContent -notmatch 'Inner-Loop TDD') {
                    $failures.Add("Invariant 'inner_loop_tdd' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
                }
            }
            "no_unsafe_blocks" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'unsafe' -or $copilotContent -notmatch 'unsafe') {
                    $failures.Add("Invariant 'no_unsafe_blocks' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
                }
            }
            "submodule_boundary_isolation" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'Submodule Isolation Guardrail') {
                    $failures.Add("Invariant 'submodule_boundary_isolation' missing in ask-control/SKILL.md")
                }
            }
            "circuit_breaker_triggered" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'maximum of 3') {
                    $failures.Add("Invariant 'circuit_breaker_triggered' (max 3 iterations) missing in ask-control/SKILL.md")
                }
            }
            "quota_protection_gate" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'Quota Protection User Gate') {
                    $failures.Add("Invariant 'quota_protection_gate' missing in ask-control/SKILL.md")
                }
            }
            "clean_release_tagging" {
                if ($agentsContent -notmatch 'Clean Release Tagging') {
                    $failures.Add("Invariant 'clean_release_tagging' missing in AGENTS.md")
                }
            }
            "fast_gate_consolidated" {
                $controlSkill = Join-Path $repoRoot "skills\ask-control\SKILL.md"
                if (-not (Test-Path $controlSkill) -or (Get-Content $controlSkill -Raw -Encoding UTF8) -notmatch 'Consolidated Deterministic Fast-Gate') {
                    $failures.Add("Invariant 'fast_gate_consolidated' missing in ask-control/SKILL.md")
                }
            }
            "copilot_uses_dot_agents" {
                if ($copilotContent -notmatch '\./\.agents/scripts/' -or $copilotContent -notmatch '\.agents/skills/') {
                    $failures.Add("Invariant 'copilot_uses_dot_agents' violated in .github/copilot-instructions.md")
                }
            }
            "agy_uses_underscore_agents" {
                if ($agentsContent -notmatch '\./_agents/' -or $agentsContent -notmatch '~/_agents/') {
                    $failures.Add("Invariant 'agy_uses_underscore_agents' violated in AGENTS.md")
                }
            }
        }
    }

    # Rule 7: Optional Behavioral Trajectory Evaluation (-TranscriptPath for AGY JSONL / Copilot CLI traces)
    if ($TranscriptPath) {
        if (-not (Test-Path $TranscriptPath)) {
            $failures.Add("Transcript file not found: $TranscriptPath")
        } else {
            $traceLines = Get-Content -Path $TranscriptPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $executedCommands = [System.Collections.Generic.List[string]]::new()
            $writtenSnippets = [System.Collections.Generic.List[string]]::new()
            foreach ($tl in $traceLines) {
                try {
                    $step = $tl | ConvertFrom-Json
                    if ($step.case_id -and $step.case_id -ne $caseId) { continue }
                    if ($step.command) { $executedCommands.Add([string]$step.command) }
                    if ($step.tool_calls) {
                        foreach ($call in $step.tool_calls) {
                            $argsObj = if ($call.arguments) { $call.arguments } elseif ($call.args) { $call.args } else { $null }
                            if ($argsObj) {
                                if ($argsObj.CommandLine) { $executedCommands.Add([string]$argsObj.CommandLine) }
                                if ($argsObj.command) { $executedCommands.Add([string]$argsObj.command) }
                                if ($argsObj.Content) { $writtenSnippets.Add([string]$argsObj.Content) }
                                if ($argsObj.Replacement) { $writtenSnippets.Add([string]$argsObj.Replacement) }
                            }
                        }
                    }
                } catch {}
            }

            if ($tc.expected.prohibited_actions) {
                foreach ($prohibited in $tc.expected.prohibited_actions) {
                    foreach ($cmd in $executedCommands) {
                        if ($cmd -match [regex]::Escape($prohibited)) {
                            $failures.Add("Behavioral trace executed prohibited action '$prohibited' in command: $cmd")
                        }
                    }
                }
            }

            if ($tc.expected.forbidden_code_patterns) {
                foreach ($pat in $tc.expected.forbidden_code_patterns) {
                    foreach ($snip in $writtenSnippets) {
                        if ($snip -match $pat) {
                            $failures.Add("Behavioral trace wrote forbidden code pattern '$pat'")
                        }
                    }
                }
            }

            if ($tc.expected.max_iterations -and $executedCommands.Count -gt [int]$tc.expected.max_iterations) {
                $failures.Add("Behavioral trace exceeded circuit breaker max_iterations ($($executedCommands.Count) > $($tc.expected.max_iterations))")
            }
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
