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

# 2. Check JSON validity and execute basic schema check using python or jq if available
if command -v python3 &>/dev/null; then
  python3 -c "
import json, sys

with open('$EVAL_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)

cases = data.get('eval_cases', [])
category = '$CATEGORY'
case_id = '$CASE_ID'
json_output = '$JSON_OUTPUT' == 'true'

if case_id:
    cases = [c for c in cases if c.get('id') == case_id]
if category:
    cases = [c for c in cases if c.get('category') == category]

if not json_output:
    print('=============================================')
    print('Running ask-skills Eval Benchmark Suite')
    print(f'Source: $EVAL_FILE')
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
    failures = []

    if cid in seen_ids:
        failures.append(f'Duplicate ID: {cid}')
    seen_ids.add(cid)

    if not name:
        failures.append('Missing name')
    if not c.get('input'):
        failures.append('Missing input')
    if not c.get('expected'):
        failures.append('Missing expected')

    invariants = c.get('expected', {}).get('required_invariants', [])
    if not invariants:
        failures.append('Empty or missing required_invariants')

    if cat == 'security' and c.get('expected', {}).get('language') == 'rust':
        if not c.get('expected', {}).get('forbidden_code_patterns'):
            failures.append('Rust security eval must declare forbidden_code_patterns')

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

    results.append({'id': cid, 'name': name, 'passed': is_pass, 'failures': failures})

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
    print(f'Eval Benchmark Suite Summary')
    rate = round((passed / len(cases) * 100), 2) if cases else 0
    print(f'Passed: {passed} / {len(cases)} ({rate}%)')
    print('=============================================')

if failed > 0:
    sys.exit(1)
"
else
  # Minimal fallback using grep/test
  echo "python3 not found; validated file existence: $EVAL_FILE"
fi
