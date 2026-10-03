#!/usr/bin/env bash
# ==============================================================================
# Diagnoses Git repository state, anomalies, and creates safety snapshots deterministically.
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
CREATE_SNAPSHOT=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --snapshot)
      CREATE_SNAPSHOT=true
      ;;
    --json|-j)
      JSON_OUTPUT=true
      ;;
  esac
done

BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
IS_DETACHED=false
if [[ -z "$BRANCH" ]]; then
  IS_DETACHED=true
  BRANCH="DETACHED_HEAD"
fi

CONFLICTS=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null || true)
HAS_CONFLICTS=false
if [[ -n "$CONFLICTS" ]]; then
  HAS_CONFLICTS=true
fi

GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || echo "${REPO_ROOT}/.git")
IS_REBASE=false
if [[ -d "${GIT_DIR}/rebase-merge" || -d "${GIT_DIR}/rebase-apply" ]]; then
  IS_REBASE=true
fi

IS_MERGE=false
if [[ -f "${GIT_DIR}/MERGE_HEAD" ]]; then
  IS_MERGE=true
fi

UNCOMMITTED_COUNT=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l || echo 0)

SNAPSHOT_BRANCH=""
if [[ "$CREATE_SNAPSHOT" == "true" ]]; then
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  SNAPSHOT_BRANCH="safety-snapshot-${BRANCH//[^a-zA-Z0-9_-]/-}-${TIMESTAMP}"
  git -C "$REPO_ROOT" branch "$SNAPSHOT_BRANCH" 2>/dev/null || true
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"branch\":\"$BRANCH\",\"is_detached_head\":$IS_DETACHED,\"has_conflicts\":$HAS_CONFLICTS,\"is_rebase\":$IS_REBASE,\"is_merge\":$IS_MERGE,\"uncommitted\":$UNCOMMITTED_COUNT,\"snapshot\":\"$SNAPSHOT_BRANCH\"}"
else
  echo "============================================="
  echo "Deterministic Git State & Anomaly Diagnostics"
  echo "Branch: $BRANCH | Uncommitted: $UNCOMMITTED_COUNT"
  echo "============================================="
  if [[ -n "$SNAPSHOT_BRANCH" ]]; then
    echo "Safety Snapshot Created: $SNAPSHOT_BRANCH"
  fi
fi
