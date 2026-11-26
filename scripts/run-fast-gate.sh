#!/usr/bin/env bash
# ==============================================================================
# Executes a Stage-1 deterministic Fast-Gate (build, test, lint) with log compaction.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
TEST_FILTER=""
SKIP_LINT=false
SKIP_GUARDRAILS=false
FORCE=false
MAX_DIFF_LINES=400
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    --skip-lint)
      SKIP_LINT=true
      shift
      ;;
    --skip-guardrails)
      SKIP_GUARDRAILS=true
      shift
      ;;
    --force|-f)
      FORCE=true
      shift
      ;;
    --max-diff-lines)
      MAX_DIFF_LINES="${2:-400}"
      shift 2
      ;;
    --max-diff-lines=*)
      MAX_DIFF_LINES="${1#*=}"
      shift
      ;;
    --filter)
      TEST_FILTER="${2:-}"
      shift 2
      ;;
    --filter=*)
      TEST_FILTER="${1#*=}"
      shift
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --project-root=*)
      PROJECT_ROOT="${1#*=}"
      shift
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

DETECT_SCRIPT="${SCRIPT_DIR}/detect-tech-stack.sh"
STACK="unknown"
LANG="unknown"
BUILD_CMD=""
TEST_CMD=""
FILTER_SYNTAX=""
LINT_CMD=""
SUPPORT_LEVEL="full"
SUPPORT_GAPS=""

if [[ -f "$DETECT_SCRIPT" ]]; then
  STACK_JSON=$(bash "$DETECT_SCRIPT" "$PROJECT_ROOT" --json 2>/dev/null || echo '{}')
  if command -v python3 &>/dev/null; then
    {
      IFS= read -r STACK || true
      IFS= read -r LANG || true
      IFS= read -r BUILD_CMD || true
      IFS= read -r TEST_CMD || true
      IFS= read -r FILTER_SYNTAX || true
      IFS= read -r LINT_CMD || true
      IFS= read -r SUPPORT_LEVEL || true
      IFS= read -r SUPPORT_GAPS || true
    } < <(python3 - "$STACK_JSON" << 'EOF' 2>/dev/null | tr -d '\r' || true
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('stack', 'unknown'))
    print(d.get('language', 'unknown'))
    print(d.get('build_cmd', ''))
    print(d.get('test_cmd', ''))
    print(d.get('test_filter_syntax', ''))
    print(d.get('lint_cmd', ''))
    print(d.get('support_level', 'full'))
    print(', '.join(d.get('support_gaps', [])))
except Exception:
    print('unknown\nunknown\n\n\n\n\nfull\n')
EOF
    )
  fi
fi

get_time_ns() {
  local d
  d=$(date +%s%N 2>/dev/null || true)
  if [[ "$d" =~ ^[0-9]+$ ]]; then
    echo "$d"
  elif command -v python3 &>/dev/null; then
    python3 -c 'import time; print(int(time.time()*1e9))'
  else
    echo "$(( $(date +%s) * 1000000000 ))"
  fi
}

START_TIME=$(get_time_ns)
FAILED_STEP=""
ERROR_LOG=""
WARNINGS_LOG=""

run_step() {
  local step_name="$1"
  local cmd="$2"
  if [[ -z "$cmd" ]]; then return 0; fi

  local tmp_out
  tmp_out=$(mktemp)
  if ! (cd "$PROJECT_ROOT" && eval "$cmd") >"$tmp_out" 2>&1; then
    FAILED_STEP="$step_name"
    ERROR_LOG=$(grep -iE -C 2 "error|failed|exception|assert|fatal|panicked" "$tmp_out" | head -n 12 || tail -n 8 "$tmp_out")
    rm -f "$tmp_out"
    return 1
  fi
  rm -f "$tmp_out"
  return 0
}

BYPASSED_NO_CODE=false
if [[ "$FORCE" != "true" && -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" && "$STACK" != "unknown" ]]; then
  if command -v git &>/dev/null; then
    GIT_STATUS=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || true)
    if [[ -z "$GIT_STATUS" ]]; then
      BYPASSED_NO_CODE=true
    else
      HAS_CODE=false
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        FILE_PATH="${line:3}"
        [[ "$FILE_PATH" =~ "->" ]] && FILE_PATH="${FILE_PATH##*-> }"
        FILE_PATH="${FILE_PATH%\"}"
        FILE_PATH="${FILE_PATH#\"}"
        FILE_NAME="$(basename "$FILE_PATH")"
        if [[ "$FILE_NAME" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|qml|qrc|ui|swift|rb|php|scala|dart|zig|sql)$ ]] || \
           [[ "$FILE_NAME" =~ ^(Cargo\.(toml|lock)|package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|.*\.csproj|.*\.fsproj|.*\.sln|Directory\.Build\.(props|targets)|pyproject\.toml|requirements\.txt|Pipfile|go\.(mod|sum)|pom\.xml|(build|settings)\.gradle(\.kts)?|libs\.versions\.toml|AndroidManifest\.xml|CMakeLists\.txt|CMakePresets\.json|.*\.vcxproj|Makefile)$ ]]; then
          HAS_CODE=true
          break
        fi
      done <<< "$GIT_STATUS"
      if [[ "$HAS_CODE" != "true" ]]; then
        BYPASSED_NO_CODE=true
      fi
    fi
  fi
fi

OVERALL_PASS=true

if [[ "$STACK" != "unknown" && "$BYPASSED_NO_CODE" != "true" ]]; then
  if [[ -n "$BUILD_CMD" ]]; then
    if ! run_step "Build" "$BUILD_CMD"; then
      OVERALL_PASS=false
    fi
  fi

  if [[ "$OVERALL_PASS" == "true" && -n "$TEST_CMD" ]]; then
    CMD="$TEST_CMD"
    if [[ -n "$TEST_FILTER" && -n "$FILTER_SYNTAX" ]]; then
      CMD="${FILTER_SYNTAX//\{filter\}/$TEST_FILTER}"
    fi
    if ! run_step "Test" "$CMD"; then
      OVERALL_PASS=false
    fi
  fi

  if [[ "$OVERALL_PASS" == "true" && "$SKIP_LINT" == "false" && -n "$LINT_CMD" ]]; then
    if ! run_step "Lint" "$LINT_CMD"; then
      OVERALL_PASS=false
    fi
  fi
elif [[ "${SUPPORT_LEVEL:-full}" == "unsupported" ]]; then
  WARNINGS_LOG+="[ToolchainGap] Stack '${STACK}' / Language '${LANG:-unknown}' is unsupported (${SUPPORT_GAPS:-no_build_or_test_runner}). Automated Build/Test/Architecture gates were skipped."$'\n'
fi

if [[ "$OVERALL_PASS" == "true" && "$SKIP_GUARDRAILS" == "false" ]]; then
  if [[ "$BYPASSED_NO_CODE" != "true" && "${SUPPORT_LEVEL:-full}" == "partial" && -n "${SUPPORT_GAPS:-}" ]]; then
    WARNINGS_LOG+="[ToolchainGap] Partial support for '${STACK}': ${SUPPORT_GAPS}."$'\n'
  fi
  if [[ -f "${SCRIPT_DIR}/lint-clean-architecture.sh" ]]; then
    ARCH_OUT=""
    if ! ARCH_OUT=$(bash "${SCRIPT_DIR}/lint-clean-architecture.sh" "$PROJECT_ROOT" --working-tree --json 2>&1); then
      OVERALL_PASS=false
      FAILED_STEP="CleanArchitecture"
      if command -v python3 &>/dev/null; then
        ERROR_LOG=$(python3 - "$ARCH_OUT" << 'EOF' 2>/dev/null || printf '%s\n' "$ARCH_OUT"
import json, sys
try:
    d = json.loads(sys.argv[1])
    lines = [f"[{v.get('Type', v.get('type', 'Error'))}] {v.get('File', v.get('file', ''))}:{v.get('Line', v.get('line', 0))} - {v.get('Message', v.get('message', ''))}" for v in d.get('violations', []) if v.get('Severity', v.get('severity')) == 'Error']
    print('\n'.join(lines) if lines else sys.argv[1])
except Exception:
    print(sys.argv[1])
EOF
        )
      else
        ERROR_LOG="$ARCH_OUT"
      fi
    fi
  fi
  if [[ "$OVERALL_PASS" == "true" && -f "${SCRIPT_DIR}/scan-guardrails.sh" ]]; then
    SCAN_OUT=""
    if ! SCAN_OUT=$(bash "${SCRIPT_DIR}/scan-guardrails.sh" --path "$PROJECT_ROOT" --working-tree --skip-line-endings --json 2>&1); then
      OVERALL_PASS=false
      FAILED_STEP="Guardrails"
      if command -v python3 &>/dev/null; then
        ERROR_LOG=$(python3 - "$SCAN_OUT" << 'EOF' 2>/dev/null || printf '%s\n' "$SCAN_OUT"
import json, sys
try:
    d = json.loads(sys.argv[1])
    lines = []
    for v in d.get('violations', []):
        if isinstance(v, dict):
            lines.append(f"[{v.get('Rule', 'Guardrail')}] {v.get('File', '')}:{v.get('Line', 0)} - {v.get('Message', '')}")
        else:
            lines.append(str(v))
    print('\n'.join(lines) if lines else sys.argv[1])
except Exception:
    print(sys.argv[1])
EOF
        )
      else
        ERROR_LOG="$SCAN_OUT"
      fi
    fi
  fi
  if [[ "$OVERALL_PASS" == "true" && ( "$STACK" == "android-gradle" || "$LANG" == "kotlin" ) && -f "${SCRIPT_DIR}/lint-android-contracts.sh" ]]; then
    ANDROID_OUT=""
    if ! ANDROID_OUT=$(bash "${SCRIPT_DIR}/lint-android-contracts.sh" --project-root "$PROJECT_ROOT" --working-tree --json 2>&1); then
      OVERALL_PASS=false
      FAILED_STEP="AndroidContracts"
      if command -v python3 &>/dev/null; then
        ERROR_LOG=$(python3 - "$ANDROID_OUT" << 'EOF' 2>/dev/null || printf '%s\n' "$ANDROID_OUT"
import json, sys
try:
    d = json.loads(sys.argv[1])
    lines = [f"[{v.get('Rule', 'AndroidContracts')}] {v.get('File', '')}:{v.get('Line', 0)} - {v.get('Message', '')}" for v in d.get('errors', [])]
    print('\n'.join(lines) if lines else sys.argv[1])
except Exception:
    print(sys.argv[1])
EOF
        )
      else
        ERROR_LOG="$ANDROID_OUT"
      fi
    fi
  fi
  if [[ "$OVERALL_PASS" == "true" && ( "$LANG" == "cpp" || "$STACK" =~ cmake|msbuild ) && -f "${SCRIPT_DIR}/lint-cpp-qt-contracts.sh" ]]; then
    CPPQT_OUT=""
    if ! CPPQT_OUT=$(bash "${SCRIPT_DIR}/lint-cpp-qt-contracts.sh" --project-root "$PROJECT_ROOT" --working-tree --json 2>&1); then
      OVERALL_PASS=false
      FAILED_STEP="CppQtContracts"
      if command -v python3 &>/dev/null; then
        ERROR_LOG=$(python3 - "$CPPQT_OUT" << 'EOF' 2>/dev/null || printf '%s\n' "$CPPQT_OUT"
import json, sys
try:
    d = json.loads(sys.argv[1])
    lines = [f"[{v.get('Rule', 'CppQtContracts')}] {v.get('File', '')}:{v.get('Line', 0)} - {v.get('Message', '')}" for v in d.get('errors', [])]
    print('\n'.join(lines) if lines else sys.argv[1])
except Exception:
    print(sys.argv[1])
EOF
        )
      else
        ERROR_LOG="$CPPQT_OUT"
      fi
    fi
  fi
  # 3b. Diff-Size-Guardrail (FEAT-GOV-002 AC-3: Warning only when executable code diff exceeds MAX_DIFF_LINES)
  if [[ "$BYPASSED_NO_CODE" != "true" && "$MAX_DIFF_LINES" -gt 0 ]] && command -v git &>/dev/null; then
    NUMSTAT_OUT=$(git -C "$PROJECT_ROOT" diff --numstat HEAD 2>/dev/null || true)
    if [[ -n "$NUMSTAT_OUT" ]]; then
      TOTAL_DIFF_LINES=0
      while IFS=$'\t' read -r added deleted diff_file; do
        [[ -z "$added" || "$added" == "-" || "$deleted" == "-" ]] && continue
        if [[ "$diff_file" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql|ps1|sh)$ ]]; then
          TOTAL_DIFF_LINES=$(( TOTAL_DIFF_LINES + added + deleted ))
        fi
      done <<< "$NUMSTAT_OUT"
      if [[ "$TOTAL_DIFF_LINES" -gt "$MAX_DIFF_LINES" ]]; then
        WARNINGS_LOG+="[DiffSize] $TOTAL_DIFF_LINES executable code lines changed in working tree (threshold: $MAX_DIFF_LINES). Consider splitting into smaller atomic commits."$'\n'
      fi
    fi
  fi

  # 3c. AC-* Traceability Check (FEAT-GOV-002 AC-1/AC-2: Stage-1 Fail when active APPROVED/IN_PROGRESS FEAT-*.md has uncovered AC-* IDs)
  if [[ "$OVERALL_PASS" == "true" && "$BYPASSED_NO_CODE" != "true" && -d "${PROJECT_ROOT}/docs/features" ]]; then
    ACTIVE_SPECS=()
    while IFS= read -r -d '' sf; do
      if grep -qE '^status:[[:space:]]*(APPROVED|IN_PROGRESS)\b' "$sf" 2>/dev/null; then
        ACTIVE_SPECS+=("$sf")
      fi
    done < <(find "${PROJECT_ROOT}/docs/features" -maxdepth 1 -type f -name 'FEAT-*.md' -print0 2>/dev/null)

    if [[ ${#ACTIVE_SPECS[@]} -gt 0 ]]; then
      TEST_CORPUS_FILE=$(mktemp)
      while IFS= read -r -d '' tf; do
        cat "$tf" >> "$TEST_CORPUS_FILE" 2>/dev/null || true
        echo "" >> "$TEST_CORPUS_FILE"
      done < <(find "$PROJECT_ROOT" -type f \
        ! -path '*/node_modules/*' ! -path '*/target/*' ! -path '*/bin/*' ! -path '*/obj/*' \
        ! -path '*/.git/*' ! -path '*/_agents/*' ! -path '*/.agents/*' ! -path '*/dist/*' ! -path '*/build/*' \
        \( -ipath '*/tests/*' -o -ipath '*/test/*' -o -ipath '*/androidTest/*' -o -ipath '*/commonTest/*' -o -ipath '*/jvmTest/*' -o -ipath '*/desktopTest/*' -o -ipath '*/androidUnitTest/*' -o -ipath '*/androidInstrumentedTest/*' -o -ipath '*/iosTest/*' -o -ipath '*/jsTest/*' -o -ipath '*/wasmJsTest/*' -o -ipath '*/nativeTest/*' -o -ipath '*/specs/*' -o -ipath '*/__tests__/*' -o -ipath '*/evals/*' \
           -o -iname '*test.*' -o -name '*Test.kt' -o -name '*Test.java' -o -name '*Test.cpp' -o -name 'tst_*.cpp' -o -name 'tst_*.qml' -o -iname '*spec.*' -o -iname '*_test.*' -o -name 'eval-cases.json' -o -name 'test-skills.ps1' -o -name 'test-skills.sh' \) \
        -print0 2>/dev/null)

      for sf in "${ACTIVE_SPECS[@]}"; do
        REL_SPEC="${sf#${PROJECT_ROOT}/}"
        while IFS= read -r ac_id; do
          [[ -z "$ac_id" ]] && continue
          if ! grep -qE "\b${ac_id}\b" "$TEST_CORPUS_FILE" 2>/dev/null; then
            OVERALL_PASS=false
            FAILED_STEP="ACTraceability"
            ERROR_LOG+="[ACTraceability] ${REL_SPEC}: Missing test reference for ${ac_id} (reference ${ac_id} in a test name or comment)"$'\n'
          fi
        done < <(grep -E '^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*\*\*AC-[0-9]+\*\*' "$sf" 2>/dev/null | grep -oE 'AC-[0-9]+' || true)
      done
      rm -f "$TEST_CORPUS_FILE"
    fi
  fi
fi

END_TIME=$(get_time_ns)
DURATION_MS=0
if [[ "$END_TIME" =~ ^[0-9]+$ && "$START_TIME" =~ ^[0-9]+$ && ${#END_TIME} -gt 10 ]]; then
  DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  if command -v python3 &>/dev/null; then
    python3 - "$OVERALL_PASS" "$FAILED_STEP" "$DURATION_MS" "$BYPASSED_NO_CODE" "$ERROR_LOG" "$WARNINGS_LOG" << 'EOF'
import json, sys
ok_s, step, dur_s, byp_s, raw_err, raw_warn = sys.argv[1:7]
errs = [l.strip() for l in raw_err.splitlines() if l.strip()] if ok_s != "true" else []
warns = [l.strip() for l in raw_warn.splitlines() if l.strip()]
print(json.dumps({
    "status": "pass" if ok_s == "true" else "fail",
    "failed_step": None if ok_s == "true" else step,
    "duration_ms": int(dur_s),
    "bypassed_code_gate": byp_s == "true",
    "errors": errs,
    "warnings": warns,
}))
EOF
  else
    ERR_ARR=""
    if [[ "$OVERALL_PASS" != "true" ]]; then
      while IFS= read -r eline; do
        [[ -z "$eline" ]] && continue
        eline="${eline//\\/\\\\}"
        eline="${eline//\"/\\\"}"
        eline="${eline//$'\r'/}"
        [[ -n "$ERR_ARR" ]] && ERR_ARR+=","
        ERR_ARR+="\"$eline\""
      done <<< "$ERROR_LOG"
    fi
    WARN_ARR=""
    while IFS= read -r wline; do
      [[ -z "$wline" ]] && continue
      wline="${wline//\\/\\\\}"
      wline="${wline//\"/\\\"}"
      wline="${wline//$'\r'/}"
      [[ -n "$WARN_ARR" ]] && WARN_ARR+=","
      WARN_ARR+="\"$wline\""
    done <<< "$WARNINGS_LOG"
    if [[ "$OVERALL_PASS" == "true" ]]; then
      echo "{\"status\":\"pass\",\"failed_step\":null,\"duration_ms\":$DURATION_MS,\"bypassed_code_gate\":$BYPASSED_NO_CODE,\"errors\":[],\"warnings\":[$WARN_ARR]}"
    else
      echo "{\"status\":\"fail\",\"failed_step\":\"$FAILED_STEP\",\"duration_ms\":$DURATION_MS,\"bypassed_code_gate\":$BYPASSED_NO_CODE,\"errors\":[$ERR_ARR],\"warnings\":[$WARN_ARR]}"
    fi
  fi
else
  if [[ "$OVERALL_PASS" == "true" ]]; then
    if [[ "$BYPASSED_NO_CODE" == "true" ]]; then
      echo "Stage-1 Fast-Gate: PASS (${DURATION_MS}ms) - Bypassed (no executable code modified in working tree; use --force to override)"
    else
      echo "Stage-1 Fast-Gate: PASS (${DURATION_MS}ms) - Zero errors"
    fi
  else
    echo "Stage-1 Fast-Gate: FAIL at step '$FAILED_STEP'"
    echo "$ERROR_LOG"
  fi
  if [[ -n "$WARNINGS_LOG" ]]; then
    while IFS= read -r wline; do
      [[ -n "$wline" ]] && echo "  [WARN] $wline"
    done <<< "$WARNINGS_LOG"
  fi
fi

if [[ "$OVERALL_PASS" == "false" ]]; then
  exit 1
fi
