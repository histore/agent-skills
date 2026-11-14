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

OS_UNAME="$(uname -s 2>/dev/null || echo "")"
case "$OS_UNAME" in
  MINGW*|MSYS*|CYGWIN*) DEFAULT_TARGET_EOL="CRLF" ;;
  *) DEFAULT_TARGET_EOL="LF" ;;
esac

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

CANDIDATES_LIST=$( {
  git -C "$REPO_ROOT" diff --name-only --cached 2>/dev/null || true
  git -C "$REPO_ROOT" diff --name-only 2>/dev/null || true
  printf '%s\n' "$UNTRACKED_LIST"
} | sort -u )

# Resolve project-level EOL overrides (.gitattributes / .editorconfig) in a single batch
EOL_SKIP_LIST=""
EOL_LF_LIST=""
EOL_CRLF_LIST=""

if [[ -n "$CANDIDATES_LIST" ]]; then
  if [[ -f "${REPO_ROOT}/.gitattributes" ]]; then
    CUR_SKIP="" ; CUR_EOL="" ; CUR_PATH=""
    while IFS= read -r -d '' p && IFS= read -r -d '' attr && IFS= read -r -d '' val; do
      if [[ "$p" != "$CUR_PATH" ]]; then
        if [[ -n "$CUR_PATH" ]]; then
          if [[ "$CUR_SKIP" == "true" ]]; then EOL_SKIP_LIST+="${CUR_PATH}"$'\n'
          elif [[ "$CUR_EOL" == "LF" ]]; then EOL_LF_LIST+="${CUR_PATH}"$'\n'
          elif [[ "$CUR_EOL" == "CRLF" ]]; then EOL_CRLF_LIST+="${CUR_PATH}"$'\n'
          fi
        fi
        CUR_PATH="$p"; CUR_SKIP="false"; CUR_EOL=""
      fi
      if [[ "$attr" == "text" && "$val" == "unset" ]]; then
        CUR_SKIP="true"
      elif [[ "$attr" == "eol" ]]; then
        if [[ "$val" == "lf" ]]; then CUR_EOL="LF"
        elif [[ "$val" == "crlf" ]]; then CUR_EOL="CRLF"
        fi
      fi
    done < <(printf '%s\n' "$CANDIDATES_LIST" | tr '\n' '\0' | git -C "$REPO_ROOT" check-attr --stdin -z text eol 2>/dev/null || true)
    if [[ -n "$CUR_PATH" ]]; then
      if [[ "$CUR_SKIP" == "true" ]]; then EOL_SKIP_LIST+="${CUR_PATH}"$'\n'
      elif [[ "$CUR_EOL" == "LF" ]]; then EOL_LF_LIST+="${CUR_PATH}"$'\n'
      elif [[ "$CUR_EOL" == "CRLF" ]]; then EOL_CRLF_LIST+="${CUR_PATH}"$'\n'
      fi
    fi
  fi

  if [[ -f "${REPO_ROOT}/.editorconfig" ]] && command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r ov_rel ov_eol; do
      [[ -z "$ov_rel" ]] && continue
      if [[ $'\n'"$EOL_SKIP_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* || $'\n'"$EOL_LF_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* || $'\n'"$EOL_CRLF_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* ]]; then
        continue
      fi
      case "$ov_eol" in
        LF)   EOL_LF_LIST+="${ov_rel}"$'\n' ;;
        CRLF) EOL_CRLF_LIST+="${ov_rel}"$'\n' ;;
      esac
    done < <(printf '%s\n' "$CANDIDATES_LIST" | python3 - "${REPO_ROOT}/.editorconfig" << 'EOF' 2>/dev/null || true
import re, sys

ec_path = sys.argv[1]
def glob_to_regex(pat):
    has_slash = '/' in pat
    p = pat.lstrip('/')
    out = ['^' if has_slash else '(?:^|/)']
    i = 0
    while i < len(p):
        if p.startswith('**/', i):
            out.append('(?:.*/)?')
            i += 3
            continue
        c = p[i]
        if c == '*':
            if i + 1 < len(p) and p[i + 1] == '*':
                out.append('.*')
                i += 2
                continue
            out.append('[^/]*')
        elif c == '?':
            out.append('[^/]')
        elif c == '{' and '}' in p[i+1:]:
            close = p.index('}', i + 1)
            alts = [re.escape(x) for x in p[i+1:close].split(',')]
            out.append('(?:' + '|'.join(alts) + ')')
            i = close + 1
            continue
        else:
            out.append(re.escape(c))
        i += 1
    out.append('$')
    return re.compile(''.join(out))

ec_rules = []
cur_rx = None
with open(ec_path, 'r', encoding='utf-8', errors='ignore') as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith('#') or line.startswith(';'): continue
        m = re.match(r'^\[(.+)\]$', line)
        if m:
            cur_rx = glob_to_regex(m.group(1).strip())
        elif cur_rx is not None:
            m2 = re.match(r'^end_of_line\s*=\s*(lf|crlf)\b', line, re.I)
            if m2:
                ec_rules.append((cur_rx, m2.group(1).upper()))

for rel in sys.stdin:
    rel = rel.rstrip('\r\n')
    if not rel: continue
    res = None
    for rx, val in ec_rules:
        if rx.search(rel): res = val
    if res:
        print(f"{rel}\t{res}")
EOF
    )
  fi
fi

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

  is_text=false
  if command -v file >/dev/null 2>&1; then
    if file -b --mime "$full" 2>/dev/null | grep -q 'text'; then
      is_text=true
    fi
  else
    file_name="$(basename "$full")"
    if [[ "$file_name" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|json|md|yml|yaml|toml|ps1|sh|axaml|props|targets|xml|txt|csproj|sln|editorconfig|gitattributes|gitignore|manifest)$ ]] || \
       [[ "$file_name" =~ ^(LICENSE|NOTICE|AUTHORS|CODEOWNERS)$ ]]; then
      is_text=true
    fi
  fi

  if [[ "$is_text" == "true" ]]; then
    eff_eol="$DEFAULT_TARGET_EOL"
    has_override=false
    if [[ $'\n'"$EOL_SKIP_LIST"$'\n' == *$'\n'"$rel"$'\n'* ]]; then
      eff_eol="SKIP"
      has_override=true
    elif [[ $'\n'"$EOL_LF_LIST"$'\n' == *$'\n'"$rel"$'\n'* ]]; then
      eff_eol="LF"
      has_override=true
    elif [[ $'\n'"$EOL_CRLF_LIST"$'\n' == *$'\n'"$rel"$'\n'* ]]; then
      eff_eol="CRLF"
      has_override=true
    fi

    needs_norm=false
    if [[ "$eff_eol" == "CRLF" ]]; then
      if awk '{ if (/\r[^\r]/ || !/\r$/) { found=1; exit } } END { exit !found }' "$full" 2>/dev/null; then
        needs_norm=true
      fi
    elif [[ "$eff_eol" == "LF" ]]; then
      if grep -q $'\r' "$full" 2>/dev/null; then
        needs_norm=true
      fi
    fi

    if [[ "$needs_norm" == "true" ]]; then
      is_ambiguous=false
      if [[ "$has_override" == "false" && "$is_untracked" == "false" ]]; then
        eol_info=$(git -C "$REPO_ROOT" ls-files --eol -- "$rel" 2>/dev/null || true)
        if [[ "$eff_eol" == "LF" ]]; then
          if [[ "$eol_info" =~ i/crlf && ! "$eol_info" =~ eol=lf ]]; then
            is_ambiguous=true
          fi
        else
          if [[ "$eol_info" =~ i/lf && ! "$eol_info" =~ eol=crlf ]]; then
            is_ambiguous=true
          fi
        fi
      fi

      if [[ "$is_ambiguous" == "true" && "$FORCE_NORMALIZE" != "true" ]]; then
        AMBIGUOUS_FILES+=("$rel")
      elif [[ "$DO_FIX_EOL" == "true" || ( "$is_ambiguous" == "true" && "$FORCE_NORMALIZE" == "true" ) ]]; then
        if [[ "$eff_eol" == "CRLF" ]]; then
          awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$full" > "${full}.tmp" && mv "${full}.tmp" "$full"
        else
          tr -d '\r' < "$full" > "${full}.tmp" && mv "${full}.tmp" "$full"
        fi
        NORMALIZED_FILES+=("$rel")
      else
        CRLF_FILES+=("$rel")
      fi
    fi
  fi
done <<< "$CANDIDATES_LIST"

FORMAT_STATUS="skipped"
FORMAT_CMD=""
FORMAT_FIX_CMD=""
FORMAT_ERRORS=()
HAS_EXEC=false
for f in "${HOST_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql)$ ]]; then
    HAS_EXEC=true
    break
  fi
done

HAS_DECISION_ITEMS=false
if [[ ${#WS_ONLY_FILES[@]} -gt 0 || ${#AMBIGUOUS_FILES[@]} -gt 0 || ${#CRLF_FILES[@]} -gt 0 ]]; then
  HAS_DECISION_ITEMS=true
fi

if [[ "$HAS_EXEC" == "true" && "$HAS_DECISION_ITEMS" == "false" && ${#SUBMODULE_FILES[@]} -eq 0 && -f "${SCRIPT_DIR}/detect-tech-stack.sh" ]]; then
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
        if (cd "$REPO_ROOT" && eval "$FORMAT_FIX_CMD") >/dev/null 2>&1; then
          for rel_fmt in "${HOST_FILES[@]:-}"; do
            [[ -z "$rel_fmt" ]] && continue
            full_fmt="${REPO_ROOT}/${rel_fmt}"
            [[ ! -f "$full_fmt" ]] && continue
            eff_fmt="$DEFAULT_TARGET_EOL"
            if [[ $'\n'"$EOL_SKIP_LIST"$'\n' == *$'\n'"$rel_fmt"$'\n'* ]]; then eff_fmt="SKIP"
            elif [[ $'\n'"$EOL_LF_LIST"$'\n' == *$'\n'"$rel_fmt"$'\n'* ]]; then eff_fmt="LF"
            elif [[ $'\n'"$EOL_CRLF_LIST"$'\n' == *$'\n'"$rel_fmt"$'\n'* ]]; then eff_fmt="CRLF"
            fi
            if [[ "$eff_fmt" == "CRLF" ]] && awk '{ if (/\r[^\r]/ || !/\r$/) { found=1; exit } } END { exit !found }' "$full_fmt" 2>/dev/null; then
              awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$full_fmt" > "${full_fmt}.tmp" && mv "${full_fmt}.tmp" "$full_fmt"
            elif [[ "$eff_fmt" == "LF" ]] && grep -q $'\r' "$full_fmt" 2>/dev/null; then
              tr -d '\r' < "$full_fmt" > "${full_fmt}.tmp" && mv "${full_fmt}.tmp" "$full_fmt"
            fi
          done
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
    [[ ! "$f" =~ (\.(md|txt|rst)$|^docs/|^(LICENSE|NOTICE|AUTHORS|CODEOWNERS)(\..*)?$) ]] && all_docs=false
    [[ ! "$f" =~ (\.(md|txt|rst)$|^(docs/|scripts/|rules/|skills/|evals/|\.github/)|^(LICENSE|NOTICE|AUTHORS|CODEOWNERS)(\..*)?$|^\.(gitignore|gitattributes|editorconfig)$) ]] && all_meta=false
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
  if [[ -z "$first_leaf" ]]; then
    first_leaf="$first_base"
  fi
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
  echo "{\"status\":\"$STATUS\",\"mode\":\"$MODE_NAME\",\"target_eol\":\"$DEFAULT_TARGET_EOL\",\"next_step\":\"$NEXT_STEP\",\"host_files_count\":${#HOST_FILES[@]},\"reverted_whitespace_count\":${#REVERTED_WS_FILES[@]},\"normalized_count\":${#NORMALIZED_FILES[@]},\"whitespace_only_count\":${#WS_ONLY_FILES[@]},\"eol_count\":${#CRLF_FILES[@]},\"crlf_count\":${#CRLF_FILES[@]},\"ambiguous_count\":${#AMBIGUOUS_FILES[@]},\"submodule_count\":${#SUBMODULE_FILES[@]},\"format_status\":\"$FORMAT_STATUS\",\"guardrails_status\":\"$GUARDRAILS_STATUS\",\"arch_status\":\"$ARCH_STATUS\",\"suggested_commit_message\":\"$escaped_commit\"}"
else
  echo "============================================="
  echo "Commit Preparation ($([[ "$DIRECT_MODE" == "true" ]] && echo "DIRECT" || echo "PREPARE")) [Target EOL: $DEFAULT_TARGET_EOL]"
  echo "============================================="
  echo "Status: $STATUS | Next Step: $NEXT_STEP"
  if [[ ${#REVERTED_WS_FILES[@]} -gt 0 ]]; then echo "Reverted whitespace-only files: $(join_csv "${REVERTED_WS_FILES[@]}")"; fi
  if [[ ${#NORMALIZED_FILES[@]} -gt 0 ]]; then echo "Normalized EOL: $(join_csv "${NORMALIZED_FILES[@]}")"; fi
  if [[ ${#WS_ONLY_FILES[@]} -gt 0 ]]; then echo "Whitespace-only diffs awaiting revert (--revert-whitespace-only): $(join_csv "${WS_ONLY_FILES[@]}")"; fi
  if [[ ${#CRLF_FILES[@]} -gt 0 ]]; then echo "Unambiguous non-target EOL files (--fix-line-endings): $(join_csv "${CRLF_FILES[@]}")"; fi
  if [[ ${#AMBIGUOUS_FILES[@]} -gt 0 ]]; then echo "Ambiguous legacy EOL files (user decision required, --force-normalize): $(join_csv "${AMBIGUOUS_FILES[@]}")"; fi
  if [[ ${#SUBMODULE_FILES[@]} -gt 0 ]]; then echo "Submodule changes detected (must not be committed in host repo): $(join_csv "${SUBMODULE_FILES[@]}")"; fi
  if [[ "$FORMAT_STATUS" == "fail" ]]; then echo "Format check failed ($FORMAT_CMD): $(join_csv "${FORMAT_ERRORS[@]:-}")"; fi
  if [[ ${#GUARDRAIL_ERRORS[@]} -gt 0 ]]; then echo "Errors: $(join_csv "${GUARDRAIL_ERRORS[@]}")"; fi
  if [[ -n "$SUGGESTED_COMMIT" ]]; then echo "Suggested Commit: $SUGGESTED_COMMIT"; fi
fi

if [[ "$STATUS" == "fail" || "$STATUS" == "needs_decision" ]]; then
  exit 1
fi
