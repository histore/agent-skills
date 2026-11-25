#!/usr/bin/env bash
# ==============================================================================
# Deterministic test failure diagnostics and stack trace extractor.
# ==============================================================================
set -euo pipefail

REPO_ROOT=""
RESULTS_PATH=""
LOG_FILE=""
LOG_TEXT=""
RUN_TESTS=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --repo-root=*)
      REPO_ROOT="${1#*=}"
      shift
      ;;
    --results|-r)
      RESULTS_PATH="$2"
      shift 2
      ;;
    --results=*|-r=*)
      RESULTS_PATH="${1#*=}"
      shift
      ;;
    --log-file|-l)
      LOG_FILE="$2"
      shift 2
      ;;
    --log-file=*|-l=*)
      LOG_FILE="${1#*=}"
      shift
      ;;
    --log-text)
      LOG_TEXT="$2"
      shift 2
      ;;
    --log-text=*)
      LOG_TEXT="${1#*=}"
      shift
      ;;
    --run)
      RUN_TESTS=true
      shift
      ;;
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$REPO_ROOT" ]]; then
        REPO_ROOT="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  SUPERPROJECT=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
  if [[ -n "$SUPERPROJECT" ]]; then
    REPO_ROOT="$SUPERPROJECT"
  else
    TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$TOPLEVEL" ]]; then
      REPO_ROOT="$TOPLEVEL"
      if [[ "$REPO_ROOT" =~ /(_agents|\.agents)$ ]]; then
        REPO_ROOT="$(dirname "$REPO_ROOT")"
      fi
    else
      REPO_ROOT="$(pwd)"
    fi
  fi
fi

if [[ "$RUN_TESTS" == "true" ]]; then
  if [[ -n "$(find "$REPO_ROOT" -maxdepth 3 \( -name "*.sln" -o -name "*.csproj" \) -type f 2>/dev/null | head -n 1)" ]]; then
    TRX_DIR="${REPO_ROOT}/TestResults"
    mkdir -p "$TRX_DIR"
    TRX_FILE="${TRX_DIR}/run_diagnostics.trx"
    rm -f "$TRX_FILE"
    (cd "$REPO_ROOT" && dotnet test --logger "trx;LogFileName=run_diagnostics.trx" --verbosity quiet) >/dev/null 2>&1 || true
    RESULTS_PATH="$TRX_FILE"
  fi
fi

if command -v python3 &>/dev/null; then
  python3 - "$REPO_ROOT" "$RESULTS_PATH" "$LOG_FILE" "$LOG_TEXT" "$JSON_OUTPUT" << 'EOF'
import os, re, sys, glob, json
import xml.etree.ElementTree as ET

repo_root, custom_path, log_file, log_text, json_out_s = sys.argv[1:6]
json_out = json_out_s == 'true'

def clean_stack_trace(raw_stack):
    if not raw_stack:
        return ''
    filtered = []
    skip_re = re.compile(r'System\.Runtime\.|Microsoft\.VisualStudio\.TestPlatform\.|Xunit\.Sdk\.|NUnit\.Framework\.Internal\.')
    for line in raw_stack.splitlines():
        trimmed = line.strip()
        if not trimmed or skip_re.search(trimmed):
            continue
        filtered.append(trimmed)
        if len(filtered) >= 8:
            break
    return '\n'.join(filtered)

files = []
if custom_path and os.path.exists(custom_path):
    if os.path.isdir(custom_path):
        files.extend(glob.glob(os.path.join(custom_path, '**/*.trx'), recursive=True))
        files.extend(glob.glob(os.path.join(custom_path, '**/*junit*.xml'), recursive=True))
        files.extend(glob.glob(os.path.join(custom_path, '**/*test*.xml'), recursive=True))
    else:
        files.append(custom_path)
else:
    candidates = [
        os.path.join(repo_root, 'TestResults'),
        os.path.join(repo_root, 'test-results'),
        os.path.join(repo_root, 'target/surefire-reports'),
        os.path.join(repo_root, 'build/test-results'),
        os.path.join(repo_root, '.pytest_cache')
    ]
    for c in candidates:
        if os.path.isdir(c):
            found = glob.glob(os.path.join(c, '**/*.trx'), recursive=True) + glob.glob(os.path.join(c, '**/*.xml'), recursive=True)
            found.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            files.extend(found[:3])
    if not files:
        gradle_xmls = glob.glob(os.path.join(repo_root, '**/build/test-results/**/TEST-*.xml'), recursive=True)
        gradle_xmls.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        files.extend(gradle_xmls[:5])

failures = []
total_tests = 0
total_passed = 0

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
                    'TestName': f"{tc.attrib.get('classname', '')}.{tc.attrib.get('name', '')}",
                    'Outcome': 'Failed',
                    'Duration': tc.attrib.get('time', '0s'),
                    'ErrorMessage': fail.attrib.get('message', fail.text or '').strip(),
                    'StackTrace': clean_stack_trace(fail.text or ''),
                    'ReportFile': os.path.basename(f)
                })
            else:
                total_passed += 1
        # TRX
        for utr in root.iter('{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}UnitTestResult'):
            total_tests += 1
            outcome = utr.attrib.get('outcome')
            if outcome == 'Passed':
                total_passed += 1
            elif outcome == 'Failed':
                err_msg = ''
                stack = ''
                err_info = utr.find('.//{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}ErrorInfo')
                if err_info is not None:
                    msg = err_info.find('{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}Message')
                    st = err_info.find('{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}StackTrace')
                    if msg is not None and msg.text:
                        err_msg = msg.text.strip()
                    if st is not None and st.text:
                        stack = clean_stack_trace(st.text)
                failures.append({
                    'TestName': utr.attrib.get('testName', ''),
                    'Outcome': 'Failed',
                    'Duration': utr.attrib.get('duration', '0s'),
                    'ErrorMessage': err_msg,
                    'StackTrace': stack,
                    'ReportFile': os.path.basename(f)
                })
    except Exception:
        pass

raw_log = ''
if log_file and os.path.isfile(log_file):
    try:
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as lf:
            raw_log = lf.read()
    except Exception:
        pass
elif log_text:
    raw_log = log_text

if raw_log:
    log_lines = raw_log.splitlines()
    for i, raw_line in enumerate(log_lines):
        l = raw_line.strip()
        m = re.search(r'(?:FAILED|FAIL)\s+([A-Za-z0-9_.:]+)', l, re.IGNORECASE) or re.search(r'Test\s+([A-Za-z0-9_.]+)\s+failed', l, re.IGNORECASE)
        if m:
            test_name = m.group(1) or 'UnknownTest'
            err_msg = ''
            for k in range(i + 1, min(len(log_lines), i + 6)):
                if re.search(r'assert|error|exception|expected', log_lines[k], re.IGNORECASE):
                    err_msg = log_lines[k].strip()
                    break
            total_tests += 1
            failures.append({
                'TestName': test_name,
                'Outcome': 'Failed',
                'Duration': '0s',
                'ErrorMessage': err_msg,
                'StackTrace': '',
                'ReportFile': os.path.basename(log_file) if log_file else 'log-stream'
            })

is_pass = len(failures) == 0

if json_out:
    print(json.dumps({
        'status': 'pass' if is_pass else 'fail',
        'reports_scanned': len(files),
        'total_tests': total_tests,
        'passed_count': total_passed,
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
            print(f"  [FAILED] {fail['TestName']}: {fail['ErrorMessage']}")
            if fail.get('StackTrace'):
                for sl in fail['StackTrace'].splitlines():
                    print(f"    {sl}")
    print('=============================================')

if not is_pass:
    sys.exit(1)
EOF
else
  echo 'python3 required for test failure collection'
  exit 0
fi
