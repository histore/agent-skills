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
            if [[ -z "$REPO_ROOT" && ! "$1" =~ ^- ]]; then
                REPO_ROOT="$1"
            fi
            shift
            ;;
    esac
done

TOTAL_VULNS=0
OVERALL_STATUS="pass"
AUDITS_COUNT=0
ECOSYSTEM_AUDITS=()

# 1. Cargo (Rust)
if [ -f "$REPO_ROOT/Cargo.toml" ] || [ -f "$REPO_ROOT/Cargo.lock" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v cargo-audit &>/dev/null || cargo audit --version &>/dev/null; then
        if cargo audit --version &>/dev/null; then
            AUDIT_OUT=$(cargo audit --json 2>/dev/null || true)
            VULN=0
            if echo "$AUDIT_OUT" | grep -q '"vulnerabilities"'; then
                VULN=$(echo "$AUDIT_OUT" | grep -o '"count": *[0-9]*' | head -1 | grep -o '[0-9]*' || echo 0)
                TOTAL_VULNS=$((TOTAL_VULNS + VULN))
                if [ "$VULN" -gt 0 ]; then OVERALL_STATUS="fail"; fi
            fi
            ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Rust (Cargo)\",\"tool\":\"cargo-audit\",\"status\":\"$([ "$VULN" -gt 0 ] && echo fail || echo pass)\",\"vulnerabilities_count\":$VULN}")
        fi
    else
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Rust (Cargo)\",\"tool\":\"cargo-audit\",\"status\":\"advisory\",\"vulnerabilities_count\":0}")
    fi
fi

# 2. .NET
if [ -n "$(find "$REPO_ROOT" -maxdepth 3 \( -name "*.csproj" -o -name "*.sln" \) 2>/dev/null | head -1)" ] || [ -f "$REPO_ROOT/Directory.Build.props" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v dotnet &>/dev/null; then
        DOTNET_OUT=$(dotnet list package --vulnerable --include-transitive 2>/dev/null || true)
        VULN=0
        if echo "$DOTNET_OUT" | grep -iqE "has the following vulnerable packages|has vulnerable packages"; then
            VULN=1
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\".NET (NuGet)\",\"tool\":\"dotnet list package --vulnerable\",\"status\":\"$([ "$VULN" -gt 0 ] && echo fail || echo pass)\",\"vulnerabilities_count\":$VULN}")
    fi
fi

# 3. npm (Node.js)
if [ -f "$REPO_ROOT/package.json" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v npm &>/dev/null; then
        NPM_OUT=$(npm audit --json 2>/dev/null || true)
        VULN=0
        if echo "$NPM_OUT" | grep -q '"vulnerabilities"'; then
            VULN=$(echo "$NPM_OUT" | grep -o '"total": *[0-9]*' | head -1 | grep -o '[0-9]*' || echo 0)
            TOTAL_VULNS=$((TOTAL_VULNS + VULN))
            if [ "$VULN" -gt 0 ]; then OVERALL_STATUS="fail"; fi
        fi
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Node.js (npm)\",\"tool\":\"npm audit\",\"status\":\"$([ "$VULN" -gt 0 ] && echo fail || echo pass)\",\"vulnerabilities_count\":$VULN}")
    fi
fi

# 4. Python
if [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/requirements.txt" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v pip-audit &>/dev/null; then
        PY_OUT=$(pip-audit -f json 2>/dev/null || true)
        VULN=0
        if echo "$PY_OUT" | grep -q '"vulns"'; then
            VULN=1
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Python\",\"tool\":\"pip-audit\",\"status\":\"$([ "$VULN" -gt 0 ] && echo fail || echo pass)\",\"vulnerabilities_count\":$VULN}")
    else
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Python\",\"tool\":\"pip-audit\",\"status\":\"advisory\",\"vulnerabilities_count\":0}")
    fi
fi

# 5. Go
if [ -f "$REPO_ROOT/go.mod" ]; then
    AUDITS_COUNT=$((AUDITS_COUNT + 1))
    if command -v govulncheck &>/dev/null; then
        VULN=0
        if ! govulncheck ./... &>/dev/null; then
            VULN=1
            TOTAL_VULNS=$((TOTAL_VULNS + 1))
            OVERALL_STATUS="fail"
        fi
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Go\",\"tool\":\"govulncheck\",\"status\":\"$([ "$VULN" -gt 0 ] && echo fail || echo pass)\",\"vulnerabilities_count\":$VULN}")
    else
        ECOSYSTEM_AUDITS+=("{\"ecosystem\":\"Go\",\"tool\":\"govulncheck\",\"status\":\"advisory\",\"vulnerabilities_count\":0}")
    fi
fi

if [ ${#ECOSYSTEM_AUDITS[@]} -eq 0 ]; then
    ECOSYSTEM_AUDITS+=('{"ecosystem":"None","tool":"none","status":"pass","vulnerabilities_count":0}')
fi

if [ "$JSON_OUTPUT" = true ]; then
    AUDITS_JSON=$(printf ",%s" "${ECOSYSTEM_AUDITS[@]}")
    AUDITS_JSON="[${AUDITS_JSON:1}]"
    echo "{\"status\":\"$OVERALL_STATUS\",\"audits_executed\":${#ECOSYSTEM_AUDITS[@]},\"total_vulnerabilities\":$TOTAL_VULNS,\"ecosystem_audits\":$AUDITS_JSON}"
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
