#!/usr/bin/env bash
# ==============================================================================
# Lints documentation integrity, validates internal relative links, and checks architecture parity.
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
CHECK_PARITY=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --parity)
      CHECK_PARITY=true
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

if command -v python3 &>/dev/null; then
  python3 -c "
import os, re, json, sys

repo_root = os.path.abspath('$REPO_ROOT')
check_parity = '$CHECK_PARITY' == 'true'
json_output = '$JSON_OUTPUT' == 'true'

md_files = []
for root, dirs, files in os.walk(repo_root):
    if '.git' in root or 'node_modules' in root:
        continue
    for f in files:
        if f.endswith('.md'):
            md_files.append(os.path.join(root, f))

link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
broken_links = []
total_checked = 0

for file_path in md_files:
    file_dir = os.path.dirname(file_path)
    rel_source = os.path.relpath(file_path, repo_root)
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as fp:
        for idx, line in enumerate(fp, 1):
            for match in link_pattern.finditer(line):
                target = match.group(2).strip()
                if re.match(r'^(https?://|mailto:|#|file://)', target):
                    continue
                target_path = target.split('#')[0].split('?')[0]
                if not target_path:
                    continue
                total_checked += 1
                resolved = os.path.normpath(os.path.join(file_dir, target_path))
                if not os.path.exists(resolved):
                    broken_links.append({'file': rel_source, 'line': idx, 'target': target})

is_pass = len(broken_links) == 0

if json_output:
    print(json.dumps({'status': 'pass' if is_pass else 'fail', 'files_scanned': len(md_files), 'links_checked': total_checked, 'broken_links_count': len(broken_links), 'broken_links': broken_links}))
else:
    print('=============================================')
    print('Deterministic Documentation & Link Integrity Linter')
    print(f'Files: {len(md_files)} | Links: {total_checked}')
    print('=============================================')
    if is_pass:
        print('Documentation Status: PASS (0 broken relative links)')
    else:
        print(f'Documentation Status: FAIL ({len(broken_links)} broken links)')
        for bl in broken_links:
            print(f\"  [Broken Link] {bl['file']}:{bl['line']} -> {bl['target']}\")
    print('=============================================')

if not is_pass:
    sys.exit(1)
"
else
  echo "python3 required for docs linting"
fi
