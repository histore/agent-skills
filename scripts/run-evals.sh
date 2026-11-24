#!/usr/bin/env bash
# ==============================================================================
# Benchmark evaluation runner for ask-skills governance rules, guardrails, and role invariants.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EVAL_FILE=""
CATEGORY=""
CASE_ID=""
TRANSCRIPT_PATH=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --eval-file|-f)
      EVAL_FILE="$2"
      shift 2
      ;;
    --category|-c)
      CATEGORY="$2"
      shift 2
      ;;
    --case-id|--case|-i)
      CASE_ID="$2"
      shift 2
      ;;
    --transcript|-t)
      TRANSCRIPT_PATH="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# 1. Resolve eval-cases.json path
if [[ -z "$EVAL_FILE" ]]; then
  for candidate in \
    "${REPO_ROOT}/evals/eval-cases.json" \
    "${REPO_ROOT}/_agents/evals/eval-cases.json" \
    "${REPO_ROOT}/.agents/evals/eval-cases.json"; do
    if [[ -f "$candidate" ]]; then
      EVAL_FILE="$candidate"
      break
    fi
  done
fi

if [[ -z "$EVAL_FILE" || ! -f "$EVAL_FILE" ]]; then
  echo "Error: evals/eval-cases.json not found." >&2
  exit 1
fi

# 2. Check JSON validity and execute schema + skill invariant checks using python3
if command -v python3 &>/dev/null; then
  python3 - "$REPO_ROOT" "$EVAL_FILE" "$CATEGORY" "$CASE_ID" "$TRANSCRIPT_PATH" "$JSON_OUTPUT" << 'EOF'
import os, re, json, sys

repo_root, eval_file, category, case_id, transcript_path, json_out_str = sys.argv[1:7]
json_output = json_out_str == 'true'

with open(eval_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

valid_roles = set()
for cand in [
    os.path.join(repo_root, 'rules', 'model-tiers.json'),
    os.path.join(repo_root, '_agents', 'rules', 'model-tiers.json'),
    os.path.join(repo_root, '.agents', 'rules', 'model-tiers.json')
]:
    if os.path.isfile(cand):
        try:
            with open(cand, 'r', encoding='utf-8') as tf:
                tiers = json.load(tf)
            td = tiers.get('execution_modes', {}).get('multi_agent', {}).get('tier_dispatch', {})
            for tier_obj in td.values():
                valid_roles.update(tier_obj.get('roles', []))
            break
        except Exception:
            pass

agents_file = os.path.join(repo_root, 'AGENTS.md')
agents_content = open(agents_file, 'r', encoding='utf-8', errors='ignore').read() if os.path.isfile(agents_file) else ''
copilot_file = os.path.join(repo_root, '.github', 'copilot-instructions.md')
copilot_content = open(copilot_file, 'r', encoding='utf-8', errors='ignore').read() if os.path.isfile(copilot_file) else ''

def read_skill(skill_name):
    for root_rel in ('skills', '_agents/skills', '.agents/skills'):
        p = os.path.join(repo_root, root_rel, skill_name, 'SKILL.md')
        if os.path.isfile(p):
            return open(p, 'r', encoding='utf-8', errors='ignore').read()
    return ''

cases = data.get('eval_cases', [])
if case_id:
    cases = [c for c in cases if c.get('id') == case_id]
if category:
    cases = [c for c in cases if c.get('category') == category]

if not json_output:
    print('=============================================')
    print('Running ask-skills Eval Benchmark Suite')
    print(f'Source: {eval_file}')
    print(f'Total Cases Selected: {len(cases)}')
    print('=============================================')

passed = 0
failed = 0
results = []
seen_ids = set()

for c in cases:
    cid = c.get('id', '')
    name = c.get('name', '')
    cat = c.get('category', '')
    exp = c.get('expected', {})
    failures = []

    if cid in seen_ids:
        failures.append(f'Duplicate ID: {cid}')
    seen_ids.add(cid)

    if not name:
        failures.append('Missing name')
    if not c.get('input'):
        failures.append('Missing input')
    if not exp:
        failures.append('Missing expected')

    prim_role = exp.get('primary_role')
    if prim_role and valid_roles and prim_role not in valid_roles:
        failures.append(f"Referenced primary_role '{prim_role}' is not in registered roles list")
    for wf_role in exp.get('workflow_sequence', []):
        if valid_roles and wf_role not in valid_roles:
            failures.append(f"Referenced workflow role '{wf_role}' is not in registered roles list")

    invariants = exp.get('required_invariants', [])
    if not invariants:
        failures.append('Empty or missing required_invariants')

    if cat == 'security' and exp.get('language') == 'rust':
        if not exp.get('forbidden_code_patterns'):
            failures.append('Rust security eval must declare forbidden_code_patterns')

    if cat == 'git_hygiene' and exp.get('prohibited_staging_paths'):
        if not any(re.search(r'_agents|\.agents', p) for p in exp.get('prohibited_staging_paths', [])):
            failures.append('Submodule git hygiene eval must declare prohibited submodule staging paths')

    control_content = read_skill('ask-control')
    contract_content = read_skill('ask-contract-specialist')

    for inv in invariants:
        if inv == 'direct_response':
            if 'Answer directly' not in agents_content or 'Answer directly' not in copilot_content:
                failures.append("Invariant 'direct_response' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'zero_git_operations':
            if 'Zero Git operations' not in agents_content or 'Zero Git commands' not in copilot_content:
                failures.append("Invariant 'zero_git_operations' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'zero_test_execution':
            if 'zero test execution' not in agents_content or 'zero test execution' not in copilot_content:
                failures.append("Invariant 'zero_test_execution' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'inner_loop_tdd':
            if 'Inner-Loop TDD' not in control_content or 'Inner-Loop TDD' not in copilot_content:
                failures.append("Invariant 'inner_loop_tdd' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
        elif inv == 'safe_rust_only':
            if not re.search(r'Rust codebases.*unsafe', agents_content) or not re.search(r'Rust codebases.*unsafe', control_content):
                failures.append("Invariant 'safe_rust_only' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'no_unsafe_blocks':
            if 'unsafe' not in control_content or 'unsafe' not in copilot_content:
                failures.append("Invariant 'no_unsafe_blocks' missing in ask-control/SKILL.md or .github/copilot-instructions.md")
        elif inv == 'scope_to_host_workspace':
            if 'host repository root' not in agents_content or 'host workspace' not in control_content:
                failures.append("Invariant 'scope_to_host_workspace' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'submodule_boundary_isolation':
            if 'Submodule Isolation Guardrail' not in control_content:
                failures.append("Invariant 'submodule_boundary_isolation' missing in ask-control/SKILL.md")
        elif inv == 'circuit_breaker_triggered':
            if 'maximum of 3' not in control_content:
                failures.append("Invariant 'circuit_breaker_triggered' (max 3 iterations) missing in ask-control/SKILL.md")
        elif inv == 'user_escalation_report':
            if 'before escalating' not in agents_content or 'User Escalation' not in control_content:
                failures.append("Invariant 'user_escalation_report' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'quota_protection_gate':
            if 'Quota Protection User Gate' not in control_content:
                failures.append("Invariant 'quota_protection_gate' missing in ask-control/SKILL.md")
        elif inv == 'fast_gate_consolidated':
            if 'Consolidated Deterministic Fast-Gate' not in control_content:
                failures.append("Invariant 'fast_gate_consolidated' missing in ask-control/SKILL.md")
        elif inv == 'copilot_uses_dot_agents':
            if './.agents/scripts/' not in copilot_content or '.agents/skills/' not in copilot_content:
                failures.append("Invariant 'copilot_uses_dot_agents' violated in .github/copilot-instructions.md")
        elif inv == 'agy_uses_underscore_agents':
            if './_agents/' not in agents_content or '~/_agents/' not in agents_content:
                failures.append("Invariant 'agy_uses_underscore_agents' violated in AGENTS.md")
        elif inv == 'surgical_editing_first':
            if 'Surgical Edit First' not in agents_content or 'Surgical Edit First' not in control_content:
                failures.append("Invariant 'surgical_editing_first' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'prompt_cache_two_zone':
            if 'Two-Zone Prompt Cache Architecture' not in agents_content or 'Two-Zone Prompt Architecture' not in control_content:
                failures.append("Invariant 'prompt_cache_two_zone' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'reasoning_budget_clamped':
            if 'Thinking Budget Clamping' not in control_content:
                failures.append("Invariant 'reasoning_budget_clamped' missing in ask-control/SKILL.md")
        elif inv == 'zero_token_log_compaction':
            if 'Zero-Token Log Compaction' not in agents_content:
                failures.append("Invariant 'zero_token_log_compaction' missing in AGENTS.md")
        elif inv == 'deferred_format_prepare_commit':
            prep_ok = os.path.isfile(os.path.join(repo_root, 'scripts', 'prepare-commit.sh'))
            if not prep_ok or 'prepare-commit' not in agents_content or 'prepare-commit' not in control_content:
                failures.append("Invariant 'deferred_format_prepare_commit' missing in AGENTS.md, ask-control/SKILL.md, or scripts/prepare-commit.sh")
        elif inv == 'no_premature_tests':
            if 'No-Premature-Tests Invariant' not in agents_content or 'No-Premature-Tests Invariant' not in control_content:
                failures.append("Invariant 'no_premature_tests' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'single_prepare_commit_on_confirm':
            if 'without re-running' not in agents_content or 'do **not** re-run' not in copilot_content or 'without re-running' not in control_content:
                failures.append("Invariant 'single_prepare_commit_on_confirm' missing in AGENTS.md, .github/copilot-instructions.md, or ask-control/SKILL.md")
        elif inv == 'os_native_line_endings':
            if 'OS-Native Line Endings Invariant' not in agents_content or 'OS-native line-ending normalization' not in copilot_content or 'OS-native line-ending normalization' not in control_content:
                failures.append("Invariant 'os_native_line_endings' missing in AGENTS.md, .github/copilot-instructions.md, or ask-control/SKILL.md")
        elif inv == 'clean_release_tagging':
            if 'Clean Release Tagging' not in agents_content:
                failures.append("Invariant 'clean_release_tagging' missing in AGENTS.md")
        elif inv == 'targeted_test_first':
            if 'Target only affected test' not in agents_content or 'targeted Arrange-Act-Assert' not in control_content:
                failures.append("Invariant 'targeted_test_first' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'red_green_refactor_loop':
            if 'Inner-Loop TDD' not in agents_content or 'Inner-Loop TDD' not in control_content:
                failures.append("Invariant 'red_green_refactor_loop' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'contract_first':
            if 'Architecture Contract' not in agents_content or 'Architecture Contract' not in control_content:
                failures.append("Invariant 'contract_first' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'two_stage_quality_gate':
            if 'Two-Stage Quality Gate' not in agents_content or 'Two-Stage Quality Gate' not in control_content:
                failures.append("Invariant 'two_stage_quality_gate' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'direct_file_edit':
            if 'Surgical Edit First' not in agents_content or 'Surgical Edit First' not in copilot_content:
                failures.append("Invariant 'direct_file_edit' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'zero_test_execution_on_markdown':
            if 'No test execution for markdown' not in agents_content or 'Omit build/test runners for markdown' not in control_content:
                failures.append("Invariant 'zero_test_execution_on_markdown' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'zero_git_on_read':
            if not re.search(r'Zero Git operations.*read-only', agents_content) or 'Zero Git commands' not in copilot_content:
                failures.append("Invariant 'zero_git_on_read' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'zero_reload_core':
            if 'Zero-Reload Core Invariant' not in agents_content or 'Zero-Reload Invariant' not in copilot_content:
                failures.append("Invariant 'zero_reload_core' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'zero_probe_detection':
            if 'Zero-Probe Environment Detection' not in agents_content or 'Zero-Probe Environment Detection' not in control_content:
                failures.append("Invariant 'zero_probe_detection' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'concept_template_schema':
            if 'CONCEPT_TEMPLATE.md' not in agents_content or 'CONCEPT_TEMPLATE.md' not in copilot_content or 'CONCEPT_TEMPLATE.md' not in contract_content:
                failures.append("Invariant 'concept_template_schema' missing in AGENTS.md, .github/copilot-instructions.md, or ask-contract-specialist/SKILL.md")
        elif inv == 'zero_test_on_concept':
            if 'Zero test or formatter execution during concept drafting' not in agents_content or 'Zero test or formatter execution during concept drafting' not in control_content or 'Zero-Test Concept Guardrail' not in contract_content:
                failures.append("Invariant 'zero_test_on_concept' missing in AGENTS.md, ask-control/SKILL.md, or ask-contract-specialist/SKILL.md")
        elif inv == 'four_step_analysis':
            if 'Four-Step Codebase Analysis Protocol' not in agents_content or '4-Step Analysis Protocol' not in control_content:
                failures.append("Invariant 'four_step_analysis' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'code_outline_before_read':
            if 'get-code-outline' not in agents_content or 'get-code-outline' not in control_content:
                failures.append("Invariant 'code_outline_before_read' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'mcp_local_first':
            if 'MCP & External Tool Governance (Local-First Priority)' not in agents_content or 'MCP & External Tool Governance (Local-First Priority)' not in copilot_content:
                failures.append("Invariant 'mcp_local_first' missing in AGENTS.md or .github/copilot-instructions.md")
        elif inv == 'ac_traceability_gate':
            fg_ps1 = read_file(os.path.join(repo_root, 'scripts', 'run-fast-gate.ps1'))
            fg_sh = read_file(os.path.join(repo_root, 'scripts', 'run-fast-gate.sh'))
            if 'ACTraceability' not in fg_ps1 or 'ACTraceability' not in fg_sh:
                failures.append("Invariant 'ac_traceability_gate' missing in run-fast-gate.ps1 or run-fast-gate.sh")
        elif inv == 'diff_size_warning':
            fg_ps1 = read_file(os.path.join(repo_root, 'scripts', 'run-fast-gate.ps1'))
            fg_sh = read_file(os.path.join(repo_root, 'scripts', 'run-fast-gate.sh'))
            if '[DiffSize]' not in fg_ps1 or '[DiffSize]' not in fg_sh:
                failures.append("Invariant 'diff_size_warning' missing in run-fast-gate.ps1 or run-fast-gate.sh")
        elif inv == 'zero_trust_diff_report':
            if 'Zero-Trust Diff-Report' not in control_content:
                failures.append("Invariant 'zero_trust_diff_report' missing in ask-control/SKILL.md")
        elif inv == 'progressive_disclosure_ac_scoped':
            if 'directly modified by the active `AC-*`' not in agents_content or 'directly modified by the active `AC-*`' not in control_content:
                failures.append("Invariant 'progressive_disclosure_ac_scoped' missing in AGENTS.md or ask-control/SKILL.md")
        elif inv == 'situative_agent_state_scratch':
            if 'scratch/temp directory' not in agents_content or 'scratch/temp directory' not in control_content:
                failures.append("Invariant 'situative_agent_state_scratch' missing in AGENTS.md or ask-control/SKILL.md")
        else:
            failures.append(f"Unhandled required_invariant '{inv}' in eval case '{cid}' (must be explicitly asserted in run-evals.sh)")

    if transcript_path:
        if not os.path.isfile(transcript_path):
            failures.append(f'Transcript file not found: {transcript_path}')
        else:
            cmds, snippets = [], []
            with open(transcript_path, 'r', encoding='utf-8', errors='ignore') as tf:
                for line in tf:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        step = json.loads(line)
                        if step.get('case_id') and step.get('case_id') != cid:
                            continue
                        if step.get('command'):
                            cmds.append(str(step['command']))
                        for call in step.get('tool_calls', []):
                            args = call.get('arguments') or call.get('args') or {}
                            if args.get('CommandLine'):
                                cmds.append(str(args['CommandLine']))
                            if args.get('command'):
                                cmds.append(str(args['command']))
                            if args.get('Content'):
                                snippets.append(str(args['Content']))
                            if args.get('Replacement'):
                                snippets.append(str(args['Replacement']))
                    except Exception:
                        pass
            for prohib in exp.get('prohibited_actions', []):
                for cmd in cmds:
                    if prohib in cmd:
                        failures.append(f"Behavioral trace executed prohibited action '{prohib}' in command: {cmd}")
            for pat in exp.get('forbidden_code_patterns', []):
                for snip in snippets:
                    if re.search(pat, snip):
                        failures.append(f"Behavioral trace wrote forbidden code pattern '{pat}'")
            if exp.get('max_iterations') and len(cmds) > int(exp['max_iterations']):
                failures.append(f"Behavioral trace exceeded max_iterations ({len(cmds)} > {exp['max_iterations']})")

    is_pass = len(failures) == 0
    if is_pass:
        passed += 1
        if not json_output:
            print(f'  [PASS] {cid}: {name}')
    else:
        failed += 1
        if not json_output:
            print(f'  [FAIL] {cid}: {name}')
            for err in failures:
                print(f'         - {err}')

    results.append({'id': cid, 'name': name, 'category': cat, 'passed': is_pass, 'failures': failures})

if json_output:
    summary = {
        'total': len(cases),
        'passed': passed,
        'failed': failed,
        'pass_rate_percent': round((passed / len(cases) * 100), 2) if cases else 0,
        'results': results
    }
    print(json.dumps(summary, indent=2))
else:
    print('\n=============================================')
    print('Eval Benchmark Suite Summary')
    rate = round((passed / len(cases) * 100), 2) if cases else 0
    print(f'Passed: {passed} / {len(cases)} ({rate}%)')
    print('=============================================')

if failed > 0:
    sys.exit(1)
EOF
else
  # Minimal fallback using grep/test
  echo "python3 not found; validated file existence: $EVAL_FILE"
fi
