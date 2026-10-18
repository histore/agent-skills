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
  python3 - "$REPO_ROOT" "$CHECK_PARITY" "$JSON_OUTPUT" << 'EOF'
import os, re, json, sys

repo_root = os.path.abspath(sys.argv[1])
check_parity = sys.argv[2] == 'true'
json_output = sys.argv[3] == 'true'

md_files = []
for root, dirs, files in os.walk(repo_root):
    if '.git' in root or 'node_modules' in root:
        continue
    for f in files:
        if f.endswith('.md'):
            md_files.append(os.path.join(root, f))

link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
fence_pattern = re.compile(r'^\s*(```|~~~)')
inline_code_pattern = re.compile(r'`[^`]+`')
broken_links = []
total_checked = 0

for file_path in md_files:
    file_dir = os.path.dirname(file_path)
    rel_source = os.path.relpath(file_path, repo_root)
    in_code_block = False
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as fp:
        for idx, line in enumerate(fp, 1):
            if fence_pattern.match(line):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                continue
            clean_line = inline_code_pattern.sub('', line)
            for match in link_pattern.finditer(clean_line):
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

parity_mismatches = []
if check_parity:
    src_dir = os.path.join(repo_root, 'src')
    arch_mod_dir = os.path.join(repo_root, 'docs', 'architecture', 'modules')
    if os.path.isdir(src_dir) and os.path.isdir(arch_mod_dir):
        for entry in sorted(os.listdir(src_dir)):
            mod_path = os.path.join(src_dir, entry)
            if os.path.isdir(mod_path):
                expected_spec = os.path.join(arch_mod_dir, f'{entry}.md')
                if not os.path.isfile(expected_spec):
                    parity_mismatches.append(f"Module 'src/{entry}' missing spec in docs/architecture/modules/{entry}.md")

is_pass = len(broken_links) == 0 and len(parity_mismatches) == 0

if json_output:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'scanned_markdowns': len(md_files),
        'links_checked': total_checked,
        'broken_links_count': len(broken_links),
        'broken_links': broken_links,
        'parity_mismatches': parity_mismatches
    }))
else:
    print('=============================================')
    print('Deterministic Documentation & Link Integrity Linter')
    print(f'Files: {len(md_files)} | Links: {total_checked}')
    print('=============================================')
    if is_pass:
        print('Documentation Status: PASS (0 broken relative links)')
    else:
        print(f'Documentation Status: FAIL ({len(broken_links)} broken links, {len(parity_mismatches)} parity gaps)')
        for bl in broken_links:
            print(f"  [Broken Link] {bl['file']}:{bl['line']} -> {bl['target']}")
        for pm in parity_mismatches:
            print(f"  [Parity Gap] {pm}")
    print('=============================================')

if not is_pass:
    sys.exit(1)
EOF
else
  echo "python3 required for docs linting"
fi
