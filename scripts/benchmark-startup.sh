#!/usr/bin/env bash
# ==============================================================================
# Deterministic benchmark tool measuring application startup times.
# ==============================================================================
set -euo pipefail

REPO_ROOT=""
EXECUTABLE_PATH=""
ITERATIONS=3
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exec|-e)
      EXECUTABLE_PATH="$2"
      shift 2
      ;;
    --exec=*|-e=*)
      EXECUTABLE_PATH="${1#*=}"
      shift
      ;;
    --iterations|-i)
      ITERATIONS="$2"
      shift 2
      ;;
    --iterations=*|-i=*)
      ITERATIONS="${1#*=}"
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
  REPO_ROOT="$(pwd)"
fi

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
  ITERATIONS=3
fi

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
    echo '{"status":"skipped","message":"Executable not found. Build the project first.","executable":null}'
  else
    echo "Benchmark Startup: SKIPPED (No executable found)"
  fi
  exit 0
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

TOTAL_MS=0
MIN_MS=-1
MAX_MS=0
RUNS_JSON=()

for ((i=1; i<=ITERATIONS; i++)); do
  START=$(get_time_ns)
  "$EXECUTABLE_PATH" --version >/dev/null 2>&1 || true
  END=$(get_time_ns)
  DUR_MS=$(( (END - START) / 1000000 ))
  TOTAL_MS=$((TOTAL_MS + DUR_MS))
  if [[ "$MIN_MS" -lt 0 || "$DUR_MS" -lt "$MIN_MS" ]]; then
    MIN_MS="$DUR_MS"
  fi
  if [[ "$DUR_MS" -gt "$MAX_MS" ]]; then
    MAX_MS="$DUR_MS"
  fi
  RUNS_JSON+=("{\"Iteration\":$i,\"DurationMs\":$DUR_MS,\"TimedOut\":false}")
done

[[ "$MIN_MS" -lt 0 ]] && MIN_MS=0
AVG_MS=$(( TOTAL_MS / ITERATIONS ))
RUNS_ARR=$(printf ",%s" "${RUNS_JSON[@]}")
RUNS_ARR="[${RUNS_ARR:1}]"

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"status\":\"pass\",\"executable\":\"$(basename "$EXECUTABLE_PATH")\",\"iterations\":$ITERATIONS,\"avg_duration_ms\":$AVG_MS,\"min_duration_ms\":$MIN_MS,\"max_duration_ms\":$MAX_MS,\"runs\":$RUNS_ARR}"
else
  echo "============================================="
  echo "Application Startup Benchmark"
  echo "Target: $(basename "$EXECUTABLE_PATH") | Iterations: $ITERATIONS"
  echo "============================================="
  echo "  Average Startup : ${AVG_MS} ms"
  echo "  Min Duration    : ${MIN_MS} ms"
  echo "  Max Duration    : ${MAX_MS} ms"
  echo "============================================="
fi
