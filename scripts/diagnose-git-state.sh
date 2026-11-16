#!/usr/bin/env bash
# ==============================================================================
# Diagnoses Git repository state, anomalies, and creates safety snapshots deterministically.
# ==============================================================================
set -euo pipefail

REPO_ROOT=""
CREATE_SNAPSHOT=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root|-RepoRoot)
      REPO_ROOT="$2"
      shift 2
      ;;
    --create-snapshot|-CreateSnapshot|--snapshot)
      CREATE_SNAPSHOT=true
      shift
      ;;
    --json|-JsonOutput|-j)
      JSON_OUTPUT=true
      shift
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$REPO_ROOT" ]]; then
        REPO_ROOT="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(pwd)"
fi

RAW_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
IS_DETACHED=false
BRANCH="$RAW_BRANCH"
if [[ -z "$BRANCH" ]]; then
  IS_DETACHED=true
  BRANCH="DETACHED_HEAD"
fi

CONFLICTS=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null || true)
HAS_CONFLICTS=false
CONFLICT_LIST=()
if [[ -n "$CONFLICTS" ]]; then
  HAS_CONFLICTS=true
  while IFS= read -r cf; do
    [[ -n "$cf" ]] && CONFLICT_LIST+=("$cf")
  done <<< "$CONFLICTS"
fi

GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || echo "${REPO_ROOT}/.git")
if [[ "$GIT_DIR" != /* && "$GIT_DIR" != [A-Za-z]:* ]]; then
  GIT_DIR="${REPO_ROOT}/${GIT_DIR}"
fi
IS_REBASE=false
if [[ -d "${GIT_DIR}/rebase-merge" || -d "${GIT_DIR}/rebase-apply" ]]; then
  IS_REBASE=true
fi

IS_MERGE=false
if [[ -f "${GIT_DIR}/MERGE_HEAD" ]]; then
  IS_MERGE=true
fi

IS_CHERRY_PICK=false
if [[ -f "${GIT_DIR}/CHERRY_PICK_HEAD" ]]; then
  IS_CHERRY_PICK=true
fi

UNCOMMITTED_COUNT=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || echo 0)

AHEAD=0
BEHIND=0
if [[ "$IS_DETACHED" == "false" && -n "$RAW_BRANCH" ]]; then
  RAW_REV=$(git -C "$REPO_ROOT" rev-list --left-right --count "${RAW_BRANCH}...@{upstream}" 2>/dev/null || true)
  if [[ -n "$RAW_REV" ]]; then
    read -r AHEAD BEHIND <<< "$RAW_REV" || true
    AHEAD="${AHEAD:-0}"
    BEHIND="${BEHIND:-0}"
  fi
fi

if [[ "$HAS_CONFLICTS" == "true" ]]; then STATE_NAME="merge_conflict"
elif [[ "$IS_REBASE" == "true" ]]; then STATE_NAME="rebase_in_progress"
elif [[ "$IS_MERGE" == "true" ]]; then STATE_NAME="merge_in_progress"
elif [[ "$IS_CHERRY_PICK" == "true" ]]; then STATE_NAME="cherry_pick_in_progress"
elif [[ "$IS_DETACHED" == "true" ]]; then STATE_NAME="detached_head"
elif [[ "$AHEAD" -gt 0 && "$BEHIND" -gt 0 ]]; then STATE_NAME="diverged"
elif [[ "$UNCOMMITTED_COUNT" -gt 0 ]]; then STATE_NAME="dirty"
else STATE_NAME="clean"; fi

SNAPSHOT_BRANCH=""
if [[ "$CREATE_SNAPSHOT" == "true" ]]; then
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  SAFE_BRANCH="detached"
  if [[ "$IS_DETACHED" == "false" && -n "$RAW_BRANCH" ]]; then
    SAFE_BRANCH="${RAW_BRANCH//[^a-zA-Z0-9_-]/-}"
  fi
  SNAPSHOT_BRANCH="safety-snapshot-${SAFE_BRANCH}-${TIMESTAMP}"
  git -C "$REPO_ROOT" branch "$SNAPSHOT_BRANCH" 2>/dev/null || true
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  CONFLICTS_JSON=""
  for cf in "${CONFLICT_LIST[@]:-}"; do
    [[ -z "$cf" ]] && continue
    esc_cf="${cf//\\/\\\\}"
    esc_cf="${esc_cf//\"/\\\"}"
    [[ -n "$CONFLICTS_JSON" ]] && CONFLICTS_JSON+=","
    CONFLICTS_JSON+="\"$esc_cf\""
  done
  SNAP_JSON="null"
  if [[ -n "$SNAPSHOT_BRANCH" ]]; then
    SNAP_JSON="\"$SNAPSHOT_BRANCH\""
  fi
  echo "{\"state\":\"$STATE_NAME\",\"branch\":\"$BRANCH\",\"is_detached_head\":$IS_DETACHED,\"has_conflicts\":$HAS_CONFLICTS,\"conflicted_files\":[$CONFLICTS_JSON],\"is_rebase_in_progress\":$IS_REBASE,\"is_merge_in_progress\":$IS_MERGE,\"is_cherry_pick_in_progress\":$IS_CHERRY_PICK,\"uncommitted_changes\":$UNCOMMITTED_COUNT,\"ahead_of_upstream\":$AHEAD,\"behind_upstream\":$BEHIND,\"created_snapshot_branch\":$SNAP_JSON}"
else
  echo "Git State: $STATE_NAME (Branch: $BRANCH, Dirty: $UNCOMMITTED_COUNT, Ahead: $AHEAD, Behind: $BEHIND)"
  if [[ "$HAS_CONFLICTS" == "true" ]]; then
    echo "Active Conflicts (${#CONFLICT_LIST[@]}):"
    for cf in "${CONFLICT_LIST[@]}"; do
      echo "  ! $cf"
    done
  fi
  if [[ -n "$SNAPSHOT_BRANCH" ]]; then
    echo "Safety Snapshot Created: $SNAPSHOT_BRANCH"
  fi
fi
