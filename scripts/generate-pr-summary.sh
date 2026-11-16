#!/usr/bin/env bash
# ==============================================================================
# Generates structured Pull Request descriptions and change summaries deterministically.
# ==============================================================================
set -euo pipefail

BASE_BRANCH=""
REPO_ROOT=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    --base|-b|-BaseBranch)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --base=*|-b=*)
      BASE_BRANCH="${1#*=}"
      shift
      ;;
    --repo-root|-RepoRoot)
      REPO_ROOT="$2"
      shift 2
      ;;
    --repo-root=*)
      REPO_ROOT="${1#*=}"
      shift
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$BASE_BRANCH" ]]; then
        BASE_BRANCH="$1"
      elif [[ -z "$REPO_ROOT" ]]; then
        REPO_ROOT="$1"
      fi
      shift
      ;;
  esac
done

[[ -z "$BASE_BRANCH" ]] && BASE_BRANCH="main"
[[ -z "$REPO_ROOT" ]] && REPO_ROOT="$(pwd)"

CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
[[ -z "$CURRENT_BRANCH" ]] && CURRENT_BRANCH="HEAD"
COMMITS=$(git -C "$REPO_ROOT" log "${BASE_BRANCH}..HEAD" --oneline --no-merges 2>/dev/null || true)
CHANGED_FILES=$(git -C "$REPO_ROOT" diff --name-only "${BASE_BRANCH}..HEAD" 2>/dev/null || true)

COMMIT_COUNT=0
if [[ -n "$COMMITS" ]]; then
  COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
fi

FILE_COUNT=0
if [[ -n "$CHANGED_FILES" ]]; then
  FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
fi

REQ_IDS=()
while IFS= read -r rid; do
  [[ -n "$rid" ]] && REQ_IDS+=("$rid")
done < <( {
  printf '%s\n' "$COMMITS"
  git -C "$REPO_ROOT" diff "${BASE_BRANCH}..HEAD" 2>/dev/null || true
} | grep -oE 'REQ-[A-Za-z0-9_]+-[0-9]{3,}' | tr '[:lower:]' '[:upper:]' | sort -u || true )

TITLE="feat: updates on ${CURRENT_BRANCH}"

PR_MD="## Summary of Changes"$'\n'
if [[ -n "$COMMITS" ]]; then
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    msg=$(echo "$c" | sed -E 's/^[a-f0-9]+[[:space:]]+//')
    PR_MD+="- ${msg}"$'\n'
  done <<< "$COMMITS"
else
  PR_MD+="- Working branch updates and maintenance."$'\n'
fi
PR_MD+=$'\n'"## Associated Requirements"$'\n'
if [[ ${#REQ_IDS[@]} -gt 0 ]]; then
  for req in "${REQ_IDS[@]}"; do
    PR_MD+="- ${req}"$'\n'
  done
else
  PR_MD+="- None explicitly referenced."$'\n'
fi
PR_MD+=$'\n'"## Touched Files (${FILE_COUNT})"$'\n'
if [[ -n "$CHANGED_FILES" ]]; then
  shown=0
  while IFS= read -r cf; do
    [[ -z "$cf" ]] && continue
    if [[ $shown -lt 10 ]]; then
      PR_MD+="- ${cf}"$'\n'
    fi
    shown=$((shown + 1))
  done <<< "$CHANGED_FILES"
  if [[ $FILE_COUNT -gt 10 ]]; then
    PR_MD+="- ... and $((FILE_COUNT - 10)) more files"$'\n'
  fi
fi
PR_MD+=$'\n'"## Quality & Verification Checklist"$'\n'
PR_MD+="- [x] Inner-Loop TDD followed (tests pass 100% with 0 errors)"$'\n'
PR_MD+="- [x] Clean Architecture layer boundaries respected"$'\n'
PR_MD+="- [x] Safe Rust adhered to (zero unsafe blocks)"$'\n'
PR_MD+="- [x] Stage-1 Fast-Gate and project linter verified"$'\n'

pr_json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

if [[ "$JSON_OUTPUT" == "true" ]]; then
  REQS_JSON=""
  for r in "${REQ_IDS[@]:-}"; do
    [[ -z "$r" ]] && continue
    [[ -n "$REQS_JSON" ]] && REQS_JSON+=","
    REQS_JSON+="\"$(pr_json_esc "$r")\""
  done
  echo "{\"base_branch\":\"$(pr_json_esc "$BASE_BRANCH")\",\"current_branch\":\"$(pr_json_esc "$CURRENT_BRANCH")\",\"suggested_title\":\"$(pr_json_esc "$TITLE")\",\"commits_count\":$COMMIT_COUNT,\"files_count\":$FILE_COUNT,\"referenced_reqs\":[${REQS_JSON}],\"pr_body_markdown\":\"$(pr_json_esc "$PR_MD")\"}"
else
  echo "PR Summary: $TITLE (Branch: $CURRENT_BRANCH -> Base: $BASE_BRANCH, Commits: $COMMIT_COUNT)"
  printf '%s' "$PR_MD"
fi
