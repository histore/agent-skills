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
target_exts = ('.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hxx', '.qml')

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
                if line and not re.match(r'^(\.agents|_agents)/', line) and line.lower().endswith(target_exts):
                    fp = os.path.join(project_root, line)
                    if os.path.isfile(fp) and fp not in seen:
                        seen.add(fp)
                        files_to_scan.append(fp)
else:
    ignored = {'.git', '_agents', '.agents', 'build', 'out', 'node_modules'}
    for root, dirs, files in os.walk(project_root):
        dirs[:] = [d for d in dirs if d not in ignored and not d.startswith('cmake-build-')]
        for f in files:
            if f.lower().endswith(target_exts):
                files_to_scan.append(os.path.join(root, f))

errors, warnings = [], []

for fp in files_to_scan:
    rel = os.path.relpath(fp, project_root).replace('\\', '/')
    if re.search(r'(?i)(^|/)(test|tests)/|tst_|_test\.|Test\.(cpp|cc|cxx|qml)$', rel):
        continue
    try:
        with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.read().splitlines()
    except Exception:
        continue
    raw = '\n'.join(lines)
    ext = os.path.splitext(fp)[1].lower()

    if ext == '.qml':
        if re.search(r'Connections\s*\{', raw):
            for idx, line in enumerate(lines):
                if re.search(r'Connections\s*\{', line):
                    for k in range(idx + 1, min(len(lines), idx + 16)):
                        if re.match(r'^\s*\}\s*$', lines[k]):
                            break
                        if re.match(r'^\s*on[A-Z]\w*\s*:', lines[k]) and not re.match(r'^\s*function\s+', lines[k]):
                            errors.append({"Rule": "Qt6ConnectionsSyntax", "File": rel, "Line": k + 1, "Message": "QML Connections uses deprecated 'onSignal:' syntax; use 'function onSignal(...)' for Qt 6 compatibility."})
        continue

    if re.search(r'class\s+\w+\s*:\s*public\s+(QObject|QWidget|QQuickItem|QAbstractItemModel|QAbstractListModel)\b', raw):
        if not re.search(r'\bQ_OBJECT\b', raw):
            errors.append({"Rule": "MissingQObjectMacro", "File": rel, "Line": 1, "Message": "QObject-derived class is missing the Q_OBJECT macro."})

    for idx, line in enumerate(lines):
        m = re.match(r'^\s*Q_PROPERTY\s*\(([^)]+)\)', line)
        if m:
            body = m.group(1)
            if not re.search(r'\bCONSTANT\b', body) and not re.search(r'\bNOTIFY\b', body):
                errors.append({"Rule": "MissingNotifySignal", "File": rel, "Line": idx + 1, "Message": "Non-CONSTANT Q_PROPERTY is missing a NOTIFY signal for QML binding updates."})

        if re.search(r'\bconnect\s*\(', line) and re.search(r'\b(SIGNAL|SLOT)\s*\(', line):
            errors.append({"Rule": "LegacySignalSlot", "File": rel, "Line": idx + 1, "Message": "Use compile-time pointer-to-member connect(&Sender::sig, ...) instead of legacy SIGNAL()/SLOT() macros."})

        if re.search(r'=\s*new\s+[A-Z]\w*', line) and not re.search(r'\b(make_unique|make_shared|unique_ptr|shared_ptr|QPointer)\b', line) and not re.search(r'\bnew\s+[A-Z]\w*\s*\([^)]*\bthis\b', line):
            warnings.append({"Rule": "RawOwningNew", "File": rel, "Line": idx + 1, "Message": "Raw 'new' allocation detected; prefer std::make_unique/make_shared or parented QObject(..., this)."})

status = "fail" if errors else "pass"
res = {"status": status, "scanned_files": len(files_to_scan), "errors": errors, "warnings": warnings}
if json_out:
    print(json.dumps(res))
else:
    print(f"C++/Qt/QML Contract Linter: {status.upper()} ({len(files_to_scan)} files, {len(errors)} errors, {len(warnings)} warnings)")
    for e in errors: print(f"  [ERROR:{e['Rule']}] {e['File']}:{e['Line']} - {e['Message']}")
    for w in warnings: print(f"  [WARN:{w['Rule']}] {w['File']}:{w['Line']} - {w['Message']}")
sys.exit(1 if errors else 0)
EOF
fi
