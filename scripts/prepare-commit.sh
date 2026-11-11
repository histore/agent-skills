#!/usr/bin/env bash
# ==============================================================================
# Deterministic zero-token commit preparation:
# - Detects & optionally reverts whitespace/CRLF-only diffs against HEAD
# - Distinguishes unambiguous CRLF regressions from legacy CRLF files
# - Runs deferred tech-stack format check and final guardrails/Clean Arch
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
REVERT_WS=false
FIX_EOL=false
FORMAT_FIX=false
FORCE_NORMALIZE=false
DIRECT_MODE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --revert-whitespace-only)
      REVERT_WS=true
      shift
      ;;
    --fix-line-endings)
      FIX_EOL=true
      shift
      ;;
    --format)
      FORMAT_FIX=true
      shift
      ;;
    --force-normalize)
      FORCE_NORMALIZE=true
      shift
      ;;
    --direct)
      DIRECT_MODE=true
      shift
      ;;
    --json|-j)
      JSON_OUTPUT=true
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

if [[ -z "$REPO_ROOT" ]]; then
  SUPERPROJECT=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
  if [[ -n "$SUPERPROJECT" ]]; then
    REPO_ROOT="$SUPERPROJECT"
  else
    TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$TOPLEVEL" ]]; then
      REPO_ROOT="$TOPLEVEL"
      [[ "$REPO_ROOT" =~ /(_agents|\.agents)$ ]] && REPO_ROOT="$(dirname "$REPO_ROOT")"
    else
      REPO_ROOT="$(pwd)"
    fi
  fi
fi

DO_REVERT_WS=false
DO_FIX_EOL=false
if [[ "$REVERT_WS" == "true" || "$DIRECT_MODE" == "true" ]]; then DO_REVERT_WS=true; fi
if [[ "$FIX_EOL" == "true" || "$DIRECT_MODE" == "true" ]]; then DO_FIX_EOL=true; fi

HAS_HEAD=false
if git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
  HAS_HEAD=true
fi

HOST_FILES=()
SUBMODULE_FILES=()
WS_ONLY_FILES=()
REVERTED_WS_FILES=()
CRLF_FILES=()
AMBIGUOUS_FILES=()
NORMALIZED_FILES=()

UNTRACKED_LIST=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true)

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ "$rel" =~ ^(\.agents|_agents)(/|$) ]]; then
    SUBMODULE_FILES+=("$rel")
    continue
  fi

  full="${REPO_ROOT}/${rel}"
  if [[ ! -f "$full" ]]; then
    HOST_FILES+=("$rel")
    continue
  fi

  is_untracked=false
  if printf '%s\n' "$UNTRACKED_LIST" | grep -Fxq "$rel"; then
    is_untracked=true
  fi

  if [[ "$is_untracked" == "false" && "$HAS_HEAD" == "true" ]]; then
    raw_diff=$(git -C "$REPO_ROOT" diff HEAD -- "$rel" 2>/dev/null || true)
    ws_diff=$(git -C "$REPO_ROOT" diff -w HEAD -- "$rel" 2>/dev/null || true)
    if [[ -n "$raw_diff" && -z "$ws_diff" ]]; then
      if [[ "$DO_REVERT_WS" == "true" ]]; then
        if git -C "$REPO_ROOT" checkout -- "$rel" 2>/dev/null; then
          REVERTED_WS_FILES+=("$rel")
          continue
        fi
      fi
      WS_ONLY_FILES+=("$rel")
    fi
  fi

  HOST_FILES+=("$rel")

  if file -b --mime "$full" 2>/dev/null | grep -q 'text' && grep -q $'\r' "$full" 2>/dev/null; then
    is_ambiguous=false
    if [[ "$is_untracked" == "false" ]]; then
      eol_info=$(git -C "$REPO_ROOT" ls-files --eol -- "$rel" 2>/dev/null || true)
      if [[ "$eol_info" =~ i/crlf && ! "$eol_info" =~ eol=lf ]]; then
        is_ambiguous=true
      fi
    fi

    if [[ "$is_ambiguous" == "true" && "$FORCE_NORMALIZE" != "true" ]]; then
      AMBIGUOUS_FILES+=("$rel")
    elif [[ "$DO_FIX_EOL" == "true" || ( "$is_ambiguous" == "true" && "$FORCE_NORMALIZE" == "true" ) ]]; then
      tr -d '\r' < "$full" > "${full}.tmp" && mv "${full}.tmp" "$full"
      NORMALIZED_FILES+=("$rel")
    else
      CRLF_FILES+=("$rel")
    fi
  fi
done < <({
  git -C "$REPO_ROOT" diff --name-only --cached 2>/dev/null || true
  git -C "$REPO_ROOT" diff --name-only 2>/dev/null || true
  printf '%s\n' "$UNTRACKED_LIST"
} | sort -u)

FORMAT_STATUS="skipped"
FORMAT_CMD=""
FORMAT_FIX_CMD=""
FORMAT_ERRORS=()
HAS_EXEC=false
for f in "${HOST_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql)$ ]]; then
    HAS_EXEC=true
    break
  fi
done

if [[ "$HAS_EXEC" == "true" && -f "${SCRIPT_DIR}/detect-tech-stack.sh" ]]; then
  STACK_JSON=$(bash "${SCRIPT_DIR}/detect-tech-stack.sh" "$REPO_ROOT" --json 2>/dev/null || echo '{}')
  if command -v python3 &>/dev/null; then
    {
      IFS= read -r FORMAT_CMD || true
      IFS= read -r FORMAT_FIX_CMD || true
    } < <(python3 - "$STACK_JSON" << 'EOF' 2>/dev/null || true
import json, sys
d = json.loads(sys.argv[1])
print(d.get('format_check_cmd', ''))
print(d.get('format_fix_cmd', ''))
EOF
    )
  fi

  if [[ -n "$FORMAT_CMD" ]]; then
    LAST_FMT_OUT=""
    run_fmt_check() {
      local fmt_out=""
      local rc=0
      fmt_out=$(cd "$REPO_ROOT" && eval "$FORMAT_CMD" 2>&1) || rc=$?
      LAST_FMT_OUT="$fmt_out"
      if [[ $rc -ne 0 ]]; then
        return 1
      fi
      if [[ "$FORMAT_CMD" =~ ^gofmt[[:space:]]+-l && -n "$fmt_out" ]]; then
        return 1
      fi
      return 0
    }

    if run_fmt_check; then
      FORMAT_STATUS="pass"
    else
      if [[ "$FORMAT_FIX" == "true" && -n "$FORMAT_FIX_CMD" && ${#AMBIGUOUS_FILES[@]} -eq 0 ]]; then
        (cd "$REPO_ROOT" && eval "$FORMAT_FIX_CMD") >/dev/null 2>&1 || true
        if run_fmt_check; then
          FORMAT_STATUS="pass"
        else
          FORMAT_STATUS="fail"
        fi
      else
        FORMAT_STATUS="fail"
      fi
      if [[ "$FORMAT_STATUS" == "fail" && -n "$LAST_FMT_OUT" ]]; then
        while IFS= read -r line; do
          [[ -n "${line// /}" ]] && FORMAT_ERRORS+=("$line")
        done < <(printf '%s\n' "$LAST_FMT_OUT" | head -n 10)
      fi
    fi
  fi
fi

GUARDRAILS_STATUS="pass"
GUARDRAIL_ERRORS=()
if [[ ${#HOST_FILES[@]} -gt 0 && -f "${SCRIPT_DIR}/scan-guardrails.sh" ]]; then
  SCAN_ARGS=("--path" "$REPO_ROOT" "--working-tree")
  if [[ ${#AMBIGUOUS_FILES[@]} -gt 0 || ${#CRLF_FILES[@]} -gt 0 || ${#WS_ONLY_FILES[@]} -gt 0 ]]; then
    SCAN_ARGS+=("--skip-line-endings")
  fi
  SCAN_OUT=""
  if ! SCAN_OUT=$(bash "${SCRIPT_DIR}/scan-guardrails.sh" "${SCAN_ARGS[@]}" 2>&1); then
    GUARDRAILS_STATUS="fail"
    while IFS= read -r line; do
      [[ -n "${line// /}" ]] && GUARDRAIL_ERRORS+=("$line")
    done < <(printf '%s\n' "$SCAN_OUT" | grep -E 'FAIL|Violation|\[|Error' | head -n 10 || true)
    if [[ ${#GUARDRAIL_ERRORS[@]} -eq 0 && -n "$SCAN_OUT" ]]; then
      GUARDRAIL_ERRORS+=("scan-guardrails.sh failed")
    fi
  fi
fi

ARCH_STATUS="pass"
if [[ ${#HOST_FILES[@]} -gt 0 && -f "${SCRIPT_DIR}/lint-clean-architecture.sh" ]]; then
  ARCH_OUT=""
  if ! ARCH_OUT=$(bash "${SCRIPT_DIR}/lint-clean-architecture.sh" "$REPO_ROOT" --working-tree 2>&1); then
    ARCH_STATUS="fail"
    while IFS= read -r line; do
      [[ -n "${line// /}" ]] && GUARDRAIL_ERRORS+=("$line")
    done < <(printf '%s\n' "$ARCH_OUT" | grep -E 'Error|FAIL|Violation' | head -n 10 || true)
    if [[ ${#GUARDRAIL_ERRORS[@]} -eq 0 && -n "$ARCH_OUT" ]]; then
      GUARDRAIL_ERRORS+=("lint-clean-architecture.sh failed")
    fi
  fi
fi

STATUS="ready"
if [[ ${#HOST_FILES[@]} -eq 0 && ${#REVERTED_WS_FILES[@]} -gt 0 ]]; then
  STATUS="clean"
elif [[ ${#HOST_FILES[@]} -eq 0 ]]; then
  STATUS="no_changes"
elif [[ "$GUARDRAILS_STATUS" == "fail" || "$ARCH_STATUS" == "fail" || "$FORMAT_STATUS" == "fail" || ${#SUBMODULE_FILES[@]} -gt 0 ]]; then
  STATUS="fail"
elif [[ ${#WS_ONLY_FILES[@]} -gt 0 || ${#AMBIGUOUS_FILES[@]} -gt 0 || ${#CRLF_FILES[@]} -gt 0 ]]; then
  STATUS="needs_decision"
fi

case "$STATUS" in
  clean) NEXT_STEP="nothing_to_commit_whitespace_reverted" ;;
  no_changes) NEXT_STEP="nothing_to_commit" ;;
  needs_decision) NEXT_STEP="ask_user_normalization" ;;
  fail) NEXT_STEP="resolve_format_or_guardrail_errors" ;;
  ready) NEXT_STEP=$([[ "$DIRECT_MODE" == "true" ]] && echo "execute_commit" || echo "present_commit_message") ;;
esac

SUGGESTED_COMMIT=""
if [[ "$STATUS" == "ready" && ${#HOST_FILES[@]} -gt 0 ]]; then
  all_docs=true
  all_meta=true
  has_tests=false
  for f in "${HOST_FILES[@]}"; do
    [[ ! "$f" =~ (\.md$|^docs/) ]] && all_docs=false
    [[ ! "$f" =~ (\.md$|^(docs/|scripts/|rules/|skills/|evals/|\.github/)|^\.(gitignore|gitattributes|editorconfig)$) ]] && all_meta=false
    [[ "$f" =~ (^|/)(tests?|specs?)/|(\.|_)(test|spec)\. ]] && has_tests=true
  done
  if [[ "$all_docs" == "true" ]]; then
    prefix="docs"; scope="docs"
  elif [[ "$all_meta" == "true" ]]; then
    prefix="chore"; scope="tooling"
  elif [[ "$has_tests" == "true" ]]; then
    prefix="test"; scope="tests"
  else
    prefix="feat"; scope="core"
  fi
  first_base=$(basename "${HOST_FILES[0]}")
  first_leaf="${first_base%.*}"
  if [[ ${#HOST_FILES[@]} -eq 1 ]]; then
    SUGGESTED_COMMIT="${prefix}(${scope}): update ${first_leaf}"
  else
    SUGGESTED_COMMIT="${prefix}(${scope}): update ${first_leaf} and $((${#HOST_FILES[@]} - 1)) additional file(s)"
  fi
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

join_csv() {
  local out="" item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ -z "$out" ]]; then
      out="$item"
    else
      out="${out}, ${item}"
    fi
  done
  printf '%s' "$out"
}

MODE_NAME=$([[ "$DIRECT_MODE" == "true" ]] && echo "direct" || echo "prepare")

if [[ "$JSON_OUTPUT" == "true" ]]; then
  escaped_commit=$(json_escape "$SUGGESTED_COMMIT")
  echo "{\"status\":\"$STATUS\",\"mode\":\"$MODE_NAME\",\"next_step\":\"$NEXT_STEP\",\"host_files_count\":${#HOST_FILES[@]},\"reverted_whitespace_count\":${#REVERTED_WS_FILES[@]},\"normalized_count\":${#NORMALIZED_FILES[@]},\"whitespace_only_count\":${#WS_ONLY_FILES[@]},\"crlf_count\":${#CRLF_FILES[@]},\"ambiguous_count\":${#AMBIGUOUS_FILES[@]},\"submodule_count\":${#SUBMODULE_FILES[@]},\"format_status\":\"$FORMAT_STATUS\",\"guardrails_status\":\"$GUARDRAILS_STATUS\",\"arch_status\":\"$ARCH_STATUS\",\"suggested_commit_message\":\"$escaped_commit\"}"
else
  echo "============================================="
  echo "Commit Preparation ($([[ "$DIRECT_MODE" == "true" ]] && echo "DIRECT" || echo "PREPARE"))"
  echo "============================================="
  echo "Status: $STATUS | Next Step: $NEXT_STEP"
  if [[ ${#REVERTED_WS_FILES[@]} -gt 0 ]]; then echo "Reverted whitespace-only files: $(join_csv "${REVERTED_WS_FILES[@]}")"; fi
  if [[ ${#NORMALIZED_FILES[@]} -gt 0 ]]; then echo "Normalized CRLF -> LF: $(join_csv "${NORMALIZED_FILES[@]}")"; fi
  if [[ ${#WS_ONLY_FILES[@]} -gt 0 ]]; then echo "Whitespace-only diffs awaiting revert (--revert-whitespace-only): $(join_csv "${WS_ONLY_FILES[@]}")"; fi
  if [[ ${#CRLF_FILES[@]} -gt 0 ]]; then echo "Unambiguous CRLF files (--fix-line-endings): $(join_csv "${CRLF_FILES[@]}")"; fi
  if [[ ${#AMBIGUOUS_FILES[@]} -gt 0 ]]; then echo "Ambiguous legacy CRLF files (user decision required, --force-normalize): $(join_csv "${AMBIGUOUS_FILES[@]}")"; fi
  if [[ ${#SUBMODULE_FILES[@]} -gt 0 ]]; then echo "Submodule changes detected (must not be committed in host repo): $(join_csv "${SUBMODULE_FILES[@]}")"; fi
  if [[ "$FORMAT_STATUS" == "fail" ]]; then echo "Format check failed ($FORMAT_CMD): $(join_csv "${FORMAT_ERRORS[@]:-}")"; fi
  if [[ ${#GUARDRAIL_ERRORS[@]} -gt 0 ]]; then echo "Errors: $(join_csv "${GUARDRAIL_ERRORS[@]}")"; fi
  if [[ -n "$SUGGESTED_COMMIT" ]]; then echo "Suggested Commit: $SUGGESTED_COMMIT"; fi
fi

if [[ "$STATUS" == "fail" || "$STATUS" == "needs_decision" ]]; then
  exit 1
fi
