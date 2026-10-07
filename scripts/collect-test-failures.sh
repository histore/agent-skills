#!/usr/bin/env bash
# ==============================================================================
# Deterministic test failure diagnostics and stack trace extractor.
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
RESULTS_PATH=""
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --results=*|-r=*)
      RESULTS_PATH="${arg#*=}"
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

if command -v python3 &>/dev/null; then
  python3 -c "
import os, sys, glob, json
import xml.etree.ElementTree as ET

repo_root = '$REPO_ROOT'
custom_path = '$RESULTS_PATH'
json_out = '$JSON_OUTPUT' == 'true'

files = []
if custom_path and os.path.exists(custom_path):
    if os.path.isdir(custom_path):
        files.extend(glob.glob(os.path.join(custom_path, '**/*.trx'), recursive=True))
        files.extend(glob.glob(os.path.join(custom_path, '**/*junit*.xml'), recursive=True))
    else:
        files.append(custom_path)
else:
    candidates = [
        os.path.join(repo_root, 'TestResults'),
        os.path.join(repo_root, 'test-results'),
        os.path.join(repo_root, 'target/surefire-reports')
    ]
    for c in candidates:
        if os.path.isdir(c):
            files.extend(glob.glob(os.path.join(c, '**/*.trx'), recursive=True))
            files.extend(glob.glob(os.path.join(c, '**/*.xml'), recursive=True))

failures = []
total_tests = 0

for f in files:
    try:
        tree = ET.parse(f)
        root = tree.getroot()
        # JUnit
        for tc in root.iter('testcase'):
            total_tests += 1
            fail = tc.find('failure')
            if fail is not None:
                failures.append({
                    'test_name': f\"{tc.attrib.get('classname', '')}.{tc.attrib.get('name', '')}\",
                    'error_message': fail.attrib.get('message', fail.text or '').strip(),
                    'report_file': os.path.basename(f)
                })
        # TRX
        for utr in root.iter('{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}UnitTestResult'):
            total_tests += 1
            if utr.attrib.get('outcome') == 'Failed':
                err_msg = ''
                err_info = utr.find('.//{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}ErrorInfo')
                if err_info is not None:
                    msg = err_info.find('{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}Message')
                    if msg is not None and msg.text:
                        err_msg = msg.text.strip()
                failures.append({
                    'test_name': utr.attrib.get('testName', ''),
                    'error_message': err_msg,
                    'report_file': os.path.basename(f)
                })
    except Exception:
        pass

is_pass = len(failures) == 0

if json_out:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'reports_scanned': len(files),
        'total_tests': total_tests,
        'failed_count': len(failures),
        'failures': failures
    }))
else:
    print('=============================================')
    print('Test Failure Diagnostics Collector')
    print(f'Reports: {len(files)} | Tests: {total_tests} | Failed: {len(failures)}')
    print('=============================================')
    if is_pass:
        print('Diagnostics Status: PASS (0 test failures detected)')
    else:
        print(f'Diagnostics Status: FAIL ({len(failures)} test failures detected)')
        for fail in failures:
            print(f\"  [FAILED] {fail['test_name']}: {fail['error_message']}\")
    print('=============================================')

if not is_pass:
    sys.exit(1)
"
else
  echo 'python3 required for test failure collection'
  exit 0
fi
