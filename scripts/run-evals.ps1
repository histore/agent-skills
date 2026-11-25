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

$agentsFile = Join-Path $repoRoot "AGENTS.md"
$agentsContent = if (Test-Path $agentsFile) { Get-Content -Path $agentsFile -Raw -Encoding UTF8 } else { "" }
$copilotInstrFile = Join-Path $repoRoot ".github\copilot-instructions.md"
$copilotContent = if (Test-Path $copilotInstrFile) { Get-Content -Path $copilotInstrFile -Raw -Encoding UTF8 } else { "" }
$controlSkillFile = Join-Path $repoRoot "skills\ask-control\SKILL.md"
$controlContent = if (Test-Path $controlSkillFile) { Get-Content -Path $controlSkillFile -Raw -Encoding UTF8 } else { "" }
$contractSkillFile = Join-Path $repoRoot "skills\ask-contract-specialist\SKILL.md"
$contractContent = if (Test-Path $contractSkillFile) { Get-Content -Path $contractSkillFile -Raw -Encoding UTF8 } else { "" }

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
        $hasSubmodulePath = @($tc.expected.prohibited_staging_paths | Where-Object { $_ -match '_agents|\.agents' }).Count -gt 0
        if (-not $hasSubmodulePath) {
            $failures.Add("Submodule git hygiene eval must declare prohibited submodule staging paths")
        }
    }

    # Rule 6: Verify actual skill, Copilot instruction, and governance files enforce the declared invariants
    foreach ($inv in $tc.expected.required_invariants) {
        switch ($inv) {
            "direct_response" {
                if ($agentsContent -notmatch 'Answer directly' -or $copilotContent -notmatch 'Answer directly') {
                    $failures.Add("Invariant 'direct_response' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
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
                if ($controlContent -notmatch 'Inner-Loop TDD' -or $copilotContent -notmatch 'Inner-Loop TDD') {
                    $failures.Add("Invariant 'inner_loop_tdd' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
                }
            }
            "safe_rust_only" {
                if ($agentsContent -notmatch 'Rust codebases.*unsafe' -or $controlContent -notmatch 'Rust codebases.*unsafe') {
                    $failures.Add("Invariant 'safe_rust_only' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "no_unsafe_blocks" {
                if ($controlContent -notmatch 'unsafe' -or $copilotContent -notmatch 'unsafe') {
                    $failures.Add("Invariant 'no_unsafe_blocks' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
                }
            }
            "scope_to_host_workspace" {
                if ($agentsContent -notmatch 'host repository root' -or $controlContent -notmatch 'host workspace') {
                    $failures.Add("Invariant 'scope_to_host_workspace' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "submodule_boundary_isolation" {
                if ($controlContent -notmatch 'Submodule Isolation Guardrail') {
                    $failures.Add("Invariant 'submodule_boundary_isolation' missing in ask-control/SKILL.md")
                }
            }
            "circuit_breaker_triggered" {
                if ($controlContent -notmatch 'maximum of 3') {
                    $failures.Add("Invariant 'circuit_breaker_triggered' (max 3 iterations) missing in ask-control/SKILL.md")
                }
            }
            "user_escalation_report" {
                if ($agentsContent -notmatch 'before escalating' -or $controlContent -notmatch 'User Escalation') {
                    $failures.Add("Invariant 'user_escalation_report' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "quota_protection_gate" {
                if ($controlContent -notmatch 'Quota Protection User Gate') {
                    $failures.Add("Invariant 'quota_protection_gate' missing in ask-control/SKILL.md")
                }
            }
            "clean_release_tagging" {
                if ($agentsContent -notmatch 'Clean Release Tagging') {
                    $failures.Add("Invariant 'clean_release_tagging' missing in AGENTS.md")
                }
            }
            "fast_gate_consolidated" {
                if ($controlContent -notmatch 'Consolidated Deterministic Fast-Gate') {
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
            "surgical_editing_first" {
                if ($agentsContent -notmatch 'Surgical Edit First' -or $controlContent -notmatch 'Surgical Edit First') {
                    $failures.Add("Invariant 'surgical_editing_first' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "prompt_cache_two_zone" {
                if ($agentsContent -notmatch 'Two-Zone Prompt Cache Architecture' -or $controlContent -notmatch 'Two-Zone Prompt Architecture') {
                    $failures.Add("Invariant 'prompt_cache_two_zone' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "reasoning_budget_clamped" {
                if ($controlContent -notmatch 'Thinking Budget Clamping') {
                    $failures.Add("Invariant 'reasoning_budget_clamped' missing in ask-control/SKILL.md")
                }
            }
            "zero_token_log_compaction" {
                if ($agentsContent -notmatch 'Zero-Token Log Compaction') {
                    $failures.Add("Invariant 'zero_token_log_compaction' missing in AGENTS.md")
                }
            }
            "deferred_format_prepare_commit" {
                $prepScript = Join-Path $repoRoot "scripts\prepare-commit.ps1"
                if (-not (Test-Path $prepScript) -or $agentsContent -notmatch 'prepare-commit' -or $controlContent -notmatch 'prepare-commit') {
                    $failures.Add("Invariant 'deferred_format_prepare_commit' missing in AGENTS.md, ask-control/SKILL.md, or scripts/prepare-commit.ps1")
                }
            }
            "no_premature_tests" {
                if ($agentsContent -notmatch 'No-Premature-Tests Invariant' -or $controlContent -notmatch 'No-Premature-Tests Invariant') {
                    $failures.Add("Invariant 'no_premature_tests' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "single_prepare_commit_on_confirm" {
                if ($agentsContent -notmatch 'without re-running' -or $copilotContent -notmatch 'do \*\*not\*\* re-run' -or $controlContent -notmatch 'without re-running') {
                    $failures.Add("Invariant 'single_prepare_commit_on_confirm' missing in AGENTS.md, .github/copilot-instructions.md, or ask-control/SKILL.md")
                }
            }
            "os_native_line_endings" {
                if ($agentsContent -notmatch 'OS-Native Line Endings Invariant' -or $copilotContent -notmatch 'OS-native line-ending normalization' -or $controlContent -notmatch 'OS-native line-ending normalization') {
                    $failures.Add("Invariant 'os_native_line_endings' missing in AGENTS.md, .github/copilot-instructions.md, or ask-control/SKILL.md")
                }
            }
            "targeted_test_first" {
                if ($agentsContent -notmatch 'Target only affected test' -or $controlContent -notmatch 'targeted Arrange-Act-Assert') {
                    $failures.Add("Invariant 'targeted_test_first' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "red_green_refactor_loop" {
                if ($agentsContent -notmatch 'Inner-Loop TDD' -or $controlContent -notmatch 'Inner-Loop TDD') {
                    $failures.Add("Invariant 'red_green_refactor_loop' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "contract_first" {
                if ($agentsContent -notmatch 'Architecture Contract' -or $controlContent -notmatch 'Architecture Contract') {
                    $failures.Add("Invariant 'contract_first' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "two_stage_quality_gate" {
                if ($agentsContent -notmatch 'Two-Stage Quality Gate' -or $controlContent -notmatch 'Two-Stage Quality Gate') {
                    $failures.Add("Invariant 'two_stage_quality_gate' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "direct_file_edit" {
                if ($agentsContent -notmatch 'Surgical Edit First' -or $copilotContent -notmatch 'Surgical Edit First') {
                    $failures.Add("Invariant 'direct_file_edit' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "zero_test_execution_on_markdown" {
                if ($agentsContent -notmatch 'No test execution for markdown' -or $controlContent -notmatch 'Omit build/test runners for markdown') {
                    $failures.Add("Invariant 'zero_test_execution_on_markdown' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "zero_git_on_read" {
                if ($agentsContent -notmatch 'Zero Git operations.*read-only' -or $copilotContent -notmatch 'Zero Git commands') {
                    $failures.Add("Invariant 'zero_git_on_read' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "zero_reload_core" {
                if ($agentsContent -notmatch 'Zero-Reload Core Invariant' -or $copilotContent -notmatch 'Zero-Reload Invariant') {
                    $failures.Add("Invariant 'zero_reload_core' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "zero_probe_detection" {
                if ($agentsContent -notmatch 'Zero-Probe Environment Detection' -or $controlContent -notmatch 'Zero-Probe Environment Detection') {
                    $failures.Add("Invariant 'zero_probe_detection' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "concept_template_schema" {
                if ($agentsContent -notmatch 'CONCEPT_TEMPLATE\.md' -or $copilotContent -notmatch 'CONCEPT_TEMPLATE\.md' -or $contractContent -notmatch 'CONCEPT_TEMPLATE\.md') {
                    $failures.Add("Invariant 'concept_template_schema' missing in AGENTS.md, .github/copilot-instructions.md, or ask-contract-specialist/SKILL.md")
                }
            }
            "zero_test_on_concept" {
                if ($agentsContent -notmatch 'Zero test or formatter execution during concept drafting' -or $controlContent -notmatch 'Zero test or formatter execution during concept drafting' -or $contractContent -notmatch 'Zero-Test Concept Guardrail') {
                    $failures.Add("Invariant 'zero_test_on_concept' missing in AGENTS.md, ask-control/SKILL.md, or ask-contract-specialist/SKILL.md")
                }
            }
            "four_step_analysis" {
                if ($agentsContent -notmatch 'Four-Step Codebase Analysis Protocol' -or $controlContent -notmatch '4-Step Analysis Protocol') {
                    $failures.Add("Invariant 'four_step_analysis' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "code_outline_before_read" {
                if ($agentsContent -notmatch 'get-code-outline' -or $controlContent -notmatch 'get-code-outline') {
                    $failures.Add("Invariant 'code_outline_before_read' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "mcp_local_first" {
                if ($agentsContent -notmatch 'MCP & External Tool Governance \(Local-First Priority\)' -or $copilotContent -notmatch 'MCP & External Tool Governance \(Local-First Priority\)') {
                    $failures.Add("Invariant 'mcp_local_first' missing in AGENTS.md or .github/copilot-instructions.md")
                }
            }
            "ac_traceability_gate" {
                $fgPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $fgSh = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.sh") -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($fgPs1 -notmatch 'ACTraceability' -or $fgSh -notmatch 'ACTraceability') {
                    $failures.Add("Invariant 'ac_traceability_gate' missing in run-fast-gate.ps1 or run-fast-gate.sh")
                }
            }
            "diff_size_warning" {
                $fgPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $fgSh = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.sh") -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($fgPs1 -notmatch '\[DiffSize\]' -or $fgSh -notmatch '\[DiffSize\]') {
                    $failures.Add("Invariant 'diff_size_warning' missing in run-fast-gate.ps1 or run-fast-gate.sh")
                }
            }
            "zero_trust_diff_report" {
                if ($controlContent -notmatch 'Zero-Trust Diff-Report') {
                    $failures.Add("Invariant 'zero_trust_diff_report' missing in ask-control/SKILL.md")
                }
            }
            "progressive_disclosure_ac_scoped" {
                if ($agentsContent -notmatch 'directly modified by the active `AC-\*`' -or $controlContent -notmatch 'directly modified by the active `AC-\*`') {
                    $failures.Add("Invariant 'progressive_disclosure_ac_scoped' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "situative_agent_state_scratch" {
                if ($agentsContent -notmatch 'scratch/temp directory' -or $controlContent -notmatch 'scratch/temp directory') {
                    $failures.Add("Invariant 'situative_agent_state_scratch' missing in AGENTS.md or ask-control/SKILL.md")
                }
            }
            "android_agp_detection" {
                $dtPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -Raw -Encoding UTF8
                $dtSh = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.sh") -Raw -Encoding UTF8
                if ($dtPs1 -notmatch 'android-gradle' -or $dtSh -notmatch 'android-gradle') {
                    $failures.Add("Invariant 'android_agp_detection' missing in detect-tech-stack.ps1 or detect-tech-stack.sh")
                }
            }
            "kotlin_clean_architecture" {
                $laPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -Raw -Encoding UTF8
                $laSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-clean-architecture.sh") -Raw -Encoding UTF8
                if ($laPs1 -notmatch '\.kt' -or $laSh -notmatch '\.kt') {
                    $failures.Add("Invariant 'kotlin_clean_architecture' missing .kt support in lint-clean-architecture")
                }
            }
            "kotlin_code_outline" {
                $coPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\get-code-outline.ps1") -Raw -Encoding UTF8
                $coSh = Get-Content -Path (Join-Path $repoRoot "scripts\get-code-outline.sh") -Raw -Encoding UTF8
                if ($coPs1 -notmatch '\.kt' -or $coSh -notmatch '\.kt') {
                    $failures.Add("Invariant 'kotlin_code_outline' missing .kt support in get-code-outline")
                }
            }
            "android_cursor_leak_guard" {
                $acPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-android-contracts.ps1") -Raw -Encoding UTF8
                $acSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-android-contracts.sh") -Raw -Encoding UTF8
                if ($acPs1 -notmatch 'CursorLeak' -or $acSh -notmatch 'CursorLeak') {
                    $failures.Add("Invariant 'android_cursor_leak_guard' missing in lint-android-contracts")
                }
            }
            "content_provider_notify_change" {
                $acPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-android-contracts.ps1") -Raw -Encoding UTF8
                $acSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-android-contracts.sh") -Raw -Encoding UTF8
                if ($acPs1 -notmatch 'MissingNotifyChange' -or $acSh -notmatch 'MissingNotifyChange') {
                    $failures.Add("Invariant 'content_provider_notify_change' missing in lint-android-contracts")
                }
            }
            "cpp_cmake_toolchain_detection" {
                $dtPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -Raw -Encoding UTF8
                $dtSh = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.sh") -Raw -Encoding UTF8
                if ($dtPs1 -notmatch 'cmake-mingw' -or $dtSh -notmatch 'cmake-mingw') {
                    $failures.Add("Invariant 'cpp_cmake_toolchain_detection' missing in detect-tech-stack")
                }
            }
            "cpp_qml_clean_architecture" {
                $laPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -Raw -Encoding UTF8
                $laSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-clean-architecture.sh") -Raw -Encoding UTF8
                if ($laPs1 -notmatch '\.qml' -or $laSh -notmatch '\.qml') {
                    $failures.Add("Invariant 'cpp_qml_clean_architecture' missing .qml/.cpp support in lint-clean-architecture")
                }
            }
            "cpp_qml_code_outline" {
                $coPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\get-code-outline.ps1") -Raw -Encoding UTF8
                $coSh = Get-Content -Path (Join-Path $repoRoot "scripts\get-code-outline.sh") -Raw -Encoding UTF8
                if ($coPs1 -notmatch '\.qml' -or $coSh -notmatch '\.qml') {
                    $failures.Add("Invariant 'cpp_qml_code_outline' missing .qml/.cpp support in get-code-outline")
                }
            }
            "qt_meta_object_guard" {
                $cqPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.ps1") -Raw -Encoding UTF8
                $cqSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.sh") -Raw -Encoding UTF8
                if ($cqPs1 -notmatch 'MissingQObjectMacro' -or $cqSh -notmatch 'MissingQObjectMacro') {
                    $failures.Add("Invariant 'qt_meta_object_guard' missing in lint-cpp-qt-contracts")
                }
            }
            "qml_qt6_connections_guard" {
                $cqPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.ps1") -Raw -Encoding UTF8
                $cqSh = Get-Content -Path (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.sh") -Raw -Encoding UTF8
                if ($cqPs1 -notmatch 'Qt6ConnectionsSyntax' -or $cqSh -notmatch 'Qt6ConnectionsSyntax') {
                    $failures.Add("Invariant 'qml_qt6_connections_guard' missing in lint-cpp-qt-contracts")
                }
            }
            "toolchain_gap_detection" {
                $dtPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -Raw -Encoding UTF8
                $dtSh = Get-Content -Path (Join-Path $repoRoot "scripts\detect-tech-stack.sh") -Raw -Encoding UTF8
                $fgPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -Raw -Encoding UTF8
                $fgSh = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.sh") -Raw -Encoding UTF8
                if ($dtPs1 -notmatch 'support_level' -or $dtSh -notmatch 'support_level' -or $fgPs1 -notmatch '\[ToolchainGap\]' -or $fgSh -notmatch '\[ToolchainGap\]') {
                    $failures.Add("Invariant 'toolchain_gap_detection' missing in detect-tech-stack or run-fast-gate")
                }
            }
            "toolchain_gap_reactive_rule" {
                $copContent = Get-Content -Path (Join-Path $repoRoot ".github\copilot-instructions.md") -Raw -Encoding UTF8
                if ($controlContent -notmatch '\[ToolchainGap\]' -or $copContent -notmatch '\[ToolchainGap\]') {
                    $failures.Add("Invariant 'toolchain_gap_reactive_rule' missing in ask-control/SKILL.md or copilot-instructions.md")
                }
            }
            default {
                $failures.Add("Unhandled required_invariant '$inv' in eval case '$caseId' (must be explicitly asserted in run-evals.ps1)")
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
