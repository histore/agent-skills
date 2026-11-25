#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=""
WORKING_TREE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root|-r) PROJECT_ROOT="$2"; shift 2 ;;
    --project-root=*) PROJECT_ROOT="${1#*=}"; shift ;;
    --working-tree|-w) WORKING_TREE=true; shift ;;
    --json|-j) JSON_OUTPUT=true; shift ;;
    -*) shift ;;
    *) [[ -z "$PROJECT_ROOT" ]] && PROJECT_ROOT="$1"; shift ;;
  esac
done

[[ -z "$PROJECT_ROOT" ]] && PROJECT_ROOT="$(pwd)"

if command -v python3 &>/dev/null; then
  python3 - "$PROJECT_ROOT" "$WORKING_TREE" "$JSON_OUTPUT" << 'EOF'
import json, os, re, subprocess, sys

project_root = os.path.abspath(sys.argv[1])
working_tree = sys.argv[2] == 'true'
json_out = sys.argv[3] == 'true'

files_to_scan = []
if working_tree:
    is_git = subprocess.run(['git', '-C', project_root, 'rev-parse', '--is-inside-work-tree'], capture_output=True, text=True)
    if is_git.stdout.strip() == 'true':
        seen = set()
        for cmd in [
            ['git', '-C', project_root, 'diff', '--name-only', '--cached'],
            ['git', '-C', project_root, 'diff', '--name-only'],
            ['git', '-C', project_root, 'ls-files', '--others', '--exclude-standard']
        ]:
            r = subprocess.run(cmd, capture_output=True, text=True)
            for line in r.stdout.splitlines():
                if line and not re.match(r'^(\.agents|_agents)/', line) and line.endswith('.kt'):
                    fp = os.path.join(project_root, line)
                    if os.path.isfile(fp) and fp not in seen:
                        seen.add(fp)
                        files_to_scan.append(fp)
else:
    ignored = {'.git', '_agents', '.agents', 'build', 'node_modules'}
    for root, dirs, files in os.walk(project_root):
        dirs[:] = [d for d in dirs if d not in ignored]
        for f in files:
            if f.endswith('.kt'):
                files_to_scan.append(os.path.join(root, f))

test_corpus_cache = None
def get_test_corpus():
    global test_corpus_cache
    if test_corpus_cache is not None:
        return test_corpus_cache
    chunks = []
    ignored = {'.git', '_agents', '.agents', 'build', 'node_modules'}
    for root, dirs, files in os.walk(project_root):
        dirs[:] = [d for d in dirs if d not in ignored]
        for f in files:
            if f.endswith('Test.kt'):
                try:
                    with open(os.path.join(root, f), 'r', encoding='utf-8', errors='ignore') as tf:
                        chunks.append(tf.read())
                except Exception:
                    pass
    test_corpus_cache = '\n'.join(chunks)
    return test_corpus_cache

errors, warnings = [], []

for fp in files_to_scan:
    rel = os.path.relpath(fp, project_root).replace('\\', '/')
    if re.search(r'(?i)(^|/)(test|androidTest)/|Test\.kt$', rel):
        continue
    try:
        with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.read().splitlines()
    except Exception:
        continue
    raw = '\n'.join(lines)

    for idx, line in enumerate(lines):
        if re.search(r'(contentResolver\.query\s*\(|\.rawQuery\s*\()', line):
            window = '\n'.join(lines[idx:min(len(lines), idx + 16)])
            if not re.search(r'\.use\s*\{|\.close\s*\(|\bfinally\s*\{', window):
                errors.append({"Rule": "CursorLeak", "File": rel, "Line": idx + 1, "Message": "Cursor query without '.use { ... }' or explicit close()/finally block."})

    if re.search(r'class\s+\w+.*:\s*ContentProvider\s*\(', raw) or rel.endswith('Provider.kt'):
        if re.search(r'override\s+fun\s+(insert|update|delete)\s*\(', raw) and not re.search(r'notifyChange\s*\(', raw):
            errors.append({"Rule": "MissingNotifyChange", "File": rel, "Line": 1, "Message": "ContentProvider implements insert/update/delete without calling notifyChange()."})

    for m in re.finditer(r'addURI\s*\([^,]+,\s*([A-Za-z0-9_."]+)\s*,', raw):
        token = m.group(1).strip('"')
        corpus = get_test_corpus()
        if len(token) >= 3 and corpus and token not in corpus:
            warnings.append({"Rule": "UriContractSync", "File": rel, "Line": 1, "Message": f"UriMatcher entry '{token}' is not referenced in any *Test.kt file."})

    for idx in range(len(lines) - 1):
        if re.match(r'^\s*@Composable\b', lines[idx]):
            if idx > 0 and '@Preview' in lines[idx - 1]:
                continue
            sig = ' '.join(lines[idx:min(len(lines), idx + 7)])
            if re.search(r'@Composable\s+(private|internal)\s+fun\b', sig):
                continue
            m = re.search(r'@Composable\s+(?:public\s+)?fun\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)', sig)
            if m and not re.search(r'\bModifier\b', m.group(2)):
                warnings.append({"Rule": "ComposeModifier", "File": rel, "Line": idx + 2, "Message": f"Public @Composable '{m.group(1)}' should accept a 'modifier: Modifier = Modifier' parameter."})

status = "fail" if errors else "pass"
res = {"status": status, "scanned_files": len(files_to_scan), "errors": errors, "warnings": warnings}
if json_out:
    print(json.dumps(res))
else:
    print(f"Android Contract Linter: {status.upper()} ({len(files_to_scan)} files, {len(errors)} errors, {len(warnings)} warnings)")
    for e in errors: print(f"  [ERROR:{e['Rule']}] {e['File']}:{e['Line']} - {e['Message']}")
    for w in warnings: print(f"  [WARN:{w['Rule']}] {w['File']}:{w['Line']} - {w['Message']}")
sys.exit(1 if errors else 0)
EOF
fi
