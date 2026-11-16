#!/usr/bin/env bash
# ==============================================================================
# Calculates next SemVer bump and draft changelog deterministically from Conventional Commits.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(pwd)"
JSON_OUTPUT=false
CHECK_SYNC=false
EXECUTE=false
VERSION_OVERRIDE=""

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
    --version-override)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --version-override=*)
      VERSION_OVERRIDE="${1#*=}"
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
    --execute|--execute-tag-and-push)
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

CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
[[ -z "$CURRENT_BRANCH" ]] && CURRENT_BRANCH="HEAD"
LATEST_TAG=$(git -C "$REPO_ROOT" tag -l "v[0-9]*" --sort=-v:refname 2>/dev/null | head -n 1 || echo "")
[[ -z "$LATEST_TAG" ]] && LATEST_TAG="v0.0.0"

IS_CLEAN=true
UNCOMMITTED=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -v -E '^[MADRCU?![:space:]]+ (_agents|\.agents)(/|$)' || true)
if [[ -n "$UNCOMMITTED" ]]; then
  IS_CLEAN=false
fi

BEHIND_COUNT=0
AHEAD_COUNT=0
if [[ "$CHECK_SYNC" == "true" || "$EXECUTE" == "true" ]]; then
  git -C "$REPO_ROOT" fetch origin main >/dev/null 2>&1 || true
  COUNTS=$(git -C "$REPO_ROOT" rev-list --left-right --count "main...origin/main" 2>/dev/null || true)
  if [[ -n "$COUNTS" ]]; then
    read -r AHEAD_COUNT BEHIND_COUNT <<< "$COUNTS" || true
    AHEAD_COUNT="${AHEAD_COUNT:-0}"
    BEHIND_COUNT="${BEHIND_COUNT:-0}"
  fi
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

if [[ -n "$VERSION_OVERRIDE" ]]; then
  if [[ "$VERSION_OVERRIDE" == v* ]]; then
    NEXT_TAG="$VERSION_OVERRIDE"
  else
    NEXT_TAG="v${VERSION_OVERRIDE}"
  fi
else
  NEXT_TAG="v${MAJOR}.${MINOR}.${PATCH}"
fi

COMMITS_ANALYZED=$(( ${#BREAKING[@]} + ${#FEATURES[@]} + ${#FIXES[@]} + ${#OTHERS[@]} ))

NOTES="## Release ${NEXT_TAG}"$'\n'
if [[ ${#BREAKING[@]} -gt 0 ]]; then
  NOTES+="### Breaking Changes"$'\n'
  for b in "${BREAKING[@]}"; do NOTES+="- ${b}"$'\n'; done
fi
if [[ ${#FEATURES[@]} -gt 0 ]]; then
  NOTES+="### Features"$'\n'
  for f in "${FEATURES[@]}"; do NOTES+="- ${f}"$'\n'; done
fi
if [[ ${#FIXES[@]} -gt 0 ]]; then
  NOTES+="### Bug Fixes"$'\n'
  for fx in "${FIXES[@]}"; do NOTES+="- ${fx}"$'\n'; done
fi
if [[ ${#OTHERS[@]} -gt 0 ]]; then
  NOTES+="### Maintenance & Documentation"$'\n'
  for o in "${OTHERS[@]}"; do NOTES+="- ${o}"$'\n'; done
fi
NOTES="${NOTES%$'\n'}"

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

sv_json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

sv_json_arr() {
  local out="" item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    [[ -n "$out" ]] && out+=","
    out+="\"$(sv_json_esc "$item")\""
  done
  printf '[%s]' "$out"
}

if [[ "$JSON_OUTPUT" == "true" ]]; then
  BRK_JSON=$(sv_json_arr "${BREAKING[@]:-}")
  FEAT_JSON=$(sv_json_arr "${FEATURES[@]:-}")
  FIX_JSON=$(sv_json_arr "${FIXES[@]:-}")
  NOTES_JSON=$(sv_json_esc "$NOTES")
  echo "{\"current_branch\":\"$(sv_json_esc "$CURRENT_BRANCH")\",\"is_main\":$([[ "$CURRENT_BRANCH" == "main" ]] && echo true || echo false),\"is_clean\":$IS_CLEAN,\"behind_origin\":$BEHIND_COUNT,\"ahead_origin\":$AHEAD_COUNT,\"current_version\":\"$LATEST_TAG\",\"next_version\":\"$NEXT_TAG\",\"bump_type\":\"$BUMP\",\"commits_analyzed\":$COMMITS_ANALYZED,\"breaking_changes\":$BRK_JSON,\"features\":$FEAT_JSON,\"fixes\":$FIX_JSON,\"release_notes\":\"$NOTES_JSON\",\"tag_pushed\":$TAG_PUSHED}"
else
  if [[ "$TAG_PUSHED" == "true" ]]; then
    echo "Release Tag: SUCCESS $NEXT_TAG created and pushed on main"
  else
    echo "SemVer Pre-Flight: $LATEST_TAG -> $NEXT_TAG (Bump: $BUMP, Branch: $CURRENT_BRANCH)"
  fi
fi
