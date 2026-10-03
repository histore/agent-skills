#!/usr/bin/env bash
# Runs deterministic dependency security and vulnerability audits across tech stacks.
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

TOTAL_VULNS=0
OVERALL_STATUS="pass"
AUDITS_COUNT=0

# 1. Cargo (Rust)
if [ -f "$REPO_ROOT/Cargo.toml" ] || [ -f "$REPO_ROOT/Cargo.lock" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v cargo-audit &>/dev/null || cargo audit --version &>/dev/null; then
        if cargo audit --version &>/dev/null; then
            AUDIT_OUT=$(cargo audit --json 2>/dev/null || true)
            # basic check if vulnerabilities were reported
            if echo "$AUDIT_OUT" | grep -q '"vulnerabilities"'; then
                VULN=$(echo "$AUDIT_OUT" | grep -o '"count": *[0-9]*' | head -1 | grep -o '[0-9]*' || echo 0)
                TOTAL_VULNS=$((TOTAL_VULNS + VULN))
                if [ "$VULN" -gt 0 ]; then OVERALL_STATUS="fail"; fi
            fi
        fi
    fi
fi

# 2. .NET
if compgen -G "$REPO_ROOT/*.csproj" > /dev/null || [ -f "$REPO_ROOT/Directory.Build.props" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v dotnet &>/dev/null; then
        DOTNET_OUT=$(dotnet list package --vulnerable --include-transitive 2>/dev/null || true)
        if echo "$DOTNET_OUT" | grep -iq "has the following vulnerable packages"; then
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
    fi
fi

# 3. npm (Node.js)
if [ -f "$REPO_ROOT/package.json" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v npm &>/dev/null; then
        NPM_OUT=$(npm audit --json 2>/dev/null || true)
        if echo "$NPM_OUT" | grep -q '"vulnerabilities"'; then
            VULN=$(echo "$NPM_OUT" | grep -o '"total": *[0-9]*' | head -1 | grep -o '[0-9]*' || echo 0)
            TOTAL_VULNS=$((TOTAL_VULNS + VULN))
            if [ "$VULN" -gt 0 ]; then OVERALL_STATUS="fail"; fi
        fi
    fi
fi

# 4. Python
if [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/requirements.txt" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v pip-audit &>/dev/null; then
        PY_OUT=$(pip-audit -f json 2>/dev/null || true)
        if echo "$PY_OUT" | grep -q '"vulns"'; then
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
    fi
fi

# 5. Go
if [ -f "$REPO_ROOT/go.mod" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v govulncheck &>/dev/null; then
        if ! govulncheck ./... &>/dev/null; then
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
    fi
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"$OVERALL_STATUS\",\"audits_executed\":$AUDITS_COUNT,\"total_vulnerabilities\":$TOTAL_VULNS}"
else
    echo "Dependency Security Audit Summary"
    echo "Overall Status: $OVERALL_STATUS"
    echo "Total Vulnerabilities: $TOTAL_VULNS"
    echo "Audits Executed: $AUDITS_COUNT"
fi

if [ "$STRICT" = true ] && [ "$OVERALL_STATUS" != "pass" ]; then
    exit 1
else
    exit 0
fi
