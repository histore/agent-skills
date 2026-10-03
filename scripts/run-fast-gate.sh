#!/usr/bin/env bash
# ==============================================================================
# Executes a Stage-1 deterministic Fast-Gate (build, test, lint) with log compaction.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(pwd)}"
TEST_FILTER=""
SKIP_LINT=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --json|-j)
      JSON_OUTPUT=true
      ;;
    --skip-lint)
      SKIP_LINT=true
      ;;
    --filter=*)
      TEST_FILTER="${arg#*=}"
      ;;
  esac
done

DETECT_SCRIPT="${SCRIPT_DIR}/detect-tech-stack.sh"
STACK="unknown"
BUILD_CMD=""
TEST_CMD=""
FILTER_SYNTAX=""
LINT_CMD=""

if [[ -f "$DETECT_SCRIPT" ]]; then
  STACK_JSON=$(bash "$DETECT_SCRIPT" "$PROJECT_ROOT" --json 2>/dev/null || echo '{}')
  if command -v python3 &>/dev/null; then
    eval $(python3 -c "
import json
try:
    d = json.loads('''$STACK_JSON''')
    print(f\"STACK='{d.get('stack', '')}'\")
    print(f\"BUILD_CMD='{d.get('build_cmd', '')}'\")
    print(f\"TEST_CMD='{d.get('test_cmd', '')}'\")
    print(f\"FILTER_SYNTAX='{d.get('test_filter_syntax', '')}'\")
    print(f\"LINT_CMD='{d.get('lint_cmd', '')}'\")
except Exception:
    pass
" 2>/dev/null || true)
  fi
fi

if [[ "$STACK" == "unknown" || -z "$BUILD_CMD" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo '{"status":"pass","message":"No executable stack detected; fast-gate bypassed","duration_ms":0}'
  else
    echo "Stage-1 Fast-Gate: Bypassed (no executable stack detected)"
  fi
  exit 0
fi

START_TIME=$(date +%s%N 2>/dev/null || date +%s)
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
    ERROR_LOG=$(grep -iE "error|failed|exception|assert|fatal" "$tmp_out" | head -n 15 || tail -n 10 "$tmp_out")
    rm -f "$tmp_out"
    return 1
  fi
  rm -f "$tmp_out"
  return 0
}

OVERALL_PASS=true

if ! run_step "Build" "$BUILD_CMD"; then
  OVERALL_PASS=false
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

END_TIME=$(date +%s%N 2>/dev/null || date +%s)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 2>/dev/null || 0 ))

if [[ "$JSON_OUTPUT" == "true" ]]; then
  if [[ "$OVERALL_PASS" == "true" ]]; then
    echo "{\"status\":\"pass\",\"duration_ms\":$DURATION_MS}"
  else
    ESCAPED_ERR=$(echo "$ERROR_LOG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    echo "{\"status\":\"fail\",\"failed_step\":\"$FAILED_STEP\",\"duration_ms\":$DURATION_MS,\"errors\":\"$ESCAPED_ERR\"}"
  fi
else
  if [[ "$OVERALL_PASS" == "true" ]]; then
    echo "Stage-1 Fast-Gate: PASS (${DURATION_MS}ms) - Zero errors"
  else
    echo "Stage-1 Fast-Gate: FAIL at step '$FAILED_STEP'"
    echo "$ERROR_LOG"
  fi
fi

if [[ "$OVERALL_PASS" == "false" ]]; then
  exit 1
fi
