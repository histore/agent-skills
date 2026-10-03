#!/usr/bin/env bash
# ==============================================================================
# Lints Clean Architecture layer boundaries and Clean Code metrics deterministically.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_PATH="${1:-$(pwd)}"
STAGED_ONLY=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --staged)
      STAGED_ONLY=true
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

RULES_FILE="${REPO_ROOT}/rules/clean-architecture.json"

if command -v python3 &>/dev/null; then
  python3 -c "
import os, re, json, sys

rules_file = '$RULES_FILE'
target_path = os.path.abspath('$TARGET_PATH')
staged_only = '$STAGED_ONLY' == 'true'
json_output = '$JSON_OUTPUT' == 'true'

rules = {}
if os.path.isfile(rules_file):
    try:
        with open(rules_file, 'r', encoding='utf-8') as f:
            rules = json.load(f)
    except Exception:
        pass

max_file_lines = rules.get('metrics', {}).get('max_file_lines', 500)
layer_boundaries = rules.get('layer_boundaries', [])

src_exts = ('.rs', '.cs', '.ts', '.js', '.py', '.go')
files_to_scan = []

if staged_only:
    import subprocess
    res = subprocess.run(['git', '-C', target_path, 'diff', '--name-only', '--cached'], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if line.endswith(src_exts) and os.path.isfile(os.path.join(target_path, line)):
            files_to_scan.append(os.path.join(target_path, line))
else:
    for root, dirs, files in os.walk(target_path):
        if any(ignored in root for ignored in ['.git', 'node_modules', 'target', 'bin', 'obj']):
            continue
        for f in files:
            if f.endswith(src_exts):
                files_to_scan.append(os.path.join(root, f))

violations = []
import_pattern = re.compile(r'^\s*(use\s+|import\s+|using\s+|from\s+)([^;]+)', re.IGNORECASE)

for fp in files_to_scan:
    rel = os.path.relpath(fp, target_path)
    try:
        with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        continue

    if len(lines) > max_file_lines:
        violations.append({
            'type': 'FileSizeLimit',
            'file': rel,
            'line': len(lines),
            'severity': 'Warning',
            'message': f'File exceeds {max_file_lines} lines ({len(lines)} lines)'
        })

    active_rules = [r for r in layer_boundaries if re.search(r.get('path_pattern', ''), rel, re.IGNORECASE)]

    for idx, line in enumerate(lines, 1):
        m = import_pattern.match(line)
        if m and active_rules:
            import_target = m.group(2).lower()
            for r in active_rules:
                for forbidden in r.get('forbidden_imports', []):
                    if re.search(r'\b' + forbidden + r'\b', import_target):
                        violations.append({
                            'type': 'LayerBoundaryViolation',
                            'file': rel,
                            'line': idx,
                            'severity': 'Error',
                            'message': f\"Layer '{r.get('layer')}' illegally imports '{forbidden}': {r.get('message')}\"
                        })

errors = [v for v in violations if v['severity'] == 'Error']
is_pass = len(errors) == 0

if json_output:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'scanned_source_files': len(files_to_scan),
        'violations_count': len(violations),
        'error_count': len(errors),
        'violations': violations
    }))
else:
    print('=============================================')
    print('Deterministic Clean Architecture & Code Linter')
    print(f'Scanned Files: {len(files_to_scan)} | Violations: {len(violations)}')
    print('=============================================')
    if is_pass:
        print('Clean Architecture Status: PASS (0 architectural boundary errors)')
    else:
        print(f'Clean Architecture Status: FAIL ({len(errors)} errors)')
        for v in violations:
            print(f\"  [{v['severity']}: {v['type']}] {v['file']}:{v['line']} - {v['message']}\")
    print('=============================================')

if not is_pass:
    sys.exit(1)
"
else
  echo "python3 required for clean architecture linting"
fi
