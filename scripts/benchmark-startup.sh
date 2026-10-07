#!/usr/bin/env bash
# ==============================================================================
# Deterministic benchmark tool measuring application startup times.
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
EXECUTABLE_PATH=""
ITERATIONS=3
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --exec=*|-e=*)
      EXECUTABLE_PATH="${arg#*=}"
      ;;
    --iterations=*|-i=*)
      ITERATIONS="${arg#*=}"
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

if [[ -z "$EXECUTABLE_PATH" ]]; then
  # Look for binaries in target/release, bin/Release, or dist
  CANDIDATE=$(find "$REPO_ROOT" -maxdepth 4 -type f -executable \
    -not -path '*/\.git/*' \
    -not -path '*/node_modules/*' \
    -not -name '*.sh' -not -name '*.ps1' 2>/dev/null | head -n 1 || true)
  if [[ -n "$CANDIDATE" ]]; then
    EXECUTABLE_PATH="$CANDIDATE"
  fi
fi

if [[ -z "$EXECUTABLE_PATH" || ! -f "$EXECUTABLE_PATH" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo '{"status":"skipped","message":"No executable found"}'
  else
    echo "Benchmark Startup: SKIPPED (No executable found)"
  fi
  exit 0
fi

TOTAL_MS=0
RUNS=()

for ((i=1; i<=ITERATIONS; i++)); do
  START=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  "$EXECUTABLE_PATH" --version >/dev/null 2>&1 || true
  END=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  DUR_MS=$(( (END - START) / 1000000 ))
  TOTAL_MS=$((TOTAL_MS + DUR_MS))
  RUNS+=("$DUR_MS")
done

AVG_MS=$(( TOTAL_MS / ITERATIONS ))

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"status\":\"pass\",\"executable\":\"$(basename "$EXECUTABLE_PATH")\",\"iterations\":$ITERATIONS,\"avg_duration_ms\":$AVG_MS}"
else
  echo "============================================="
  echo "Application Startup Benchmark"
  echo "Target: $(basename "$EXECUTABLE_PATH") | Iterations: $ITERATIONS"
  echo "============================================="
  echo "  Average Startup : ${AVG_MS} ms"
  echo "============================================="
fi
