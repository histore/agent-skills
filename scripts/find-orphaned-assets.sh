#!/usr/bin/env bash
# Identifies unreferenced media assets and orphaned modular documentation files deterministically.
set -euo pipefail

REPO_ROOT=""
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

if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(pwd)"
fi

ORPHANED_ASSETS=()
ORPHANED_DOCS=()
ASSET_COUNT=0

# 1. Collect asset files
while IFS= read -r asset; do
    [ -z "$asset" ] && continue
    ASSET_COUNT=$((ASSET_COUNT + 1))
    base=$(basename "$asset")
    # Search for reference across repository
    found=$(grep -rFl --exclude-dir=".git" --exclude-dir="_agents" --exclude-dir=".agents" --exclude-dir="bin" --exclude-dir="obj" --exclude-dir="node_modules" --exclude-dir="target" "$base" "$REPO_ROOT" 2>/dev/null | grep -v "$asset" | head -1 || true)
    if [ -z "$found" ]; then
        rel="${asset#$REPO_ROOT/}"
        ORPHANED_ASSETS+=("$rel")
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.svg" -o -name "*.gif" -o -name "*.webp" -o -name "*.ico" \) -not -path "*/.git/*" -not -path "*/_agents/*" -not -path "*/.agents/*" -not -path "*/node_modules/*" -not -path "*/bin/*" -not -path "*/obj/*" -not -path "*/target/*" 2>/dev/null || true)

# 2. Check modular docs
ARCH_INDEX="$REPO_ROOT/ARCHITECTURE.md"
REQ_INDEX="$REPO_ROOT/REQUIREMENTS.md"

if [ -d "$REPO_ROOT/docs/architecture/modules" ] && [ -f "$ARCH_INDEX" ]; then
    while IFS= read -r mf; do
        [ -z "$mf" ] && continue
        base=$(basename "$mf")
        if ! grep -q "$base" "$ARCH_INDEX"; then
            rel="${mf#$REPO_ROOT/}"
            ORPHANED_DOCS+=("$rel")
        fi
    done < <(find "$REPO_ROOT/docs/architecture/modules" -type f -name "*.md" 2>/dev/null || true)
fi

if [ -d "$REPO_ROOT/docs/requirements/modules" ] && [ -f "$REQ_INDEX" ]; then
    while IFS= read -r rf; do
        [ -z "$rf" ] && continue
        base=$(basename "$rf")
        if ! grep -q "$base" "$REQ_INDEX"; then
            rel="${rf#$REPO_ROOT/}"
            ORPHANED_DOCS+=("$rel")
        fi
    done < <(find "$REPO_ROOT/docs/requirements/modules" -type f -name "*.md" 2>/dev/null || true)
fi

oa_json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

oa_json_arr() {
    local out="" item
    for item in "$@"; do
        [ -z "$item" ] && continue
        [ -n "$out" ] && out+=","
        out+="\"$(oa_json_esc "$item")\""
    done
    printf '[%s]' "$out"
}

TOTAL_ORPHANS=$((${#ORPHANED_ASSETS[@]} + ${#ORPHANED_DOCS[@]}))
STATUS="pass"
if [ "$TOTAL_ORPHANS" -gt 0 ]; then
    STATUS="warning"
fi

if [ "$TOTAL_ORPHANS" -eq 0 ]; then
    MSG="No orphaned assets or modular documentation files detected."
else
    MSG="Found $TOTAL_ORPHANS orphaned file(s)."
fi

if [ "$JSON_OUTPUT" = true ]; then
    ASSETS_JSON=$(oa_json_arr "${ORPHANED_ASSETS[@]:-}")
    DOCS_JSON=$(oa_json_arr "${ORPHANED_DOCS[@]:-}")
    echo "{\"status\":\"$STATUS\",\"assets_scanned\":$ASSET_COUNT,\"orphaned_assets\":$ASSETS_JSON,\"orphaned_docs\":$DOCS_JSON,\"total_orphaned_count\":$TOTAL_ORPHANS,\"message\":\"$(oa_json_esc "$MSG")\"}"
else
    echo "Orphaned Assets & Modular Docs Audit Summary"
    echo "Status: $STATUS"
    echo "Assets Scanned: $ASSET_COUNT"
    echo "Total Orphaned: $TOTAL_ORPHANS"
fi

if [ "$STRICT" = true ] && [ "$TOTAL_ORPHANS" -gt 0 ]; then
    exit 1
else
    exit 0
fi
