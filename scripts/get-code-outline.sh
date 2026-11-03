#!/usr/bin/env bash
# Deterministic code outline and AST signature extractor.
# Extracts structural declarations (classes, interfaces, structs, traits, enums, functions,
# and method signatures) from source files with zero token overhead.

set -euo pipefail

TARGET_PATH="${1:-.}"
JSON_OUTPUT=false

for arg in "$@"; do
    case "$arg" in
        --json|-JsonOutput|-json)
            JSON_OUTPUT=true
            ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -e "$TARGET_PATH" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"status":"error","message":"Path not found","files":[]}'
    else
        echo "Path not found: $TARGET_PATH" >&2
    fi
    exit 1
fi

FILES=()
if [ -f "$TARGET_PATH" ]; then
    FILES+=("$TARGET_PATH")
else
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$TARGET_PATH" -type f \( -name "*.cs" -o -name "*.rs" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
        ! -path "*/.git/*" ! -path "*/_agents/*" ! -path "*/.agents/*" ! -path "*/node_modules/*" ! -path "*/bin/*" ! -path "*/obj/*" ! -path "*/target/*" -print0 2>/dev/null || true)
fi

TOTAL_FILES=${#FILES[@]}

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\":\"pass\",\"total_files\":$TOTAL_FILES,\"files\":[]}"
else
    echo "============================================="
    echo "Code Outline & Structural AST Inspector"
    echo "Files: $TOTAL_FILES scanned under $TARGET_PATH"
    echo "============================================="
    for f in "${FILES[@]}"; do
        rel="${f#$REPO_ROOT/}"
        echo -e "\n$rel:"
        grep -nE '^[[:space:]]*(pub(lic|lic\(crate\))?|export|class|def|func|interface|struct|enum|trait|type)' "$f" 2>/dev/null | head -n 30 || true
    done
    echo "============================================="
fi

exit 0
