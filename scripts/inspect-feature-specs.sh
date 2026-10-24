#!/usr/bin/env bash
# inspect-feature-specs.sh - Inspects, queries, and scaffolds modular living feature specifications with zero token overhead.
set -euo pipefail

REPO_ROOT=""
ACTION="list"
FILTER_PHASE=""
FILTER_ID=""
NEW_TITLE=""
NEW_SCOPE="CORE"
NEW_RELEASE="v0.1.0"
JSON_OUTPUT=0
CHECK_DRIFT=0
UPDATE_STATE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root|--RepoRoot|-RepoRoot)
            REPO_ROOT="$2"
            shift 2
            ;;
        --list|-List|-l)
            ACTION="list"
            shift
            ;;
        --phase|-Phase|-p)
            FILTER_PHASE="$2"
            shift 2
            ;;
        --id|-Id|-i)
            FILTER_ID="$2"
            shift 2
            ;;
        --new|-New|-n)
            ACTION="new"
            shift
            ;;
        --title|-Title|-t)
            NEW_TITLE="$2"
            shift 2
            ;;
        --scope|-Scope|-s)
            NEW_SCOPE="$2"
            shift 2
            ;;
        --target-release|-TargetRelease|-r)
            NEW_RELEASE="$2"
            shift 2
            ;;
        --check-drift|-CheckDrift|-d)
            CHECK_DRIFT=1
            shift
            ;;
        --update-state|-UpdateState|-u)
            UPDATE_STATE=1
            shift
            ;;
        --json|-JsonOutput|-j)
            JSON_OUTPUT=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(pwd)"
fi

FEATURES_DIR="$REPO_ROOT/docs/features"
ROADMAP_FILE="$REPO_ROOT/docs/ROADMAP.md"
STATE_FILE="$REPO_ROOT/docs/.spec-state.json"

# Template resolution
TEMPLATE_PATH=""
for t in "$REPO_ROOT/docs/templates/FEATURE_SPEC_TEMPLATE.md" \
         "$REPO_ROOT/_agents/docs/templates/FEATURE_SPEC_TEMPLATE.md" \
         "$REPO_ROOT/.agents/docs/templates/FEATURE_SPEC_TEMPLATE.md"; do
    if [ -f "$t" ]; then
        TEMPLATE_PATH="$t"
        break
    fi
done

# Action: Scaffolding a new feature
if [ "$ACTION" = "new" ]; then
    if [ -z "$FILTER_ID" ]; then
        echo "Error: -Id is required when creating a new feature specification." >&2
        exit 1
    fi
    if [ -z "$NEW_TITLE" ]; then
        NEW_TITLE="Feature $FILTER_ID"
    fi
    PHASE="${FILTER_PHASE:-1}"

    SLUG=$(echo "$NEW_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-zA-Z0-9]+/-/g' | sed -E 's/^-+|-+$//g')
    FILE_NAME="${FILTER_ID}-${SLUG}.md"
    mkdir -p "$FEATURES_DIR"
    TARGET_FILE="$FEATURES_DIR/$FILE_NAME"

    if [ -f "$TARGET_FILE" ]; then
        echo "Error: Feature file already exists: $TARGET_FILE" >&2
        exit 1
    fi

    if [ -n "$TEMPLATE_PATH" ] && [ -f "$TEMPLATE_PATH" ]; then
        sed -e "s/FEAT-<SCOPE>-XXX/$FILTER_ID/g" \
            -e "s/<FEAT-ID>/$FILTER_ID/g" \
            -e "s/<Feature Title>/$NEW_TITLE/g" \
            -e "s/<SCOPE>/$NEW_SCOPE/g" \
            -e "s/<PHASE>/$PHASE/g" \
            -e "s/phase: 1/phase: $PHASE/g" \
            -e "s/<TARGET_RELEASE>/$NEW_RELEASE/g" \
            -e "s/<e.g. v0.1.0>/$NEW_RELEASE/g" \
            -e "s/<slug>/$SLUG/g" \
            -e "s/<FILE_NAME>/$FILE_NAME/g" "$TEMPLATE_PATH" > "$TARGET_FILE"
    else
        cat <<EOF > "$TARGET_FILE"
# Feature Specification: $NEW_TITLE

\`\`\`yaml
---
id: $FILTER_ID
title: "$NEW_TITLE"
phase: $PHASE
status: PROPOSED
target_release: "$NEW_RELEASE"
scope: "$NEW_SCOPE"
depends_on: []
---
\`\`\`

> **Specification Path**: docs/features/$FILE_NAME
> **Parent Hub**: docs/ROADMAP.md

## 1. Executive Summary
Specification for $NEW_TITLE.

## 2. User Story
> **As a** user, **I want** capability, **so that** value.

## 3. Acceptance Criteria
- [ ] **AC-1**: **Given** condition, **When** action, **Then** result.
EOF
    fi

    ROADMAP_UPDATED=0
    if [ -f "$ROADMAP_FILE" ]; then
        REL_PATH="docs/features/$FILE_NAME"
        ROW="| Phase $PHASE | \`$FILTER_ID\` | $NEW_TITLE | PROPOSED | \`$NEW_SCOPE\` | [$REL_PATH]($REL_PATH) | \`$NEW_RELEASE\` |"
        echo "$ROW" >> "$ROADMAP_FILE"
        ROADMAP_UPDATED=1
    fi

    if [ "$JSON_OUTPUT" -eq 1 ]; then
        echo "{\"status\":\"created\",\"id\":\"$FILTER_ID\",\"title\":\"$NEW_TITLE\",\"phase\":\"$PHASE\",\"file\":\"docs/features/$FILE_NAME\",\"roadmap_updated\":$ROADMAP_UPDATED}"
    else
        echo "Created feature specification: docs/features/$FILE_NAME"
        if [ "$ROADMAP_UPDATED" -eq 1 ]; then
            echo "Appended feature entry to: docs/ROADMAP.md"
        fi
    fi
    exit 0
fi

# Parsing existing specs
SPECS_JSON="[]"
FOUND_COUNT=0

find_specs() {
    local dir="$1"
    if [ -d "$dir" ]; then
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            local rel_path="${f#$REPO_ROOT/}"
            local feat_id=$(grep -m1 -E '^[[:space:]]*id:' "$f" | sed -E 's/^[[:space:]]*id:[[:space:]]*["'\'']?([^"'\''[:space:]]+)["'\'']?.*$/\1/' || true)
            if [ -z "$feat_id" ]; then
                feat_id=$(basename "$f" .md)
            fi
            local feat_title=$(grep -m1 -E '^[[:space:]]*title:' "$f" | sed -E 's/^[[:space:]]*title:[[:space:]]*["'\'']?(.*)["'\'']?[[:space:]]*$/\1/' || true)
            if [ -z "$feat_title" ]; then
                feat_title=$(basename "$f" .md)
            fi
            local feat_phase=$(grep -m1 -E '^[[:space:]]*phase:' "$f" | sed -E 's/^[[:space:]]*phase:[[:space:]]*["'\'']?([^"'\''[:space:]]+)["'\'']?.*$/\1/' || true)
            if [ -z "$feat_phase" ]; then
                feat_phase="1"
            fi
            local feat_status=$(grep -m1 -E '^[[:space:]]*status:' "$f" | sed -E 's/^[[:space:]]*status:[[:space:]]*["'\'']?([A-Za-z_]+)["'\'']?.*$/\1/' || true)
            if [ -z "$feat_status" ]; then
                feat_status="PROPOSED"
            fi
            local feat_scope=$(grep -m1 -E '^[[:space:]]*scope:' "$f" | sed -E 's/^[[:space:]]*scope:[[:space:]]*["'\'']?([A-Za-z0-9_]+)["'\'']?.*$/\1/' || true)
            if [ -z "$feat_scope" ]; then
                feat_scope="CORE"
            fi

            # Filter logic
            if [ -n "$FILTER_ID" ] && [ "$feat_id" != "$FILTER_ID" ]; then
                continue
            fi
            if [ -n "$FILTER_PHASE" ] && [ "$feat_phase" != "$FILTER_PHASE" ]; then
                continue
            fi

            FOUND_COUNT=$((FOUND_COUNT + 1))
            if [ "$JSON_OUTPUT" -eq 1 ]; then
                local item="{\"id\":\"$feat_id\",\"title\":\"$feat_title\",\"phase\":\"$feat_phase\",\"status\":\"$feat_status\",\"scope\":\"$feat_scope\",\"file\":\"$rel_path\"}"
                if [ "$SPECS_JSON" = "[]" ]; then
                    SPECS_JSON="[$item"
                else
                    SPECS_JSON="$SPECS_JSON,$item"
                fi
            else
                echo "  [$feat_id] Phase $feat_phase | $feat_title | Status: $feat_status | Path: $rel_path"
            fi
        done
    fi
}

if [ "$JSON_OUTPUT" -eq 0 ]; then
    if [ -n "$FILTER_ID" ]; then
        echo "=== Query Feature: $FILTER_ID ==="
    elif [ -n "$FILTER_PHASE" ]; then
        echo "=== Features for Phase $FILTER_PHASE ==="
    else
        echo "=== Discovered Feature Specifications ==="
    fi
fi

find_specs "$FEATURES_DIR"
find_specs "$REPO_ROOT/docs/requirements/modules"

if [ "$JSON_OUTPUT" -eq 1 ]; then
    if [ "$SPECS_JSON" != "[]" ]; then
        SPECS_JSON="$SPECS_JSON]"
    fi
    echo "$SPECS_JSON"
else
    if [ "$FOUND_COUNT" -eq 0 ]; then
        echo "  No matching feature specifications found."
    fi
fi
exit 0
