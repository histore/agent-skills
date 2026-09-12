#!/usr/bin/env bash
# ==============================================================================
# get-arch-diff.sh - Incremental Architecture Sync Diff Analyzer (macOS & Linux)
# ==============================================================================
# Analyzes git deltas since the last architectural sync checkpoint and detects
# relevant code changes without consuming LLM tokens.
# Compatible with macOS default Bash/Zsh and standard Linux environments.
# ==============================================================================

set -euo pipefail

STATE_FILE="docs/architecture/.arch-sync.json"
UPDATE_CHECKPOINT=0
INIT_STRUCTURE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --init|-i)
      INIT_STRUCTURE=1
      shift
      ;;
    --update-checkpoint|-u)
      UPDATE_CHECKPOINT=1
      shift
      ;;
    --state-file|-s)
      STATE_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Not inside a valid git repository or git is unavailable." >&2
  exit 1
fi

HEAD_COMMIT=$(git rev-parse HEAD | tr -d '[:space:]')

# Handle initialization request
if [[ $INIT_STRUCTURE -eq 1 ]]; then
  ARCH_DIR=$(dirname "$STATE_FILE")
  [[ -z "$ARCH_DIR" || "$ARCH_DIR" == "." ]] && ARCH_DIR="docs/architecture"
  mkdir -p "$ARCH_DIR/modules" "$ARCH_DIR/adr"

  OVERVIEW_FILE="$ARCH_DIR/overview.md"
  if [[ ! -f "$OVERVIEW_FILE" ]]; then
    cat <<EOF > "$OVERVIEW_FILE"
# Architecture Overview

## System Purpose & Scope
High-level description of system capabilities, primary user workflows, and boundaries.

## Architecture & Layers
- **Domain / Models**: Core entities and domain logic.
- **Services / Contracts**: Application interfaces and business operations.
- **Presentation / UI**: ViewModels and Views.

## Cross-Cutting Concerns
- Error handling, logging, and localization.
- Performance, concurrency, and security.

## Modules Index
See modules/ for detailed specifications.
EOF
  fi

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat <<EOF > "$STATE_FILE"
{
  "last_synced_commit": "$HEAD_COMMIT",
  "last_synced_at": "$TIMESTAMP"
}
EOF
  echo "[OK] Architecture structure initialized in $ARCH_DIR (Baseline: $HEAD_COMMIT)"
  exit 0
fi

# Handle checkpoint update request
if [[ $UPDATE_CHECKPOINT -eq 1 ]]; then
  STATE_DIR=$(dirname "$STATE_FILE")
  if [[ -n "$STATE_DIR" && ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
  fi
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat <<EOF > "$STATE_FILE"
{
  "last_synced_commit": "$HEAD_COMMIT",
  "last_synced_at": "$TIMESTAMP"
}
EOF
  echo "[OK] Architecture sync checkpoint updated to $HEAD_COMMIT ($TIMESTAMP)"
  exit 0
fi

# Check if state file exists
if [[ ! -f "$STATE_FILE" ]]; then
  cat <<EOF
{
  "has_changes": true,
  "is_initial_baseline": true,
  "last_synced_commit": null,
  "head_commit": "$HEAD_COMMIT",
  "reason": "INITIAL_BASELINE_REQUIRED",
  "message": "No sync state found at $STATE_FILE. Baseline documentation should be established.",
  "affected_files": []
}
EOF
  exit 0
fi

# Extract last_synced_commit (portable regex/sed without jq dependency)
LAST_COMMIT=$(sed -n -E 's/.*"last_synced_commit"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$STATE_FILE" | tr -d '[:space:]')

if [[ -z "$LAST_COMMIT" ]]; then
  cat <<EOF
{
  "has_changes": true,
  "is_initial_baseline": true,
  "last_synced_commit": null,
  "head_commit": "$HEAD_COMMIT",
  "reason": "INVALID_STATE_FILE",
  "message": "State file exists but contains no valid last_synced_commit.",
  "affected_files": []
}
EOF
  exit 0
fi

# Verify commit exists in history
if ! git cat-file -e "$LAST_COMMIT" >/dev/null 2>&1; then
  cat <<EOF
{
  "has_changes": true,
  "is_initial_baseline": true,
  "last_synced_commit": "$LAST_COMMIT",
  "head_commit": "$HEAD_COMMIT",
  "reason": "COMMIT_NOT_IN_HISTORY",
  "message": "Last synced commit $LAST_COMMIT is not reachable. Re-baseline required.",
  "affected_files": []
}
EOF
  exit 0
fi

# Up to date check
if [[ "$LAST_COMMIT" == "$HEAD_COMMIT" ]]; then
  cat <<EOF
{
  "has_changes": false,
  "last_synced_commit": "$LAST_COMMIT",
  "head_commit": "$HEAD_COMMIT",
  "reason": "UP_TO_DATE",
  "message": "Documentation is already up to date with HEAD ($HEAD_COMMIT).",
  "affected_files": []
}
EOF
  exit 0
fi

# Inspect changed files
RAW_DIFF=$(git diff --name-status "$LAST_COMMIT..$HEAD_COMMIT" || true)

if [[ -z "$RAW_DIFF" ]]; then
  cat <<EOF
{
  "has_changes": false,
  "last_synced_commit": "$LAST_COMMIT",
  "head_commit": "$HEAD_COMMIT",
  "reason": "NO_FILES_CHANGED",
  "message": "No file changes between $LAST_COMMIT and $HEAD_COMMIT.",
  "affected_files": []
}
EOF
  exit 0
fi

AFFECTED_JSON=()
IGNORED_COUNT=0

SOURCE_EXT_REGEX='\.(cs|rs|go|ts|js|py|cpp|c|h|java|kt|swift)$'
EXCLUDE_REGEX='(test|spec|mock|\.g\.cs|\.Designer\.cs|bin/|obj/|node_modules/)'

while IFS=$'\t' read -r status filepath; do
  [[ -z "$filepath" ]] && continue

  if echo "$filepath" | grep -Eqi "$SOURCE_EXT_REGEX" && ! echo "$filepath" | grep -Eqi "$EXCLUDE_REGEX"; then
    MODULE=$(echo "$filepath" | cut -d'/' -f1)
    [[ "$MODULE" == "$filepath" ]] && MODULE="root"
    AFFECTED_JSON+=("{\"status\": \"$status\", \"path\": \"$filepath\", \"module\": \"$MODULE\"}")
  else
    IGNORED_COUNT=$((IGNORED_COUNT + 1))
  fi
done <<< "$RAW_DIFF"

AFFECTED_COUNT=${#AFFECTED_JSON[@]}

if [[ $AFFECTED_COUNT -eq 0 ]]; then
  cat <<EOF
{
  "has_changes": false,
  "last_synced_commit": "$LAST_COMMIT",
  "head_commit": "$HEAD_COMMIT",
  "reason": "NO_ARCH_CHANGES",
  "message": "Changes detected, but none affect architectural source files ($IGNORED_COUNT non-architectural files ignored).",
  "affected_files": []
}
EOF
  exit 0
fi

# Output JSON payload
MODULES_LIST=$(printf ", %s" "${AFFECTED_JSON[@]}")
MODULES_LIST="${MODULES_LIST:2}"

cat <<EOF
{
  "has_changes": true,
  "is_initial_baseline": false,
  "last_synced_commit": "$LAST_COMMIT",
  "head_commit": "$HEAD_COMMIT",
  "reason": "ARCH_CHANGES_DETECTED",
  "message": "$AFFECTED_COUNT architectural source file(s) modified.",
  "affected_files_count": $AFFECTED_COUNT,
  "ignored_files_count": $IGNORED_COUNT,
  "affected_files": [
    $MODULES_LIST
  ]
}
EOF
exit 0
