#!/usr/bin/env bash
# ==============================================================================
# get-arch-diff.sh - Incremental Architecture Sync Diff Analyzer (macOS & Linux)
# ==============================================================================
# Analyzes git deltas since the last architectural sync checkpoint and detects
# relevant code changes without consuming LLM tokens.
# Compatible with macOS default Bash/Zsh and standard Linux environments.
# Supports internal and external documentation storage with zero project footprint
# via local git configuration (.git/config) and full CLI / env override options.
# ==============================================================================

set -euo pipefail

CLI_DOC_DIR=""
CLI_MODE=""
CLI_STATE_FILE=""
UPDATE_CHECKPOINT=0
INIT_STRUCTURE=0
SET_DOC_DIR=""
SET_MODE=""

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
    --doc-dir)
      CLI_DOC_DIR="$2"
      shift 2
      ;;
    --mode)
      CLI_MODE="$2"
      shift 2
      ;;
    --state-file|-s)
      CLI_STATE_FILE="$2"
      shift 2
      ;;
    --set-doc-dir)
      SET_DOC_DIR="$2"
      shift 2
      ;;
    --set-mode)
      SET_MODE="$2"
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
REPO_ROOT=$(git rev-parse --show-toplevel | tr -d '[:space:]')
REPO_NAME=$(basename "$REPO_ROOT")

# Handle local git config helper commands
if [[ -n "$SET_DOC_DIR" ]]; then
  git config --local arch-sync.doc-dir "$SET_DOC_DIR"
  echo "[OK] Project-level arch-sync.doc-dir set to: $SET_DOC_DIR (stored in .git/config, 0 project footprint)"
  exit 0
fi

if [[ -n "$SET_MODE" ]]; then
  git config --local arch-sync.mode "$SET_MODE"
  echo "[OK] Project-level arch-sync.mode set to: $SET_MODE (stored in .git/config, 0 project footprint)"
  exit 0
fi

# Resolve documentation directory and storage mode
RESOLVED_DOC_DIR=""
RESOLVED_MODE="internal"
RESOLVED_FROM="default"

# 1. CLI Override
if [[ -n "$CLI_DOC_DIR" ]]; then
  RESOLVED_DOC_DIR="$CLI_DOC_DIR"
  RESOLVED_FROM="cli_override"
  RESOLVED_MODE="${CLI_MODE:-external}"
elif [[ -n "$CLI_STATE_FILE" ]]; then
  RESOLVED_DOC_DIR=$(dirname "$CLI_STATE_FILE")
  [[ -z "$RESOLVED_DOC_DIR" || "$RESOLVED_DOC_DIR" == "." ]] && RESOLVED_DOC_DIR="$REPO_ROOT"
  RESOLVED_FROM="cli_state_file"
  RESOLVED_MODE="${CLI_MODE:-external}"
# 2. Environment Variable
elif [[ -n "${ARCH_SYNC_DOC_DIR:-}" ]]; then
  RESOLVED_DOC_DIR="$ARCH_SYNC_DOC_DIR"
  RESOLVED_FROM="env_var"
  RESOLVED_MODE="${ARCH_SYNC_MODE:-external}"
# 3. Project-Level Git Config (git config --local arch-sync.doc-dir)
else
  GIT_LOCAL_DIR=$(git config --local --get arch-sync.doc-dir 2>/dev/null || true)
  GIT_LOCAL_MODE=$(git config --local --get arch-sync.mode 2>/dev/null || true)

  if [[ -n "$GIT_LOCAL_DIR" ]]; then
    RESOLVED_DOC_DIR="$GIT_LOCAL_DIR"
    RESOLVED_FROM="git_local_config"
    RESOLVED_MODE="${GIT_LOCAL_MODE:-external}"
  else
    # 4. User Global Git Config
    GIT_GLOBAL_BASE=$(git config --global --get arch-sync.external-base-dir 2>/dev/null || true)
    if [[ -n "$GIT_GLOBAL_BASE" ]]; then
      RESOLVED_DOC_DIR="$GIT_GLOBAL_BASE/$REPO_NAME"
      RESOLVED_FROM="git_global_config"
      RESOLVED_MODE="external"
    else
      # 5. Default Fallback
      RESOLVED_DOC_DIR="$REPO_ROOT/docs/architecture"
      RESOLVED_FROM="default"
      RESOLVED_MODE="internal"
    fi
  fi
fi

# Normalize path to absolute
if [[ "$RESOLVED_DOC_DIR" != /* ]]; then
  RESOLVED_DOC_DIR="$REPO_ROOT/$RESOLVED_DOC_DIR"
fi

if [[ -n "$CLI_MODE" ]]; then
  RESOLVED_MODE="$CLI_MODE"
elif [[ "$RESOLVED_FROM" == "default" ]]; then
  RESOLVED_MODE="internal"
elif [[ "$RESOLVED_DOC_DIR" == "$REPO_ROOT"* ]]; then
  RESOLVED_MODE="internal"
else
  RESOLVED_MODE="external"
fi

if [[ -n "$CLI_STATE_FILE" ]]; then
  STATE_FILE="$CLI_STATE_FILE"
  [[ "$STATE_FILE" != /* ]] && STATE_FILE="$REPO_ROOT/$STATE_FILE"
else
  STATE_FILE="$RESOLVED_DOC_DIR/.arch-sync.json"
fi

# Handle initialization request
if [[ $INIT_STRUCTURE -eq 1 ]]; then
  mkdir -p "$RESOLVED_DOC_DIR/modules" "$RESOLVED_DOC_DIR/adr"

  OVERVIEW_FILE="$RESOLVED_DOC_DIR/overview.md"
  if [[ ! -f "$OVERVIEW_FILE" ]]; then
    cat <<EOF > "$OVERVIEW_FILE"
# Architecture Overview

## System Purpose & Scope
High-level description of system capabilities, primary user workflows, and boundaries.

## Architecture & Layers
- **Domain / Models**: Core entities, value objects, and domain logic.
- **Services / Contracts**: Application interfaces and business operations.
- **Presentation / UI**: ViewModels and Views.

## Cross-Cutting Concerns
- Error handling, logging, and localization.
- Performance, concurrency, and security.

## Modules Index
Detailed component specifications are maintained incrementally under modules/:
- *List modules here*
EOF
  fi

  # Only write ARCHITECTURE.md to repo root if storage mode is internal (0 footprint if external)
  if [[ "$RESOLVED_MODE" == "internal" ]]; then
    ROOT_ARCH_FILE="$REPO_ROOT/ARCHITECTURE.md"
    if [[ ! -f "$ROOT_ARCH_FILE" ]]; then
      cat <<EOF > "$ROOT_ARCH_FILE"
# Architecture Documentation

This project's architecture is maintained under docs/architecture/:
- **Overview**: overview.md
- **Module Specs**: modules/
EOF
    fi
  fi

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat <<EOF > "$STATE_FILE"
{
  "last_synced_commit": "$HEAD_COMMIT",
  "last_synced_at": "$TIMESTAMP",
  "storage_mode": "$RESOLVED_MODE",
  "doc_dir": "$RESOLVED_DOC_DIR"
}
EOF
  echo "[OK] Architecture structure initialized at $RESOLVED_DOC_DIR [Mode: $RESOLVED_MODE, Source: $RESOLVED_FROM] (Baseline: $HEAD_COMMIT)"
  exit 0
fi

# Handle checkpoint update request
if [[ $UPDATE_CHECKPOINT -eq 1 ]]; then
  STATE_DIR=$(dirname "$STATE_FILE")
  mkdir -p "$STATE_DIR"
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat <<EOF > "$STATE_FILE"
{
  "last_synced_commit": "$HEAD_COMMIT",
  "last_synced_at": "$TIMESTAMP",
  "storage_mode": "$RESOLVED_MODE",
  "doc_dir": "$RESOLVED_DOC_DIR"
}
EOF
  echo "[OK] Architecture sync checkpoint updated to $HEAD_COMMIT ($TIMESTAMP) at $STATE_FILE"
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
  "reason": "INITIAL_BASELINE_REQUIRED",
  "message": "No sync state found at $STATE_FILE. Baseline documentation should be established.",
  "affected_files": []
}
EOF
  exit 0
fi

# Extract last_synced_commit (portable sed without jq dependency)
LAST_COMMIT=$(sed -n -E 's/.*"last_synced_commit"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$STATE_FILE" | tr -d '[:space:]')

if [[ -z "$LAST_COMMIT" ]]; then
  cat <<EOF
{
  "has_changes": true,
  "is_initial_baseline": true,
  "last_synced_commit": null,
  "head_commit": "$HEAD_COMMIT",
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
  "doc_dir": "$RESOLVED_DOC_DIR",
  "storage_mode": "$RESOLVED_MODE",
  "resolved_from": "$RESOLVED_FROM",
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
