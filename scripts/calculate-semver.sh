#!/usr/bin/env bash
# ==============================================================================
# Calculates next SemVer bump and draft changelog deterministically from Conventional Commits.
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
JSON_OUTPUT=false

for arg in "$@"; do
  if [[ "$arg" == "--json" || "$arg" == "-j" ]]; then
    JSON_OUTPUT=true
  fi
done

LATEST_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

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

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"current_version\":\"$LATEST_TAG\",\"next_version\":\"$NEXT_TAG\",\"bump_type\":\"$BUMP\"}"
else
  echo "============================================="
  echo "Deterministic SemVer Calculator"
  echo "Current: $LATEST_TAG -> Next: $NEXT_TAG (Bump: $BUMP)"
  echo "============================================="
fi
