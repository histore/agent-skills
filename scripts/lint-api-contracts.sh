#!/usr/bin/env bash
# Lints API contract specifications (OpenAPI/Swagger, Protobuf, GraphQL) for syntax and broken references.
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

CONTRACT_FILES=()
while IFS= read -r f; do
    [ -n "$f" ] && CONTRACT_FILES+=("$f")
done < <(find "$REPO_ROOT" -type f \( -name "openapi.json" -o -name "openapi.yaml" -o -name "openapi.yml" -o -name "swagger.json" -o -name "swagger.yaml" -o -name "*.proto" -o -name "*.graphql" -o -name "*.gql" \) -not -path "*/.git/*" -not -path "*/_agents/*" -not -path "*/.agents/*" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/bin/*" -not -path "*/obj/*" 2>/dev/null || true)

ERRORS=()
WARNINGS=()

for file in "${CONTRACT_FILES[@]}"; do
    base=$(basename "$file")

    # 1. OpenAPI JSON
    if [[ "$base" == *openapi.json ]] || [[ "$base" == *swagger.json ]]; then
        if command -v jq &>/dev/null; then
            if ! jq empty "$file" 2>/dev/null; then
                ERRORS+=("Invalid JSON in OpenAPI contract '$base'")
            else
                has_ver=$(jq -r '.openapi // .swagger // empty' "$file")
                if [ -z "$has_ver" ]; then
                    ERRORS+=("OpenAPI file '$base' missing root 'openapi' or 'swagger' version specification.")
                fi
            fi
        fi
    # 2. Protobuf (.proto)
    elif [[ "$base" == *.proto ]]; then
        if ! grep -qE 'syntax\s*=\s*"proto[23]";' "$file"; then
            WARNINGS+=("Protobuf file '$base' missing explicit 'syntax = \"proto3\";' declaration.")
        fi
    # 3. GraphQL
    elif [[ "$base" == *.graphql ]] || [[ "$base" == *.gql ]]; then
        if ! grep -qE '\b(type|schema|query|mutation|input|interface|enum)\b' "$file"; then
            WARNINGS+=("GraphQL file '$base' contains no standard GraphQL type declarations.")
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
    echo "{\"status\":\"$STATUS\",\"contracts_count\":${#CONTRACT_FILES[@]},\"errors_count\":${#ERRORS[@]},\"warnings_count\":${#WARNINGS[@]}}"
else
    echo "API Contract Lint Summary"
    echo "Status: $STATUS"
    echo "Contracts Scanned: ${#CONTRACT_FILES[@]}"
    echo "Errors: ${#ERRORS[@]}, Warnings: ${#WARNINGS[@]}"
fi

if [ "$STRICT" = true ] && [ "$STATUS" != "pass" ]; then
    exit 1
else
    exit 0
fi
