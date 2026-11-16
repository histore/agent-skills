#!/usr/bin/env bash
# Parses test coverage reports deterministically and verifies coverage thresholds.
set -euo pipefail

REPO_ROOT=""
THRESHOLD=80
REPORT_PATH=""
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
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --threshold=*)
            THRESHOLD="${1#*=}"
            shift
            ;;
        --report|--report-path)
            REPORT_PATH="$2"
            shift 2
            ;;
        --report=*|--report-path=*)
            REPORT_PATH="${1#*=}"
            shift
            ;;
        --json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            if [[ -z "$REPO_ROOT" && ! "$1" =~ ^- ]]; then
                REPO_ROOT="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(pwd)"
fi

FOUND_FILE=""
FORMAT="none"

if [ -n "$REPORT_PATH" ]; then
    if [[ "$REPORT_PATH" = /* ]]; then
        if [ -f "$REPORT_PATH" ]; then FOUND_FILE="$REPORT_PATH"; fi
    else
        if [ -f "$REPO_ROOT/$REPORT_PATH" ]; then FOUND_FILE="$REPO_ROOT/$REPORT_PATH"; fi
    fi
else
    # Scan for common reports (use basename matching; -name cannot contain '/')
    for pattern in "coverage.cobertura.xml" "cobertura.xml" "lcov.info" "coverage-summary.json" "tarpaulin-report.json"; do
        match=$(find "$REPO_ROOT" -maxdepth 4 -type f -name "$pattern" -not -path "*/.git/*" -not -path "*/_agents/*" -not -path "*/.agents/*" -not -path "*/node_modules/*" 2>/dev/null | head -1 || true)
        if [ -n "$match" ] && [ -f "$match" ]; then
            FOUND_FILE="$match"
            break
        fi
    done
fi

COVERAGE_FOUND=false
LINE_PCT=0
BRANCH_PCT="null"
STATUS="pass"
MESSAGE=""

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    COVERAGE_FOUND=true
    BASE=$(basename "$FOUND_FILE")

    if echo "$BASE" | grep -iq "cobertura.*\.xml$"; then
        FORMAT="cobertura"
        RATE=$(grep -o 'line-rate="[^"]*"' "$FOUND_FILE" | head -1 | cut -d'"' -f2 || echo "0")
        LINE_PCT=$(awk -v r="$RATE" 'BEGIN { printf "%.2f", r * 100 }')
        BRATE=$(grep -o 'branch-rate="[^"]*"' "$FOUND_FILE" | head -1 | cut -d'"' -f2 || true)
        if [ -n "$BRATE" ]; then
            BRANCH_PCT=$(awk -v r="$BRATE" 'BEGIN { printf "%.2f", r * 100 }')
        fi
    elif echo "$BASE" | grep -iq "lcov\.info$"; then
        FORMAT="lcov"
        LF=$(grep -o '^LF:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        LH=$(grep -o '^LH:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        if [ "$LF" -gt 0 ]; then
            LINE_PCT=$(awk -v h="$LH" -v f="$LF" 'BEGIN { printf "%.2f", (h/f)*100 }')
        fi
        BRF=$(grep -o '^BRF:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        BRH=$(grep -o '^BRH:[0-9]*' "$FOUND_FILE" | awk -F: '{s+=$2} END {print s+0}')
        if [ "$BRF" -gt 0 ]; then
            BRANCH_PCT=$(awk -v h="$BRH" -v f="$BRF" 'BEGIN { printf "%.2f", (h/f)*100 }')
        fi
    elif echo "$BASE" | grep -iq "coverage-summary\.json$"; then
        FORMAT="istanbul-json"
        if command -v python3 >/dev/null 2>&1; then
            read -r LINE_PCT BRANCH_PCT < <(python3 - "$FOUND_FILE" << 'PYEOF' 2>/dev/null | tr -d '\r' || echo "0 null"
import json, sys
d = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
tot = d.get('total', {})
lp = tot.get('lines', {}).get('pct', 0)
bp = tot.get('branches', {}).get('pct', None)
print(round(float(lp), 2), round(float(bp), 2) if bp is not None else 'null')
PYEOF
            )
        else
            LINE_PCT=$(grep -o '"pct": *[0-9.]*' "$FOUND_FILE" | head -1 | grep -o '[0-9.]*' || echo "0")
        fi
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

REPORT_JSON="null"
if [ -n "$FOUND_FILE" ]; then
    REL_REPORT="${FOUND_FILE#"${REPO_ROOT%/}"/}"
    REL_REPORT="${REL_REPORT//\\/\\\\}"
    REL_REPORT="${REL_REPORT//\"/\\\"}"
    REPORT_JSON="\"$REL_REPORT\""
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"$STATUS\",\"coverage_found\":$COVERAGE_FOUND,\"format\":\"$FORMAT\",\"report_file\":$REPORT_JSON,\"line_coverage_pct\":$LINE_PCT,\"branch_coverage_pct\":$BRANCH_PCT,\"threshold_pct\":$THRESHOLD,\"message\":\"$MESSAGE\"}"
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
