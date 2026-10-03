#!/usr/bin/env bash
# Generates or updates CHANGELOG.md deterministically from git commits.
set -euo pipefail

REPO_ROOT="$(pwd)"
VERSION=""
RELEASE_DATE="$(date +%Y-%m-%d)"
OUTPUT_FILE=""
PREPEND=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --date)
            RELEASE_DATE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --prepend)
            PREPEND=true
            shift
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Determine tag range
LATEST_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LATEST_TAG" ]; then
    COMMITS=$(git -C "$REPO_ROOT" log --oneline --no-merges 2>/dev/null || echo "")
else
    COMMITS=$(git -C "$REPO_ROOT" log "${LATEST_TAG}..HEAD" --oneline --no-merges 2>/dev/null || echo "")
fi

# 2. Determine version if not given
if [ -z "$VERSION" ]; then
    if [ -f "$SCRIPT_DIR/calculate-semver.sh" ]; then
        VERSION=$(bash "$SCRIPT_DIR/calculate-semver.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null | grep -o '"next_version": *"[^"]*"' | cut -d'"' -f4 || echo "v0.1.0")
    fi
    if [ -z "$VERSION" ]; then
        VERSION="v0.1.0"
    fi
fi

# 3. Categorize commits
BREAKING=()
FEATURES=()
FIXES=()
PERF=()
REFACTOR=()
DOCS=()
CHORES=()
COUNT=0

if [ -n "$COMMITS" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        COUNT=$((COUNT + 1))
        # strip hash
        msg="${line#* }"

        if echo "$msg" | grep -iqE "BREAKING CHANGE|!:"; then
            BREAKING+=("$msg")
        elif echo "$msg" | grep -qE "^feat(\([^)]+\))?:"; then
            clean=$(echo "$msg" | sed -E 's/^feat(\([^)]+\))?:[[:space:]]*//')
            FEATURES+=("$clean")
        elif echo "$msg" | grep -qE "^fix(\([^)]+\))?:"; then
            clean=$(echo "$msg" | sed -E 's/^fix(\([^)]+\))?:[[:space:]]*//')
            FIXES+=("$clean")
        elif echo "$msg" | grep -qE "^perf(\([^)]+\))?:"; then
            clean=$(echo "$msg" | sed -E 's/^perf(\([^)]+\))?:[[:space:]]*//')
            PERF+=("$clean")
        elif echo "$msg" | grep -qE "^refactor(\([^)]+\))?:"; then
            clean=$(echo "$msg" | sed -E 's/^refactor(\([^)]+\))?:[[:space:]]*//')
            REFACTOR+=("$clean")
        elif echo "$msg" | grep -qE "^docs(\([^)]+\))?:"; then
            clean=$(echo "$msg" | sed -E 's/^docs(\([^)]+\))?:[[:space:]]*//')
            DOCS+=("$clean")
        else
            clean=$(echo "$msg" | sed -E 's/^(chore|build|ci|test)(\([^)]+\))?:[[:space:]]*//')
            CHORES+=("$clean")
        fi
    done <<< "$COMMITS"
fi

# 4. Build Markdown
MD="## [$VERSION] - $RELEASE_DATE\n"

if [ ${#BREAKING[@]} -gt 0 ]; then
    MD+="\n### ⚠️ Breaking Changes\n"
    for item in "${BREAKING[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#FEATURES[@]} -gt 0 ]; then
    MD+="\n### Added\n"
    for item in "${FEATURES[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#FIXES[@]} -gt 0 ]; then
    MD+="\n### Fixed\n"
    for item in "${FIXES[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#PERF[@]} -gt 0 ]; then
    MD+="\n### Performance\n"
    for item in "${PERF[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#REFACTOR[@]} -gt 0 ]; then
    MD+="\n### Refactored\n"
    for item in "${REFACTOR[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#DOCS[@]} -gt 0 ]; then
    MD+="\n### Documentation\n"
    for item in "${DOCS[@]}"; do
        MD+="- $item\n"
    done
fi

if [ ${#CHORES[@]} -gt 0 ]; then
    MD+="\n### Maintenance & Chores\n"
    for item in "${CHORES[@]}"; do
        MD+="- $item\n"
    done
fi

# 5. Handle output file
if [ -n "$OUTPUT_FILE" ]; then
    if [[ "$OUTPUT_FILE" = /* ]]; then
        OUT_PATH="$OUTPUT_FILE"
    else
        OUT_PATH="$REPO_ROOT/$OUTPUT_FILE"
    fi

    if [ -f "$OUT_PATH" ] && [ "$PREPEND" = true ]; then
        EXISTING=$(cat "$OUT_PATH")
        if echo "$EXISTING" | grep -qE '^# Changelog'; then
            HEADER=$(echo "$EXISTING" | grep -m1 '^# Changelog')
            REST=$(echo "$EXISTING" | sed -e '1d')
            printf "%s\n\n%b\n\n%s\n" "$HEADER" "$MD" "$REST" > "$OUT_PATH"
        else
            printf "%b\n\n%s\n" "$MD" "$EXISTING" > "$OUT_PATH"
        fi
    else
        printf "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n%b\n" "$MD" > "$OUT_PATH"
    fi
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"version\":\"$VERSION\",\"release_date\":\"$RELEASE_DATE\",\"commits_analyzed\":$COUNT,\"breaking_count\":${#BREAKING[@]},\"features_count\":${#FEATURES[@]},\"fixes_count\":${#FIXES[@]}}"
else
    echo -e "$MD"
fi
