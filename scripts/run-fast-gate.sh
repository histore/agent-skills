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
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --json|-j)
      JSON_OUTPUT=true
      ;;
    --skip-lint)
      SKIP_LINT=true
      ;;
    --skip-guardrails)
      SKIP_GUARDRAILS=true
      ;;
    --force|-f)
      FORCE=true
      ;;
    --filter=*)
      TEST_FILTER="${arg#*=}"
      ;;
    -*)
      ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$arg"
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

DETECT_SCRIPT="${SCRIPT_DIR}/detect-tech-stack.sh"
STACK="unknown"
BUILD_CMD=""
TEST_CMD=""
FILTER_SYNTAX=""
LINT_CMD=""

if [[ -f "$DETECT_SCRIPT" ]]; then
  STACK_JSON=$(bash "$DETECT_SCRIPT" "$PROJECT_ROOT" --json 2>/dev/null || echo '{}')
  if command -v python3 &>/dev/null; then
    {
      IFS= read -r STACK || true
      IFS= read -r BUILD_CMD || true
      IFS= read -r TEST_CMD || true
      IFS= read -r FILTER_SYNTAX || true
      IFS= read -r LINT_CMD || true
    } < <(python3 - "$STACK_JSON" << 'EOF' 2>/dev/null || true
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('stack', 'unknown'))
    print(d.get('build_cmd', ''))
    print(d.get('test_cmd', ''))
    print(d.get('test_filter_syntax', ''))
    print(d.get('lint_cmd', ''))
except Exception:
    print('unknown\n\n\n\n')
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
        FILE_NAME="$(basename "$FILE_PATH")"
        if [[ "$FILE_NAME" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql)$ ]] || \
           [[ "$FILE_NAME" =~ ^(Cargo\.(toml|lock)|package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|.*\.csproj|.*\.fsproj|.*\.sln|Directory\.Build\.(props|targets)|pyproject\.toml|requirements\.txt|Pipfile|go\.(mod|sum)|pom\.xml|(build|settings)\.gradle(\.kts)?|libs\.versions\.toml|CMakeLists\.txt|Makefile)$ ]]; then
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
fi

if [[ "$OVERALL_PASS" == "true" && "$SKIP_GUARDRAILS" == "false" ]]; then
  if [[ -f "${SCRIPT_DIR}/lint-clean-architecture.sh" ]]; then
    if ! run_step "CleanArchitecture" "bash '${SCRIPT_DIR}/lint-clean-architecture.sh' '$PROJECT_ROOT' --working-tree"; then
      OVERALL_PASS=false
    fi
  fi
  if [[ "$OVERALL_PASS" == "true" && -f "${SCRIPT_DIR}/scan-guardrails.sh" ]]; then
    if ! run_step "Guardrails" "bash '${SCRIPT_DIR}/scan-guardrails.sh' --path '$PROJECT_ROOT' --working-tree --skip-line-endings"; then
      OVERALL_PASS=false
    fi
  fi
fi

END_TIME=$(get_time_ns)
DURATION_MS=0
if [[ "$END_TIME" =~ ^[0-9]+$ && "$START_TIME" =~ ^[0-9]+$ && ${#END_TIME} -gt 10 ]]; then
  DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  if [[ "$OVERALL_PASS" == "true" ]]; then
    echo "{\"status\":\"pass\",\"duration_ms\":$DURATION_MS,\"bypassed_code_gate\":$BYPASSED_NO_CODE}"
  else
    ESCAPED_ERR=$(echo "$ERROR_LOG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    echo "{\"status\":\"fail\",\"failed_step\":\"$FAILED_STEP\",\"duration_ms\":$DURATION_MS,\"errors\":\"$ESCAPED_ERR\"}"
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
fi

if [[ "$OVERALL_PASS" == "false" ]]; then
  exit 1
fi
