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
    --case-id|-i)
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
    p = os.path.join(repo_root, 'skills', skill_name, 'SKILL.md')
    return open(p, 'r', encoding='utf-8', errors='ignore').read() if os.path.isfile(p) else ''

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

    for inv in invariants:
        if inv == 'zero_git_operations' and 'Zero Git operations' not in agents_content:
            failures.append("Invariant 'zero_git_operations' missing in AGENTS.md")
        elif inv == 'zero_test_execution' and 'zero test execution' not in agents_content:
            failures.append("Invariant 'zero_test_execution' missing in AGENTS.md")
        elif inv == 'inner_loop_tdd' and 'Inner-Loop TDD' not in read_skill('ask-control'):
            failures.append("Invariant 'inner_loop_tdd' missing in ask-control/SKILL.md")
        elif inv == 'no_unsafe_blocks' and 'unsafe' not in read_skill('ask-control'):
            failures.append("Invariant 'no_unsafe_blocks' missing in ask-control/SKILL.md")
        elif inv == 'submodule_boundary_isolation' and 'Submodule Isolation Guardrail' not in read_skill('ask-control'):
            failures.append("Invariant 'submodule_boundary_isolation' missing in ask-control/SKILL.md")
        elif inv == 'circuit_breaker_triggered' and 'maximum of 3' not in read_skill('ask-control'):
            failures.append("Invariant 'circuit_breaker_triggered' (max 3 iterations) missing in ask-control/SKILL.md")
        elif inv == 'quota_protection_gate' and 'Quota Protection User Gate' not in read_skill('ask-control'):
            failures.append("Invariant 'quota_protection_gate' missing in ask-control/SKILL.md")
        elif inv == 'fast_gate_consolidated' and 'Consolidated Deterministic Fast-Gate' not in read_skill('ask-control'):
            failures.append("Invariant 'fast_gate_consolidated' missing in ask-control/SKILL.md")
        elif inv == 'copilot_uses_dot_agents' and ('./.agents/scripts/' not in copilot_content or '.agents/skills/' not in copilot_content):
            failures.append("Invariant 'copilot_uses_dot_agents' violated in .github/copilot-instructions.md")
        elif inv == 'agy_uses_underscore_agents' and ('./_agents/' not in agents_content or '~/_agents/' not in agents_content):
            failures.append("Invariant 'agy_uses_underscore_agents' violated in AGENTS.md")

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
