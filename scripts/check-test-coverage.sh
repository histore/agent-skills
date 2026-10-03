#!/usr/bin/env bash
# Parses test coverage reports deterministically and verifies coverage thresholds.
set -euo pipefail

REPO_ROOT="$(pwd)"
THRESHOLD=80
REPORT_PATH=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --report)
            REPORT_PATH="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

FOUND_FILE=""
FORMAT="none"

if [ -n "$REPORT_PATH" ]; then
    if [[ "$REPORT_PATH" = /* ]]; then
        if [ -f "$REPORT_PATH" ]; then FOUND_FILE="$REPORT_PATH"; fi
    else
        if [ -f "$REPO_ROOT/$REPORT_PATH" ]; then FOUND_FILE="$REPO_ROOT/$REPORT_PATH"; fi
    fi
else
    # Scan for common reports
    for pattern in "coverage.cobertura.xml" "cobertura.xml" "coverage/lcov.info" "lcov.info" "coverage/coverage-summary.json"; do
        match=$(find "$REPO_ROOT" -maxdepth 4 -name "$pattern" -not -path "*/.git/*" -not -path "*/_agents/*" -not -path "*/.agents/*" 2>/dev/null | head -1 || true)
        if [ -n "$match" ] && [ -f "$match" ]; then
            FOUND_FILE="$match"
            break
        fi
    done
fi

COVERAGE_FOUND=false
LINE_PCT=0
STATUS="pass"
MESSAGE=""

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    COVERAGE_FOUND=true
    BASE=$(basename "$FOUND_FILE")

    if echo "$BASE" | grep -iq "cobertura.*\.xml$"; then
        FORMAT="cobertura"
        RATE=$(grep -o 'line-rate="[^"]*"' "$FOUND_FILE" | head -1 | cut -d'"' -f2 || echo "0")
        LINE_PCT=$(awk -v r="$RATE" 'BEGIN { printf "%.2f", r * 100 }')
    elif echo "$BASE" | grep -iq "lcov\.info$"; then
        FORMAT="lcov"
        LF=$(grep -o '^LF:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        LH=$(grep -o '^LH:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        if [ "$LF" -gt 0 ]; then
            LINE_PCT=$(awk -v h="$LH" -v f="$LF" 'BEGIN { printf "%.2f", (h/f)*100 }')
        fi
    elif echo "$BASE" | grep -iq "coverage-summary\.json$"; then
        FORMAT="istanbul-json"
        LINE_PCT=$(grep -o '"pct": *[0-9.]*' "$FOUND_FILE" | head -1 | grep -o '[0-9.]*' || echo "0")
    fi

    # Compare with threshold
    IS_BELOW=$(awk -v p="$LINE_PCT" -v t="$THRESHOLD" 'BEGIN { print (p < t) ? 1 : 0 }')
    if [ "$IS_BELOW" -eq 1 ]; then
        STATUS="fail"
        MESSAGE="Line coverage ($LINE_PCT%) is below the required threshold ($THRESHOLD%)."
    else
        STATUS="pass"
        MESSAGE="Line coverage ($LINE_PCT%) meets or exceeds the required threshold ($THRESHOLD%)."
    fi
else
    STATUS="pass"
    MESSAGE="No test coverage artifacts found (cobertura, lcov, or coverage-summary.json)."
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"$STATUS\",\"coverage_found\":$COVERAGE_FOUND,\"format\":\"$FORMAT\",\"line_coverage_pct\":$LINE_PCT,\"threshold_pct\":$THRESHOLD,\"message\":\"$MESSAGE\"}"
else
    echo "Test Coverage Check Summary"
    echo "Status: $STATUS"
    echo "Coverage Found: $COVERAGE_FOUND"
    if [ "$COVERAGE_FOUND" = true ]; then
        echo "Line Coverage: $LINE_PCT% (Threshold: $THRESHOLD%)"
    fi
    echo "Message: $MESSAGE"
fi

if [ "$STATUS" != "pass" ]; then
    exit 1
else
    exit 0
fi
