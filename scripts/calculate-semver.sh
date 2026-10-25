#!/usr/bin/env bash
# ==============================================================================
# Calculates next SemVer bump and draft changelog deterministically from Conventional Commits.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(pwd)"
JSON_OUTPUT=false
CHECK_SYNC=false
EXECUTE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --repo-root=*)
      REPO_ROOT="${1#*=}"
      shift
      ;;
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    --check-sync)
      CHECK_SYNC=true
      shift
      ;;
    --execute)
      EXECUTE=true
      shift
      ;;
    -*)
      shift
      ;;
    *)
      REPO_ROOT="$1"
      shift
      ;;
  esac
done

CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "HEAD")
LATEST_TAG=$(git -C "$REPO_ROOT" tag -l "v[0-9]*" --sort=-v:refname 2>/dev/null | head -n 1 || echo "")
[[ -z "$LATEST_TAG" ]] && LATEST_TAG="v0.0.0"

IS_CLEAN=true
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
  IS_CLEAN=false
fi

BEHIND_COUNT=0
AHEAD_COUNT=0
UPSTREAM=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
if [[ -n "$UPSTREAM" ]]; then
  COUNTS=$(git -C "$REPO_ROOT" rev-list --left-right --count "$UPSTREAM...HEAD" 2>/dev/null || echo "0	0")
  BEHIND_COUNT=$(echo "$COUNTS" | awk '{print $1}')
  AHEAD_COUNT=$(echo "$COUNTS" | awk '{print $2}')
fi

if [[ "$LATEST_TAG" == "v0.0.0" ]]; then
  COMMITS=$(git -C "$REPO_ROOT" log --oneline --no-merges 2>/dev/null || true)
else
  COMMITS=$(git -C "$REPO_ROOT" log "${LATEST_TAG}..HEAD" --oneline --no-merges 2>/dev/null || true)
fi

CLEAN_TAG="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CLEAN_TAG"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

BUMP="none"
BREAKING=()
FEATURES=()
FIXES=()
OTHERS=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  msg=$(echo "$line" | sed -E 's/^[a-f0-9]+[[:space:]]+//')

  if echo "$msg" | grep -iE 'BREAKING[[:space:]]+CHANGE|!:' >/dev/null 2>&1; then
    BREAKING+=("$msg")
    BUMP="major"
  elif echo "$msg" | grep -E '^feat(\([^\)]+\))?:' >/dev/null 2>&1; then
    FEATURES+=("$msg")
    [[ "$BUMP" != "major" ]] && BUMP="minor"
  elif echo "$msg" | grep -E '^fix(\([^\)]+\))?:' >/dev/null 2>&1; then
    FIXES+=("$msg")
    [[ "$BUMP" != "major" && "$BUMP" != "minor" ]] && BUMP="patch"
  else
    OTHERS+=("$msg")
    [[ "$BUMP" == "none" ]] && BUMP="patch"
  fi
done <<< "$COMMITS"

if [[ "$BUMP" == "major" ]]; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
elif [[ "$BUMP" == "minor" ]]; then
  MINOR=$((MINOR + 1))
  PATCH=0
elif [[ "$BUMP" == "patch" ]]; then
  PATCH=$((PATCH + 1))
fi

NEXT_TAG="v${MAJOR}.${MINOR}.${PATCH}"

TAG_PUSHED=false
if [[ "$EXECUTE" == "true" ]]; then
  if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "Error: Cannot tag release on branch '$CURRENT_BRANCH': releases must be created strictly on 'main'." >&2
    exit 1
  fi
  if [[ "$IS_CLEAN" != "true" ]]; then
    echo "Error: Working tree has uncommitted host files. Commit or stash changes before releasing." >&2
    exit 1
  fi
  if [[ "$BEHIND_COUNT" -gt 0 ]]; then
    echo "Error: Local branch is behind origin/main ($BEHIND_COUNT commits). Run 'git pull origin main' first." >&2
    exit 1
  fi

  git -C "$REPO_ROOT" tag -a "$NEXT_TAG" -m "Release $NEXT_TAG" >/dev/null 2>&1
  git -C "$REPO_ROOT" push origin "$NEXT_TAG" >/dev/null 2>&1
  TAG_PUSHED=true
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"current_branch\":\"$CURRENT_BRANCH\",\"is_main\":$([[ "$CURRENT_BRANCH" == "main" ]] && echo true || echo false),\"is_clean\":$IS_CLEAN,\"behind_origin\":$BEHIND_COUNT,\"ahead_origin\":$AHEAD_COUNT,\"current_version\":\"$LATEST_TAG\",\"next_version\":\"$NEXT_TAG\",\"bump_type\":\"$BUMP\",\"tag_pushed\":$TAG_PUSHED}"
else
  if [[ "$TAG_PUSHED" == "true" ]]; then
    echo "Release Tag: SUCCESS $NEXT_TAG created and pushed on main"
  else
    echo "SemVer Pre-Flight: $LATEST_TAG -> $NEXT_TAG (Bump: $BUMP, Branch: $CURRENT_BRANCH)"
  fi
fi
