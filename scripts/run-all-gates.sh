#!/usr/bin/env bash
# ==============================================================================
# Unified Quality Gates Runner (macOS & Linux)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
STAGED_ONLY=false
FAST=false
FIX=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --staged)
      STAGED_ONLY=true
      ;;
    --fast)
      FAST=true
      ;;
    --fix|-f)
      FIX=true
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
    -*)
      ;;
    *)
      if [[ -z "$REPO_ROOT" ]]; then
        REPO_ROOT="$arg"
      fi
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

FAILED_GATES=0
TOTAL_GATES=0
GATES_JSON=()

get_time_ms() {
  if command -v python3 &>/dev/null; then
    python3 -c 'import time; print(int(time.time()*1000))'
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

TOTAL_START_MS=$(get_time_ms)

run_gate() {
  local name="$1"
  local script_name="$2"
  shift 2
  local script_path="${SCRIPT_DIR}/${script_name}"

  TOTAL_GATES=$((TOTAL_GATES + 1))

  if [[ ! -f "$script_path" ]]; then
    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo -e "  \033[90m[SKIP] ${name}\033[0m"
    fi
    GATES_JSON+=("{\"Gate\":\"$(json_esc "$name")\",\"Status\":\"skipped\",\"DurationMs\":0,\"Message\":\"Script '${script_name}' not found\",\"Output\":\"\"}")
    return 0
  fi

  local g_start g_end g_dur output
  g_start=$(get_time_ms)
  if output=$(bash "$script_path" "$@" 2>&1); then
    g_end=$(get_time_ms)
    g_dur=$((g_end - g_start))
    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo -e "  \033[32m[PASS] ${name}\033[0m"
    fi
    GATES_JSON+=("{\"Gate\":\"$(json_esc "$name")\",\"Status\":\"pass\",\"DurationMs\":${g_dur},\"Message\":\"Passed cleanly\",\"Output\":\"$(json_esc "$output")\"}")
  else
    local rc=$?
    g_end=$(get_time_ms)
    g_dur=$((g_end - g_start))
    FAILED_GATES=$((FAILED_GATES + 1))
    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo -e "  \033[31m[FAIL] ${name}\033[0m"
      if [[ -n "$output" ]]; then
        echo -e "         \033[33mErrors:\033[0m"
        echo "$output" | tail -n 10 | sed 's/^/         /'
      fi
    fi
    GATES_JSON+=("{\"Gate\":\"$(json_esc "$name")\",\"Status\":\"fail\",\"DurationMs\":${g_dur},\"Message\":\"Reported errors (exit code ${rc})\",\"Output\":\"$(json_esc "$output")\"}")
  fi
}

if [[ "$JSON_OUTPUT" != "true" ]]; then
  echo "============================================="
  echo "Unified Quality Gates Runner"
  echo "Target: ${REPO_ROOT}"
  echo "============================================="
fi

# 1. Guardrails
GUARD_ARGS=("$REPO_ROOT")
[[ "$STAGED_ONLY" == "true" ]] && GUARD_ARGS+=("--staged")
[[ "$FIX" == "true" ]] && GUARD_ARGS+=("--fix")
run_gate "Guardrails (Secrets/CRLF/SafeRust)" "scan-guardrails.sh" "${GUARD_ARGS[@]}"

# 2. Clean Architecture
ARCH_ARGS=("$REPO_ROOT")
[[ "$STAGED_ONLY" == "true" ]] && ARCH_ARGS+=("--staged")
run_gate "Clean Architecture Boundaries" "lint-clean-architecture.sh" "${ARCH_ARGS[@]}"

# 3. Documentation & Links
run_gate "Documentation & Link Integrity" "lint-docs.sh" "$REPO_ROOT"

# 4. Requirements (fast-path skip if no requirements exist)
if [[ -f "${REPO_ROOT}/REQUIREMENTS.md" || -d "${REPO_ROOT}/docs/requirements/modules" ]]; then
  run_gate "Requirements Scoped IDs & Non-Duplication" "lint-requirements.sh" "$REPO_ROOT"
else
  TOTAL_GATES=$((TOTAL_GATES + 1))
  if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -e "  \033[32m[PASS] Requirements Scoped IDs & Non-Duplication\033[0m"
  fi
  GATES_JSON+=("{\"Gate\":\"Requirements Scoped IDs & Non-Duplication\",\"Status\":\"pass\",\"DurationMs\":0,\"Message\":\"No requirements files present (fast-path pass)\",\"Output\":\"\"}")
fi

# 5. Fast-Gate (skip guardrails/arch since Gates 1 & 2 already ran them)
if [[ "$FAST" != "true" ]]; then
  run_gate "Stage-1 Fast-Gate (Build & Tests)" "run-fast-gate.sh" "$REPO_ROOT" "--force" "--skip-guardrails"
fi

TOTAL_END_MS=$(get_time_ms)
TOTAL_DUR_MS=$((TOTAL_END_MS - TOTAL_START_MS))
PASSED_GATES=$((TOTAL_GATES - FAILED_GATES))

if [[ "$JSON_OUTPUT" == "true" ]]; then
  STATUS="pass"
  [[ $FAILED_GATES -gt 0 ]] && STATUS="fail"
  GATES_JOINED=$(printf ",%s" "${GATES_JSON[@]}")
  GATES_JOINED="${GATES_JOINED:1}"
  echo "{\"status\":\"${STATUS}\",\"total_duration_ms\":${TOTAL_DUR_MS},\"passed_gates\":${PASSED_GATES},\"failed_gates\":${FAILED_GATES},\"gates\":[${GATES_JOINED}]}"
else
  echo "============================================="
  if [[ $FAILED_GATES -eq 0 ]]; then
    echo -e "\033[32mUnified Gates Status: PASS (${PASSED_GATES}/${TOTAL_GATES} gates passed)\033[0m"
  else
    echo -e "\033[31mUnified Gates Status: FAIL (${FAILED_GATES}/${TOTAL_GATES} gates failed)\033[0m"
  fi
  echo "============================================="
fi

if [[ $FAILED_GATES -gt 0 ]]; then
  exit 1
fi
