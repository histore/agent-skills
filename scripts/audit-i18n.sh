#!/usr/bin/env bash
# ==============================================================================
# Audits localization key parity between German (de) and English (en) resource files.
# ==============================================================================
set -euo pipefail

RES_DIR="${1:-$(pwd)}"
JSON_OUTPUT=false

for arg in "$@"; do
  if [[ "$arg" == "--json" || "$arg" == "-j" ]]; then
    JSON_OUTPUT=true
  fi
done

if command -v python3 &>/dev/null; then
  python3 -c "
import os, json, sys

base_dir = '$RES_DIR'
de_files = []
for root, dirs, files in os.walk(base_dir):
    if '.git' in root or 'node_modules' in root:
        continue
    for f in files:
        if f.lower().endswith('.de.json') or f.lower() == 'de.json':
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
    en_path = de_path.replace('.de.json', '.en.json').replace('de.json', 'en.json')
    if os.path.isfile(en_path):
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
json_out = '$JSON_OUTPUT' == 'true'

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
"
else
  echo "python3 required for i18n key audit"
fi
