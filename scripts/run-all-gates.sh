#!/usr/bin/env bash
# ==============================================================================
# Unified Quality Gates Runner (macOS & Linux)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${1:-$(pwd)}"
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
  esac
done

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
  fi
fi

FAILED_GATES=0
TOTAL_GATES=0

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
    return 0
  fi

  if bash "$script_path" "$@" >/dev/null 2>&1; then
    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo -e "  \033[32m[PASS] ${name}\033[0m"
    fi
  else
    FAILED_GATES=$((FAILED_GATES + 1))
    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo -e "  \033[31m[FAIL] ${name}\033[0m"
    fi
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
run_gate "Clean Architecture Boundaries" "lint-clean-architecture.sh" "$REPO_ROOT"

# 3. Documentation & Links
run_gate "Documentation & Link Integrity" "lint-docs.sh" "$REPO_ROOT"

# 4. Requirements
run_gate "Requirements Scoped IDs & Integrity" "lint-requirements.sh" "$REPO_ROOT"

# 5. Fast-Gate
if [[ "$FAST" != "true" ]]; then
  run_gate "Stage-1 Fast-Gate (Build & Tests)" "run-fast-gate.sh" "$REPO_ROOT"
fi

PASSED_GATES=$((TOTAL_GATES - FAILED_GATES))

if [[ "$JSON_OUTPUT" == "true" ]]; then
  STATUS="pass"
  [[ $FAILED_GATES -gt 0 ]] && STATUS="fail"
  echo "{\"status\":\"${STATUS}\",\"total_gates\":${TOTAL_GATES},\"passed\":${PASSED_GATES},\"failed\":${FAILED_GATES}}"
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
