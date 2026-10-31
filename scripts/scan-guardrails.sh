#!/usr/bin/env bash
# ==============================================================================
# Deterministic code guardrails scanner (Safe-Rust, Secrets, CRLF, Submodule leakage).
# ==============================================================================
set -euo pipefail

SCAN_PATH="${1:-$(pwd)}"
STAGED_ONLY=false
WORKING_TREE=false
FIX=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      SCAN_PATH="$2"
      shift 2
      ;;
    --staged)
      STAGED_ONLY=true
      shift
      ;;
    --working-tree)
      WORKING_TREE=true
      shift
      ;;
    --fix|-f)
      FIX=true
      shift
      ;;
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      [[ -d "$1" ]] && SCAN_PATH="$1"
      shift
      ;;
  esac
done

VIOLATIONS=()

# 1. Collect files
FILES=()
if [[ "$STAGED_ONLY" == "true" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" && -f "${SCAN_PATH}/$f" ]] && FILES+=("${SCAN_PATH}/$f")
  done < <(git -C "$SCAN_PATH" diff --name-only --cached 2>/dev/null || true)
elif [[ "$WORKING_TREE" == "true" ]]; then
  if [[ "$(git -C "$SCAN_PATH" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]]; then
    while IFS= read -r f; do
      if [[ -n "$f" && ! "$f" =~ ^(\.agents|_agents)/ && -f "${SCAN_PATH}/$f" ]]; then
        FILES+=("${SCAN_PATH}/$f")
      fi
    done < <({
      git -C "$SCAN_PATH" diff --name-only --cached 2>/dev/null || true
      git -C "$SCAN_PATH" diff --name-only 2>/dev/null || true
      git -C "$SCAN_PATH" ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u)
  else
    while IFS= read -r f; do
      FILES+=("$f")
    done < <(find "$SCAN_PATH" -type f \
      -not -path '*/\.git/*' \
      -not -path '*/_agents/*' \
      -not -path '*/\.agents/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/target/*' \
      -not -path '*/bin/*' \
      -not -path '*/obj/*')
  fi
else
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$SCAN_PATH" -type f \
    -not -path '*/\.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/target/*' \
    -not -path '*/bin/*' \
    -not -path '*/obj/*' \
    -not -path '*/publish/*' \
    -not -path '*/artifacts/*')
fi

# 2. Scan files
for file in "${FILES[@]}"; do
  rel_path="${file#"${SCAN_PATH}/"}"

  # Submodule leakage check
  if [[ "$STAGED_ONLY" == "true" && ("$rel_path" =~ ^\.agents/ || "$rel_path" =~ ^_agents/) ]]; then
    VIOLATIONS+=("[SubmoduleIsolation] ${rel_path}: Staged change originates inside submodule path")
  fi

  # CRLF check
  if file -b --mime "$file" 2>/dev/null | grep -q 'text'; then
    if grep -q $'\r' "$file" 2>/dev/null; then
      if [[ "$FIX" == "true" ]]; then
        tr -d '\r' < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        if [[ "$STAGED_ONLY" == "true" ]]; then
          git -C "$SCAN_PATH" add "$file" 2>/dev/null || true
        fi
      else
        VIOLATIONS+=("[LineEndings] ${rel_path}: CRLF line endings detected (must be LF)")
      fi
    fi

    # Safe-Rust check (blocks, pub/async unsafe fn, unsafe impl/trait/extern, Rust 2024 #[unsafe(...)])
    if [[ "$file" == *.rs ]]; then
      if sed -E 's|//.*$||; s|"((\\.)|[^"\\])*"|""|g' "$file" | grep -nE '((^|[^[:alnum:]_])unsafe[[:space:]]*(\{|fn([^[:alnum:]_]|$)|impl([^[:alnum:]_]|$)|trait([^[:alnum:]_]|$)|extern([^[:alnum:]_]|$))|#\[[[:space:]]*unsafe[[:space:]]*\()' >/dev/null 2>&1; then
        VIOLATIONS+=("[SafeRust] ${rel_path}: Forbidden unsafe construct detected in safe-Rust codebase")
      fi
    fi

    # Secret patterns
    if grep -nE -- '-----BEGIN (RSA|EC|DSA|OPENSSH)?\s*PRIVATE KEY-----' "$file" >/dev/null 2>&1; then
      VIOLATIONS+=("[SecretDetection] ${rel_path}: Potential private key detected")
    fi
    if grep -nE -- '(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}' "$file" >/dev/null 2>&1; then
      VIOLATIONS+=("[SecretDetection] ${rel_path}: Potential AWS access key detected")
    fi
    if grep -nE -- 'gh[pousr]_[A-Za-z0-9_]{36,255}' "$file" >/dev/null 2>&1; then
      VIOLATIONS+=("[SecretDetection] ${rel_path}: Potential GitHub Personal Token detected")
    fi
  fi
done

TOTAL_VIOLATIONS=${#VIOLATIONS[@]}

if [[ "$JSON_OUTPUT" == "true" ]]; then
  if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo "{\"status\":\"pass\",\"scanned_files_count\":${#FILES[@]},\"violations_count\":0,\"violations\":[]}"
  else
    echo "{\"status\":\"fail\",\"scanned_files_count\":${#FILES[@]},\"violations_count\":$TOTAL_VIOLATIONS}"
  fi
else
  echo "============================================="
  echo "Deterministic Guardrails Scanner"
  echo "Scanned Files: ${#FILES[@]} | Violations: $TOTAL_VIOLATIONS"
  echo "============================================="
  if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo "Guardrails Status: PASS (0 violations)"
  else
    echo "Guardrails Status: FAIL ($TOTAL_VIOLATIONS violations)"
    for v in "${VIOLATIONS[@]}"; do
      echo "  $v"
    done
  fi
  echo "============================================="
fi

if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
  exit 1
fi
