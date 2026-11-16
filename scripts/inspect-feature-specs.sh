#!/usr/bin/env bash
# inspect-feature-specs.sh - Inspects, queries, and scaffolds modular living feature specifications with zero token overhead.
set -euo pipefail

REPO_ROOT=""
ACTION="list"
FILTER_PHASE=""
FILTER_ID=""
CONCEPT_ID=""
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
        --concept-id|-ConceptId)
            CONCEPT_ID="$2"
            shift 2
            ;;
        --concept-id=*|-ConceptId=*)
            CONCEPT_ID="${1#*=}"
            shift
            ;;
        --new|-New|-n)
            ACTION="new"
            shift
            ;;
        --new-concept|-NewConcept|--concept|-Concept)
            ACTION="new-concept"
            shift
            ;;
        --archive-concept|-ArchiveConcept)
            ACTION="archive-concept"
            FILTER_ID="$2"
            shift 2
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
            if [[ -z "$REPO_ROOT" && ! "$1" =~ ^- ]]; then
                REPO_ROOT="$1"
            fi
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

CONCEPT_TEMPLATE_PATH=""
for t in "$REPO_ROOT/docs/templates/CONCEPT_TEMPLATE.md" \
         "$REPO_ROOT/_agents/docs/templates/CONCEPT_TEMPLATE.md" \
         "$REPO_ROOT/.agents/docs/templates/CONCEPT_TEMPLATE.md"; do
    if [ -f "$t" ]; then
        CONCEPT_TEMPLATE_PATH="$t"
        break
    fi
done

CONCEPTS_DIR_NAME="concepts"
if [ -d "$REPO_ROOT/docs/concept" ] && [ ! -d "$REPO_ROOT/docs/concepts" ]; then
    CONCEPTS_DIR_NAME="concept"
fi
CONCEPTS_DRAFT_DIR="$REPO_ROOT/docs/$CONCEPTS_DIR_NAME/drafts"
CONCEPTS_ARCHIVE_DIR="$REPO_ROOT/docs/$CONCEPTS_DIR_NAME/archive"

# Helper: safe literal template substitution (avoids sed '/' and '&' delimiter collisions)
render_template() {
    local tmpl="$1"
    local dest="$2"
    shift 2
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$tmpl" "$dest" "$@" << 'PYEOF'
import sys
tmpl_path, dest_path = sys.argv[1], sys.argv[2]
pairs = sys.argv[3:]
with open(tmpl_path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()
for i in range(0, len(pairs) - 1, 2):
    text = text.replace(pairs[i], pairs[i + 1])
with open(dest_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
PYEOF
    else
        cp -f "$tmpl" "$dest"
        while [[ $# -ge 2 ]]; do
            local key="$1"
            local val="$2"
            shift 2
            python_free_val=$(printf '%s' "$val" | sed 's/[&|\\]/\\&/g')
            local esc_key
            esc_key=$(printf '%s' "$key" | sed 's/[.[\*^$()+?{|]/\\&/g')
            sed "s|${esc_key}|${python_free_val}|g" "$dest" > "${dest}.tmp" && mv "${dest}.tmp" "$dest"
        done
    fi
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# Action: Scaffolding a new concept draft
if [ "$ACTION" = "new-concept" ]; then
    if [ -n "$CONCEPT_ID" ]; then
        CID="$CONCEPT_ID"
    elif [ -n "$FILTER_ID" ] && [[ "$FILTER_ID" =~ ^CONCEPT- ]]; then
        CID="$FILTER_ID"
    else
        CID="CONCEPT-${NEW_SCOPE}-001"
    fi
    if [ -z "$NEW_TITLE" ]; then
        NEW_TITLE="Concept $CID"
    fi
    SLUG=$(echo "$NEW_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-zA-Z0-9]+/-/g' | sed -E 's/^-+|-+$//g')
    FILE_NAME="${CID}-${SLUG}.md"
    mkdir -p "$CONCEPTS_DRAFT_DIR"
    TARGET_FILE="$CONCEPTS_DRAFT_DIR/$FILE_NAME"

    if [ -f "$TARGET_FILE" ]; then
        echo "Error: Concept draft already exists: $TARGET_FILE" >&2
        exit 1
    fi

    TODAY=$(date +%Y-%m-%d)
    if [ -n "$CONCEPT_TEMPLATE_PATH" ] && [ -f "$CONCEPT_TEMPLATE_PATH" ]; then
        render_template "$CONCEPT_TEMPLATE_PATH" "$TARGET_FILE" \
            "CONCEPT-<SCOPE>-XXX" "$CID" \
            "<CONCEPT-ID>" "$CID" \
            "<Concept Title>" "$NEW_TITLE" \
            "<SCOPE>" "$NEW_SCOPE" \
            "<YYYY-MM-DD>" "$TODAY" \
            "<Author>" "User / Agent" \
            "<slug>" "$SLUG"
    else
        cat <<EOF > "$TARGET_FILE"
# Concept & RFC Draft: $NEW_TITLE

\`\`\`yaml
---
id: $CID
title: "$NEW_TITLE"
status: DRAFT
scope: "$NEW_SCOPE"
target_feature: "FEAT-${NEW_SCOPE}-001"
author: "User / Agent"
created: "$TODAY"
---
\`\`\`

## 1. Problem Statement & Motivation
<Context & Need>

## 2. Solution Approaches & Trade-Offs
- Approach A (Recommended)
- Approach B (Alternative)

## 3. High-Level Architecture
Target Layer: Core Domain / Application

## 4. Phased Implementation Plan
- Phase 1: Foundation & Core Contracts (MVP)
- Phase 2: Feature Integration & Adapters
- Phase 3: Rollout, Migration & Hardening

## 5. Open Questions & Review Checklist
- [ ] Q-1: <Clarification needed>

## 6. Distillation Target Preview
- Preview AC-1: Given, When, Then
EOF
    fi

    if [ "$JSON_OUTPUT" -eq 1 ]; then
        echo "{\"status\":\"created\",\"id\":\"$(json_escape "$CID")\",\"title\":\"$(json_escape "$NEW_TITLE")\",\"file\":\"docs/$CONCEPTS_DIR_NAME/drafts/$(json_escape "$FILE_NAME")\"}"
    else
        echo "Created concept draft: docs/$CONCEPTS_DIR_NAME/drafts/$FILE_NAME"
    fi
    exit 0
fi

# Action: Archiving a distilled concept
if [ "$ACTION" = "archive-concept" ]; then
    if [ ! -d "$CONCEPTS_DRAFT_DIR" ]; then
        echo "Error: Drafts directory does not exist: $CONCEPTS_DRAFT_DIR" >&2
        exit 1
    fi
    MATCHING_FILE=$(find "$CONCEPTS_DRAFT_DIR" -maxdepth 1 -name "*${FILTER_ID}*.md" | head -n 1 || true)
    if [ -z "$MATCHING_FILE" ]; then
        MATCHING_FILE=$(grep -rlE "id:[[:space:]]*['\"]?${FILTER_ID}['\"]?" "$CONCEPTS_DRAFT_DIR" 2>/dev/null | head -n 1 || true)
    fi
    if [ -z "$MATCHING_FILE" ]; then
        echo "Error: No matching draft concept found for '$FILTER_ID' in $CONCEPTS_DRAFT_DIR" >&2
        exit 1
    fi
    mkdir -p "$CONCEPTS_ARCHIVE_DIR"
    BASE_NAME=$(basename "$MATCHING_FILE")
    DEST_FILE="$CONCEPTS_ARCHIVE_DIR/$BASE_NAME"

    sed -E 's/status:[[:space:]]*["'\'']?(DRAFT|UNDER_REVIEW|APPROVED)["'\'']?/status: ARCHIVED/g' "$MATCHING_FILE" > "$DEST_FILE"
    rm -f "$MATCHING_FILE"

    if [ "$JSON_OUTPUT" -eq 1 ]; then
        echo "{\"status\":\"archived\",\"id\":\"$(json_escape "$FILTER_ID")\",\"source\":\"docs/$CONCEPTS_DIR_NAME/drafts/$(json_escape "$BASE_NAME")\",\"destination\":\"docs/$CONCEPTS_DIR_NAME/archive/$(json_escape "$BASE_NAME")\"}"
    else
        echo "Archived concept: docs/$CONCEPTS_DIR_NAME/archive/$BASE_NAME"
    fi
    exit 0
fi

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
        render_template "$TEMPLATE_PATH" "$TARGET_FILE" \
            "FEAT-<SCOPE>-XXX" "$FILTER_ID" \
            "<FEAT-ID>" "$FILTER_ID" \
            "<Feature Title>" "$NEW_TITLE" \
            "<SCOPE>" "$NEW_SCOPE" \
            "<PHASE>" "$PHASE" \
            "phase: 1" "phase: $PHASE" \
            "<TARGET_RELEASE>" "$NEW_RELEASE" \
            "<e.g. v0.1.0>" "$NEW_RELEASE" \
            "<slug>" "$SLUG" \
            "<FILE_NAME>" "$FILE_NAME"
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

    ROADMAP_UPDATED=false
    if [ -f "$ROADMAP_FILE" ] && grep -q '| :--- | :--- |' "$ROADMAP_FILE" 2>/dev/null; then
        REL_PATH="docs/features/$FILE_NAME"
        ROW="| Phase $PHASE | \`$FILTER_ID\` | $NEW_TITLE | PROPOSED | \`$NEW_SCOPE\` | [$REL_PATH]($REL_PATH) | \`$NEW_RELEASE\` |"
        echo "$ROW" >> "$ROADMAP_FILE"
        ROADMAP_UPDATED=true
    fi

    if [ "$JSON_OUTPUT" -eq 1 ]; then
        echo "{\"status\":\"created\",\"id\":\"$(json_escape "$FILTER_ID")\",\"title\":\"$(json_escape "$NEW_TITLE")\",\"phase\":\"$(json_escape "$PHASE")\",\"file\":\"docs/features/$(json_escape "$FILE_NAME")\",\"roadmap_updated\":$ROADMAP_UPDATED}"
    else
        echo "Created feature specification: docs/features/$FILE_NAME"
        if [ "$ROADMAP_UPDATED" = true ]; then
            echo "Appended feature entry to: docs/ROADMAP.md"
        fi
    fi
    exit 0
fi

# Action: Check hash-based drift (--check-drift / --update-state)
if [ "$CHECK_DRIFT" -eq 1 ]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$REPO_ROOT" "$STATE_FILE" "$UPDATE_STATE" "$JSON_OUTPUT" << 'PYEOF'
import hashlib, json, os, re, sys

repo_root, state_file, update_str, json_str = sys.argv[1:5]
update_state = update_str == "1"
json_out = json_str == "1"

spec_files = []
for rel_dir in ("docs/features", "docs/requirements/modules"):
    d = os.path.join(repo_root, rel_dir)
    if os.path.isdir(d):
        for fname in sorted(os.listdir(d)):
            if fname.endswith(".md"):
                spec_files.append((rel_dir + "/" + fname, os.path.join(d, fname)))

current_state = {}
for rel_path, full_path in spec_files:
    with open(full_path, "rb") as f:
        raw_bytes = f.read()
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        raw_bytes = raw_bytes[3:]
    digest = hashlib.sha256(raw_bytes.replace(b"\r\n", b"\n")).hexdigest()
    txt = raw_bytes.decode("utf-8", errors="ignore")
    m_id = re.search(r'^\s*id:\s*["\']?([A-Za-z0-9_-]+)["\']?', txt, re.M)
    feat_id = m_id.group(1) if m_id else os.path.splitext(os.path.basename(full_path))[0]
    m_phase = re.search(r'^\s*phase:\s*["\']?(.*?)["\']?\s*$', txt, re.M)
    feat_phase = m_phase.group(1).strip() if m_phase else "1"
    m_status = re.search(r'^\s*status:\s*["\']?([A-Za-z_]+)["\']?', txt, re.M)
    feat_status = m_status.group(1).strip() if m_status else "PROPOSED"
    current_state[rel_path] = {
        "id": feat_id,
        "hash": digest,
        "phase": feat_phase,
        "status": feat_status,
    }

drift_detected = False
changed_files = []
if os.path.isfile(state_file):
    try:
        with open(state_file, "r", encoding="utf-8") as sf:
            saved_state = json.load(sf)
    except Exception:
        saved_state = {}
    for key, val in current_state.items():
        prev = saved_state.get(key)
        if not prev or prev.get("hash") != val["hash"]:
            drift_detected = True
            changed_files.append(key)
else:
    drift_detected = len(current_state) > 0
    changed_files = list(current_state.keys())

if update_state:
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    with open(state_file, "w", encoding="utf-8", newline="\n") as sf:
        json.dump(current_state, sf, indent=2)

res = {
    "status": "drift_detected" if drift_detected else "synchronized",
    "drift_count": len(changed_files),
    "changed_files": changed_files,
    "total_specs": len(current_state),
}
if json_out:
    print(json.dumps(res, separators=(",", ":")))
else:
    print(f"Feature Spec State: {res['status']} ({res['drift_count']} modified, {res['total_specs']} total)")
PYEOF
        exit 0
    else
        echo '{"status":"synchronized","drift_count":0,"changed_files":[],"total_specs":0}'
        exit 0
    fi
fi

# Parsing existing specs
SPECS_JSON="[]"
FOUND_COUNT=0
LAST_ITEM=""

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
            local feat_release=$(grep -m1 -E '^[[:space:]]*target_release:' "$f" | sed -E 's/^[[:space:]]*target_release:[[:space:]]*["'\'']?(.*)["'\'']?[[:space:]]*$/\1/' || true)
            if [ -z "$feat_release" ]; then
                feat_release="v0.1.0"
            fi

            # Filter logic
            if [ -n "$FILTER_ID" ] && [ "$feat_id" != "$FILTER_ID" ] && [[ "$rel_path" != *"$FILTER_ID"* ]]; then
                continue
            fi
            if [ -n "$FILTER_PHASE" ] && [ "$feat_phase" != "$FILTER_PHASE" ]; then
                continue
            fi

            FOUND_COUNT=$((FOUND_COUNT + 1))
            local item="{\"Id\":\"$(json_escape "$feat_id")\",\"Title\":\"$(json_escape "$feat_title")\",\"Phase\":\"$(json_escape "$feat_phase")\",\"Status\":\"$(json_escape "$feat_status")\",\"Scope\":\"$(json_escape "$feat_scope")\",\"TargetRelease\":\"$(json_escape "$feat_release")\",\"FilePath\":\"$(json_escape "$rel_path")\"}"
            LAST_ITEM="$item"
            if [ "$JSON_OUTPUT" -eq 1 ]; then
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

if [ "$JSON_OUTPUT" -eq 0 ] && [ -z "$FILTER_ID" ]; then
    if [ -n "$FILTER_PHASE" ]; then
        echo "=== Features for Phase $FILTER_PHASE ==="
    else
        echo "=== Discovered Feature Specifications ==="
    fi
fi

find_specs "$FEATURES_DIR"
find_specs "$REPO_ROOT/docs/requirements/modules"

if [ -n "$FILTER_ID" ]; then
    if [ "$FOUND_COUNT" -eq 0 ]; then
        if [ "$JSON_OUTPUT" -eq 1 ]; then
            echo "{\"status\":\"not_found\",\"id\":\"$(json_escape "$FILTER_ID")\"}"
        else
            echo "Feature '$FILTER_ID' not found."
        fi
        exit 1
    fi
    if [ "$JSON_OUTPUT" -eq 1 ]; then
        echo "$LAST_ITEM"
    fi
    exit 0
fi

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
