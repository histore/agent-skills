#!/usr/bin/env bash
# ==============================================================================
# Lints requirements files, validates unique scoped IDs, and allocates next IDs deterministically.
# ==============================================================================
set -euo pipefail

REQ_PATH="${1:-$(pwd)}"
NEXT_ID=false
SCOPE=""
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --next-id)
      NEXT_ID=true
      ;;
    --scope=*)
      SCOPE="${arg#*=}"
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

if command -v python3 &>/dev/null; then
  python3 -c "
import os, re, json, sys

base_dir = '$REQ_PATH'
files = []
root_req = os.path.join(base_dir, 'REQUIREMENTS.md')
if os.path.isfile(root_req):
    files.append(root_req)

modules_dir = os.path.join(base_dir, 'docs', 'requirements', 'modules')
if os.path.isdir(modules_dir):
    for f in os.listdir(modules_dir):
        if f.endswith('.md'):
            files.append(os.path.join(modules_dir, f))

id_pattern = re.compile(r'REQ-([A-Za-z0-9_]+)-([0-9]{3,})')
found_ids = {}
duplicates = []
scope_max = {}

for f in files:
    rel = os.path.relpath(f, base_dir)
    with open(f, 'r', encoding='utf-8', errors='ignore') as fp:
        for idx, line in enumerate(fp, 1):
            for match in id_pattern.finditer(line):
                full_id = match.group(0).upper()
                sc = match.group(1).upper()
                num = int(match.group(2))

                if full_id in found_ids:
                    duplicates.append({'id': full_id, 'first': found_ids[full_id], 'second': f'{rel}:{idx}'})
                else:
                    found_ids[full_id] = f'{rel}:{idx}'

                scope_max[sc] = max(scope_max.get(sc, 0), num)

next_id = '$NEXT_ID' == 'true'
target_scope = '$SCOPE'.upper()
json_out = '$JSON_OUTPUT' == 'true'

if next_id:
    if not target_scope:
        print('Error: --scope is required with --next-id', file=sys.stderr)
        sys.exit(1)
    nxt = scope_max.get(target_scope, 0) + 1
    new_id = f'REQ-{target_scope}-{nxt:03d}'
    if json_out:
        print(json.dumps({'scope': target_scope, 'next_id': new_id}))
    else:
        print(new_id)
    sys.exit(0)

is_pass = len(duplicates) == 0
if json_out:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'scanned_files': len(files),
        'total_requirements_found': len(found_ids),
        'duplicates_count': len(duplicates),
        'duplicates': duplicates
    }))
else:
    print('=============================================')
    print('Requirements Linter & ID Registry')
    print(f'Files: {len(files)} | Requirements: {len(found_ids)} | Scopes: {len(scope_max)}')
    print('=============================================')
    if is_pass:
        print('Status: PASS (0 duplicate IDs, all requirements scoped)')
    else:
        print(f'Status: FAIL ({len(duplicates)} duplicate IDs detected)')
        for d in duplicates:
            print(f\"  Collision on {d['id']}: first in {d['first']}, second in {d['second']}\")
    print('=============================================')

if not is_pass:
    sys.exit(1)
"
else
  echo "python3 required for requirements linting"
  exit 0
fi
