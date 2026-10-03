#!/usr/bin/env bash
# Lints database migration scripts for naming conventions, duplicate versions, and dangerous DDL operations.
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

MIGRATION_FILES=()
for dir in "migrations" "db/migrations" "sql/migrations" "src" "prisma/migrations"; do
    if [ -d "$REPO_ROOT/$dir" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && MIGRATION_FILES+=("$f")
        done < <(find "$REPO_ROOT/$dir" -type f \( -name "*.sql" -o -name "*.cs" -o -name "*.py" \) -not -path "*/.git/*" -not -path "*/_agents/*" -not -path "*/.agents/*" -not -path "*/bin/*" -not -path "*/obj/*" -not -path "*/node_modules/*" 2>/dev/null | grep -E 'migration|\bup\b|\bdown\b|^[0-9]{3,}_|^V[0-9]+__' || true)
    fi
done

ERRORS=()
WARNINGS=()
declare -A SEEN_VERSIONS

for file in "${MIGRATION_FILES[@]}"; do
    base=$(basename "$file")

    # Check version prefix
    if [[ "$base" =~ ^([Vv]?[0-9]+)[_-] ]]; then
        ver="${BASH_REMATCH[1]}"
        ver=$(echo "$ver" | tr '[:lower:]' '[:upper:]')
        if [[ -n "${SEEN_VERSIONS[$ver]:-}" ]]; then
            ERRORS+=("Duplicate migration version detected: '$ver' in file '$base'")
        else
            SEEN_VERSIONS[$ver]=1
        fi
    fi

    # Check destructive SQL commands
    if [[ "$file" == *.sql ]]; then
        if grep -iqE '\bDROP\s+TABLE\b' "$file"; then
            WARNINGS+=("Destructive operation 'DROP TABLE' detected in '$base'")
        fi
        if grep -iqE '\bTRUNCATE(\s+TABLE)?\b' "$file"; then
            WARNINGS+=("Destructive operation 'TRUNCATE' detected in '$base'")
        fi
        if grep -iqE '\bALTER\s+TABLE\s+.*\bDROP\s+COLUMN\b' "$file"; then
            WARNINGS+=("Destructive operation 'DROP COLUMN' detected in '$base'")
        fi

        # Rollback symmetry check for .up.sql
        if [[ "$base" == *.up.sql ]]; then
            down_file="${file%.up.sql}.down.sql"
            if [ ! -f "$down_file" ]; then
                WARNINGS+=("Reversible migration missing matching down script: '$(basename "$down_file")' not found for '$base'")
            fi
        fi
    fi
done

STATUS="pass"
if [ ${#ERRORS[@]} -gt 0 ]; then
    STATUS="fail"
elif [ ${#WARNINGS[@]} -gt 0 ]; then
    STATUS="warning"
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"$STATUS\",\"migrations_count\":${#MIGRATION_FILES[@]},\"errors_count\":${#ERRORS[@]},\"warnings_count\":${#WARNINGS[@]}}"
else
    echo "Database Migration Lint Summary"
    echo "Status: $STATUS"
    echo "Migrations Scanned: ${#MIGRATION_FILES[@]}"
    echo "Errors: ${#ERRORS[@]}, Warnings: ${#WARNINGS[@]}"
fi

if [ "$STRICT" = true ] && [ "$STATUS" != "pass" ]; then
    exit 1
else
    exit 0
fi
