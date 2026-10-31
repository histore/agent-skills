#!/usr/bin/env bash
# ==============================================================================
# Lints Clean Architecture layer boundaries and Clean Code metrics deterministically.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_PATH="${1:-$(pwd)}"
STAGED_ONLY=false
WORKING_TREE=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --staged)
      STAGED_ONLY=true
      ;;
    --working-tree)
      WORKING_TREE=true
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

RULES_FILE=""
for candidate in \
  "${REPO_ROOT}/.agent-lint.json" \
  "${REPO_ROOT}/rules/clean-architecture.json" \
  "${REPO_ROOT}/_agents/rules/clean-architecture.json" \
  "${REPO_ROOT}/.agents/rules/clean-architecture.json"; do
  if [[ -f "$candidate" ]]; then
    RULES_FILE="$candidate"
    break
  fi
done

if command -v python3 &>/dev/null; then
  python3 - "$RULES_FILE" "$TARGET_PATH" "$STAGED_ONLY" "$WORKING_TREE" "$JSON_OUTPUT" << 'EOF'
import os, re, json, sys, subprocess

rules_file = sys.argv[1]
target_path = os.path.abspath(sys.argv[2])
staged_only = sys.argv[3] == 'true'
working_tree = sys.argv[4] == 'true'
json_output = sys.argv[5] == 'true'

rules = {}
if rules_file and os.path.isfile(rules_file):
    try:
        with open(rules_file, 'r', encoding='utf-8') as f:
            rules = json.load(f)
    except Exception:
        pass

metrics = rules.get('metrics', {})
max_file_lines = int(metrics.get('max_file_lines', 500))
max_func_lines = int(metrics.get('max_function_lines', 60))
max_nesting = int(metrics.get('max_nesting_depth', 4))
layer_boundaries = rules.get('layer_boundaries', [])

src_exts = ('.rs', '.cs', '.ts', '.js', '.py', '.go')
files_to_scan = []

if staged_only:
    res = subprocess.run(['git', '-C', target_path, 'diff', '--name-only', '--cached'], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if line.endswith(src_exts) and os.path.isfile(os.path.join(target_path, line)):
            files_to_scan.append(os.path.join(target_path, line))
elif working_tree:
    is_git = subprocess.run(['git', '-C', target_path, 'rev-parse', '--is-inside-work-tree'], capture_output=True, text=True)
    if is_git.stdout.strip() == 'true':
        seen = set()
        for cmd in [
            ['git', '-C', target_path, 'diff', '--name-only', '--cached'],
            ['git', '-C', target_path, 'diff', '--name-only'],
            ['git', '-C', target_path, 'ls-files', '--others', '--exclude-standard']
        ]:
            r = subprocess.run(cmd, capture_output=True, text=True)
            for line in r.stdout.splitlines():
                if line and not re.match(r'^(\.agents|_agents)/', line) and line.endswith(src_exts):
                    fp = os.path.join(target_path, line)
                    if os.path.isfile(fp) and fp not in seen:
                        seen.add(fp)
                        files_to_scan.append(fp)
    else:
        for root, dirs, files in os.walk(target_path):
            if any(ignored in root for ignored in ['.git', '_agents', '.agents', 'node_modules', 'target', 'bin', 'obj']):
                continue
            for f in files:
                if f.endswith(src_exts):
                    files_to_scan.append(os.path.join(root, f))
else:
    for root, dirs, files in os.walk(target_path):
        if any(ignored in root for ignored in ['.git', 'node_modules', 'target', 'bin', 'obj']):
            continue
        for f in files:
            if f.endswith(src_exts):
                files_to_scan.append(os.path.join(root, f))

violations = []
import_pattern = re.compile(r'^\s*(use\s+|import\s+|using\s+|from\s+)([^;]+)', re.IGNORECASE)
func_pattern = re.compile(r'^\s*((pub(\([^)]+\))?\s+)?(async\s+)?fn\s+\w+|def\s+\w+|func\s+(\([^)]+\)\s*)?\w+|(public|private|protected|internal)\s+(static\s+|async\s+|virtual\s+|override\s+)*[\w<>[\],\s]+\s+\w+\s*\()')
ctrl_pattern = re.compile(r'^\s*(if|for|while|match|switch)\b')

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
    is_test_file = bool(re.search(r'(test|spec|tests|benches)[\\/._-]', rel, re.IGNORECASE))
    current_func_start = 0

    for idx, line in enumerate(lines, 1):
        if not is_test_file and func_pattern.match(line):
            if current_func_start > 0 and (idx - 1 - current_func_start) > max_func_lines:
                violations.append({
                    'type': 'FunctionSizeLimit',
                    'file': rel,
                    'line': current_func_start,
                    'severity': 'Warning',
                    'message': f'Function starting at line {current_func_start} spans {idx - 1 - current_func_start} lines (exceeds recommended limit of {max_func_lines})'
                })
            current_func_start = idx

        if ctrl_pattern.match(line):
            leading_spaces = len(line) - len(line.lstrip(' '))
            depth = leading_spaces // 4
            if depth > max_nesting:
                violations.append({
                    'type': 'DeepNesting',
                    'file': rel,
                    'line': idx,
                    'severity': 'Warning',
                    'message': f'Control block nesting depth of {depth} exceeds recommended limit of {max_nesting}'
                })

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
                            'message': f"Layer '{r.get('layer')}' illegally imports '{forbidden}': {r.get('message')}"
                        })

errors = [v for v in violations if v['severity'] == 'Error']
warnings = [v for v in violations if v['severity'] == 'Warning']
is_pass = len(errors) == 0

if json_output:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'scanned_source_files': len(files_to_scan),
        'violations_count': len(violations),
        'error_count': len(errors),
        'warning_count': len(warnings),
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
        print(f'Clean Architecture Status: FAIL ({len(errors)} errors, {len(warnings)} warnings)')
        for v in violations:
            print(f"  [{v['severity']}: {v['type']}] {v['file']}:{v['line']} - {v['message']}")
    print('=============================================')

if not is_pass:
    sys.exit(1)
EOF
else
  echo "python3 required for clean architecture linting"
fi
