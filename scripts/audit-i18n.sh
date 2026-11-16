#!/usr/bin/env bash
# ==============================================================================
# Audits localization key parity between German (de) and English (en) resource files.
# ==============================================================================
set -euo pipefail

RES_DIR=""
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --json|-j)
      JSON_OUTPUT=true
      ;;
    -*)
      ;;
    *)
      if [[ -z "$RES_DIR" ]]; then
        RES_DIR="$arg"
      fi
      ;;
  esac
done

if [[ -z "$RES_DIR" ]]; then
  RES_DIR="$(pwd)"
fi

if command -v python3 &>/dev/null; then
  python3 - "$RES_DIR" "$JSON_OUTPUT" << 'EOF'
import os, json, re, sys

base_dir = sys.argv[1]
json_out = sys.argv[2] == 'true'

ignored_dirs = {'.git', '_agents', '.agents', 'node_modules', 'target', 'bin', 'obj'}
de_files = []
for root, dirs, files in os.walk(base_dir):
    dirs[:] = [d for d in dirs if d not in ignored_dirs]
    for f in files:
        if re.search(r'(^|\.)de(-[a-z]{2})?\.json$', f, re.IGNORECASE):
            de_files.append(os.path.join(root, f))

def flatten(d, prefix=''):
    keys = set()
    for k, v in d.items():
        curr = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            keys.update(flatten(v, curr))
        else:
            keys.add(curr)
    return keys

missing_in_de = []
missing_in_en = []
pairs_checked = 0

for de_path in de_files:
    dir_name = os.path.dirname(de_path)
    base_name = os.path.basename(de_path)
    en_cand1 = os.path.join(dir_name, re.sub(r'\.de(-[a-z]{2})?\.json$', '.en.json', base_name, flags=re.IGNORECASE))
    en_cand2 = os.path.join(dir_name, re.sub(r'\bde\b', 'en', base_name, flags=re.IGNORECASE))
    en_path = en_cand1 if os.path.isfile(en_cand1) else (en_cand2 if os.path.isfile(en_cand2) else None)
    if en_path and os.path.isfile(en_path):
        pairs_checked += 1
        try:
            with open(de_path, 'r', encoding='utf-8') as f:
                de_data = json.load(f)
            with open(en_path, 'r', encoding='utf-8') as f:
                en_data = json.load(f)

            de_keys = flatten(de_data)
            en_keys = flatten(en_data)

            for k in en_keys - de_keys:
                missing_in_de.append(f'{os.path.basename(de_path)}: {k}')
            for k in de_keys - en_keys:
                missing_in_en.append(f'{os.path.basename(en_path)}: {k}')
        except Exception:
            pass

is_pass = len(missing_in_de) == 0 and len(missing_in_en) == 0

if json_out:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'pairs_audited': pairs_checked,
        'missing_in_de': missing_in_de,
        'missing_in_en': missing_in_en
    }))
else:
    print('=============================================')
    print('Bilingual (de/en) Localization Key Auditor')
    print(f'Resource Pairs Checked: {pairs_checked}')
    print('=============================================')
    if is_pass:
        print('Localization Parity: PASS (0 missing keys)')
    else:
        print('Localization Parity: FAIL (Key mismatches found)')
        for k in missing_in_de:
            print(f'  Missing in DE: {k}')
        for k in missing_in_en:
            print(f'  Missing in EN: {k}')
    print('=============================================')

if not is_pass:
    sys.exit(1)
EOF
else
  echo "python3 required for i18n key audit"
fi
