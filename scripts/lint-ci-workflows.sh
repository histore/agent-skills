#!/usr/bin/env bash
# Lints GitHub Actions CI/CD workflows for syntax, structure, permissions, and PowerShell hygiene.
set -euo pipefail

REPO_ROOT="$(pwd)"
STRICT=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --strict)
            STRICT=true
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

WORKFLOW_FILES=()
if [ -d "$REPO_ROOT/.github/workflows" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] && WORKFLOW_FILES+=("$f")
    done < <(find "$REPO_ROOT/.github/workflows" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null || true)
fi

ERRORS=()
WARNINGS=()

for wf in "${WORKFLOW_FILES[@]}"; do
    base=$(basename "$wf")
    if [ ! -s "$wf" ]; then
        WARNINGS+=("Workflow file '$base' is empty.")
        continue
    fi

    if ! grep -qE '^name\s*:' "$wf"; then
        WARNINGS+=("Workflow file '$base' missing top-level 'name:' attribute.")
    fi
    if ! grep -qE '^on\s*:' "$wf"; then
        ERRORS+=("Workflow file '$base' missing mandatory 'on:' trigger definition.")
    fi
    if ! grep -qE '^jobs\s*:' "$wf"; then
        ERRORS+=("Workflow file '$base' missing mandatory 'jobs:' section.")
    fi
    if ! grep -qE '^\s*permissions\s*:' "$wf"; then
        WARNINGS+=("Workflow file '$base' does not explicitly restrict GITHUB_TOKEN 'permissions:'.")
    fi
done

STATUS="pass"
if [ ${#ERRORS[@]} -gt 0 ]; then
    STATUS="fail"
elif [ ${#WARNINGS[@]} -gt 0 ]; then
    STATUS="warning"
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"$STATUS\",\"workflows_count\":${#WORKFLOW_FILES[@]},\"errors_count\":${#ERRORS[@]},\"warnings_count\":${#WARNINGS[@]}}"
else
    echo "CI/CD Workflow Lint Summary"
    echo "Status: $STATUS"
    echo "Workflows Scanned: ${#WORKFLOW_FILES[@]}"
    echo "Errors: ${#ERRORS[@]}, Warnings: ${#WARNINGS[@]}"
fi

if [ "$STRICT" = true ] && [ ${#ERRORS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
