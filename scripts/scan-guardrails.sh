#!/usr/bin/env bash
# ==============================================================================
# Deterministic code guardrails scanner (Safe-Rust, Secrets, CRLF, Submodule leakage).
# ==============================================================================
set -euo pipefail

SCAN_PATH=""
STAGED_ONLY=false
WORKING_TREE=false
FIX=false
SKIP_LINE_ENDINGS=false
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
    --skip-line-endings)
      SKIP_LINE_ENDINGS=true
      shift
      ;;
    --json|-j)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      if [[ -z "$SCAN_PATH" ]]; then
        SCAN_PATH="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$SCAN_PATH" ]]; then
  SCAN_PATH="$(pwd)"
fi

VIOLATIONS=()

OS_UNAME="$(uname -s 2>/dev/null || echo "")"
case "$OS_UNAME" in
  MINGW*|MSYS*|CYGWIN*) DEFAULT_TARGET_EOL="CRLF" ;;
  *) DEFAULT_TARGET_EOL="LF" ;;
esac

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
    -not -path '*/_agents/*' \
    -not -path '*/\.agents/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/target/*' \
    -not -path '*/bin/*' \
    -not -path '*/obj/*' \
    -not -path '*/publish/*' \
    -not -path '*/artifacts/*')
fi

# 1b. Resolve project-level EOL overrides (.gitattributes / .editorconfig) in a single batch
EOL_SKIP_LIST=""
EOL_LF_LIST=""
EOL_CRLF_LIST=""

if [[ "$SKIP_LINE_ENDINGS" != "true" && ${#FILES[@]} -gt 0 ]]; then
  REL_PATHS=()
  for file in "${FILES[@]}"; do
    REL_PATHS+=("${file#"${SCAN_PATH}/"}")
  done

  GIT_TOP=$(git -C "$SCAN_PATH" rev-parse --show-toplevel 2>/dev/null || true)
  EC_PATH="${SCAN_PATH}/.editorconfig"
  if [[ ! -f "$EC_PATH" && -n "$GIT_TOP" && -f "${GIT_TOP}/.editorconfig" ]]; then
    EC_PATH="${GIT_TOP}/.editorconfig"
  fi
  HAS_GITATTR=false
  if [[ -f "${SCAN_PATH}/.gitattributes" ]] || [[ -n "$GIT_TOP" && -f "${GIT_TOP}/.gitattributes" ]]; then
    HAS_GITATTR=true
  fi

  if [[ "$HAS_GITATTR" == "true" && -n "$GIT_TOP" ]]; then
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
    done < <(printf '%s\0' "${REL_PATHS[@]}" | git -C "$SCAN_PATH" check-attr --stdin -z text eol 2>/dev/null || true)
    if [[ -n "$CUR_PATH" ]]; then
      if [[ "$CUR_SKIP" == "true" ]]; then EOL_SKIP_LIST+="${CUR_PATH}"$'\n'
      elif [[ "$CUR_EOL" == "LF" ]]; then EOL_LF_LIST+="${CUR_PATH}"$'\n'
      elif [[ "$CUR_EOL" == "CRLF" ]]; then EOL_CRLF_LIST+="${CUR_PATH}"$'\n'
      fi
    fi
  fi

  if [[ (-f "$EC_PATH" || ("$HAS_GITATTR" == "true" && -z "$GIT_TOP")) ]] && command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r ov_rel ov_eol; do
      [[ -z "$ov_rel" ]] && continue
      if [[ $'\n'"$EOL_SKIP_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* || $'\n'"$EOL_LF_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* || $'\n'"$EOL_CRLF_LIST"$'\n' == *$'\n'"$ov_rel"$'\n'* ]]; then
        continue
      fi
      case "$ov_eol" in
        SKIP) EOL_SKIP_LIST+="${ov_rel}"$'\n' ;;
        LF)   EOL_LF_LIST+="${ov_rel}"$'\n' ;;
        CRLF) EOL_CRLF_LIST+="${ov_rel}"$'\n' ;;
      esac
    done < <(printf '%s\n' "${REL_PATHS[@]}" | python3 - "$EC_PATH" "${SCAN_PATH}/.gitattributes" "$HAS_GITATTR" "$GIT_TOP" << 'EOF' 2>/dev/null || true
import os, re, sys

ec_path, ga_path, has_ga, git_top = sys.argv[1], sys.argv[2], sys.argv[3] == "true", sys.argv[4]

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

ga_rules = []
if has_ga and not git_top and os.path.isfile(ga_path):
    with open(ga_path, 'r', encoding='utf-8', errors='ignore') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'): continue
            parts = line.split()
            if len(parts) < 2: continue
            rx = glob_to_regex(parts[0])
            attrs = parts[1:]
            if '-text' in attrs or 'binary' in attrs: ga_rules.append((rx, 'SKIP'))
            elif 'eol=lf' in attrs: ga_rules.append((rx, 'LF'))
            elif 'eol=crlf' in attrs: ga_rules.append((rx, 'CRLF'))

ec_rules = []
if os.path.isfile(ec_path):
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
    for rx, val in ga_rules:
        if rx.search(rel): res = val
    if not res:
        for rx, val in ec_rules:
            if rx.search(rel): res = val
    if res:
        print(f"{rel}\t{res}")
EOF
    )
  fi
fi

# 2. Scan files
for file in "${FILES[@]}"; do
  rel_path="${file#"${SCAN_PATH}/"}"

  # Submodule leakage check
  if [[ "$STAGED_ONLY" == "true" && ("$rel_path" =~ ^\.agents/ || "$rel_path" =~ ^_agents/) ]]; then
    VIOLATIONS+=("[SubmoduleIsolation] ${rel_path}: Staged change originates inside submodule path")
  fi

  # Text file check (use `file` when available, fall back to extension/name allowlist in minimal containers)
  IS_TEXT=false
  if command -v file >/dev/null 2>&1; then
    if file -b --mime "$file" 2>/dev/null | grep -q 'text'; then
      IS_TEXT=true
    fi
  else
    file_name="$(basename "$file")"
    if [[ "$file_name" =~ \.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|json|md|yml|yaml|toml|ps1|sh|axaml|props|targets|xml|txt|csproj|sln|editorconfig|gitattributes|gitignore|manifest)$ ]] || \
       [[ "$file_name" =~ ^(LICENSE|NOTICE|AUTHORS|CODEOWNERS)$ ]]; then
      IS_TEXT=true
    fi
  fi

  # Line-ending check: OS-native unless overridden by project config (.gitattributes/.editorconfig); deferrable via --skip-line-endings
  if [[ "$IS_TEXT" == "true" ]]; then
    EFF_EOL="$DEFAULT_TARGET_EOL"
    if [[ $'\n'"$EOL_SKIP_LIST"$'\n' == *$'\n'"$rel_path"$'\n'* ]]; then
      EFF_EOL="SKIP"
    elif [[ $'\n'"$EOL_LF_LIST"$'\n' == *$'\n'"$rel_path"$'\n'* ]]; then
      EFF_EOL="LF"
    elif [[ $'\n'"$EOL_CRLF_LIST"$'\n' == *$'\n'"$rel_path"$'\n'* ]]; then
      EFF_EOL="CRLF"
    fi

    if [[ "$SKIP_LINE_ENDINGS" != "true" && "$EFF_EOL" != "SKIP" ]]; then
      HAS_WRONG_EOL=false
      if [[ "$EFF_EOL" == "CRLF" ]]; then
        if awk '{ if (/\r[^\r]/ || !/\r$/) { found=1; exit } } END { exit !found }' "$file" 2>/dev/null; then
          HAS_WRONG_EOL=true
        fi
      else
        if grep -q $'\r' "$file" 2>/dev/null; then
          HAS_WRONG_EOL=true
        fi
      fi

      if [[ "$HAS_WRONG_EOL" == "true" ]]; then
        if [[ "$FIX" == "true" ]]; then
          if [[ "$EFF_EOL" == "CRLF" ]]; then
            awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
          else
            tr -d '\r' < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
          fi
          if [[ "$STAGED_ONLY" == "true" ]]; then
            git -C "$SCAN_PATH" add "$file" 2>/dev/null || true
          fi
        else
          if [[ "$EFF_EOL" == "CRLF" ]]; then
            VIOLATIONS+=("[LineEndings] ${rel_path}: LF line endings detected (expected CRLF)")
          else
            VIOLATIONS+=("[LineEndings] ${rel_path}: CRLF line endings detected (expected LF)")
          fi
        fi
      fi
    fi

    # Safe-Rust check (blocks, pub/async unsafe fn, unsafe impl/trait/extern, Rust 2024 #[unsafe(...)])
    if [[ "$file" == *.rs ]]; then
      if sed -E 's#//.*$##; s#"((\\.)|[^"\\])*"#""#g' "$file" | grep -nE '((^|[^[:alnum:]_])unsafe[[:space:]]*(\{|fn([^[:alnum:]_]|$)|impl([^[:alnum:]_]|$)|trait([^[:alnum:]_]|$)|extern([^[:alnum:]_]|$))|#\[[[:space:]]*unsafe[[:space:]]*\()' >/dev/null 2>&1; then
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
    VIOLATIONS_JSON=""
    for v in "${VIOLATIONS[@]}"; do
      esc_v="${v//\\/\\\\}"
      esc_v="${esc_v//\"/\\\"}"
      if [[ -n "$VIOLATIONS_JSON" ]]; then VIOLATIONS_JSON+=","; fi
      VIOLATIONS_JSON+="\"$esc_v\""
    done
    echo "{\"status\":\"fail\",\"scanned_files_count\":${#FILES[@]},\"violations_count\":$TOTAL_VIOLATIONS,\"violations\":[$VIOLATIONS_JSON]}"
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
