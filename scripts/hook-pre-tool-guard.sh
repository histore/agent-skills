#!/usr/bin/env bash
# ==============================================================================
# hook-pre-tool-guard.sh - Deterministic zero-token PreToolUse guardrail hook
# for both Antigravity (AGY) and GitHub Copilot CLI.
#
# Enforces:
#   1. Destructive Git Guard (blocks git push --force/-f and git reset --hard)
#   2. Submodule Isolation Guard (blocks staging/committing _agents or .agents)
#   3. Safe Rust Guard (blocks unsafe constructs and #[unsafe(...)] in *.rs)
# ==============================================================================
set -euo pipefail

FORMAT="auto"
PAYLOAD_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format|-f)
      FORMAT="${2:-auto}"
      shift 2
      ;;
    --format=*)
      FORMAT="${1#*=}"
      shift
      ;;
    --payload-file|-p)
      PAYLOAD_FILE="${2:-}"
      shift 2
      ;;
    --payload-file=*)
      PAYLOAD_FILE="${1#*=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

RAW_PAYLOAD=""
if [[ -n "$PAYLOAD_FILE" && -f "$PAYLOAD_FILE" ]]; then
  RAW_PAYLOAD="$(cat "$PAYLOAD_FILE")"
elif [[ ! -t 0 ]]; then
  RAW_PAYLOAD="$(cat)"
fi

if [[ -z "$RAW_PAYLOAD" ]]; then
  if [[ "$FORMAT" == "copilot" ]]; then
    echo '{}'
  else
    echo '{"decision":"allow"}'
  fi
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$FORMAT" <<'PYEOF' "$RAW_PAYLOAD"
import json, re, sys

fmt = sys.argv[1]
raw = sys.argv[2]

def emit(resolved_fmt, deny, reason=""):
    if resolved_fmt == "copilot":
        if deny:
            print(json.dumps({"permissionDecision": "deny", "reason": reason}, separators=(",", ":")))
        else:
            print("{}")
    else:
        if deny:
            print(json.dumps({"decision": "deny", "reason": reason}, separators=(",", ":")))
        else:
            print('{"decision":"allow"}')

try:
    payload = json.loads(raw)
except Exception:
    emit("agy" if fmt == "auto" else fmt, False)
    sys.exit(0)

if fmt == "auto":
    if isinstance(payload, dict) and ("toolCall" in payload or "hookEventName" in payload):
        resolved_fmt = "agy"
    elif isinstance(payload, dict) and ("toolName" in payload or "toolArgs" in payload):
        resolved_fmt = "copilot"
    else:
        resolved_fmt = "agy"
else:
    resolved_fmt = fmt

args = {}
if isinstance(payload, dict):
    tc = payload.get("toolCall")
    if isinstance(tc, dict) and isinstance(tc.get("args"), dict):
        args = tc["args"]
    elif isinstance(payload.get("toolArgs"), dict):
        args = payload["toolArgs"]

cmd = str(args.get("CommandLine") or args.get("command") or "")
path = str(args.get("Path") or args.get("path") or args.get("file_path") or "")
written_parts = [
    str(args[k]) for k in ("Replacement", "Content", "new_str", "file_text", "content")
    if args.get(k)
]
written = "\n".join(written_parts)

deny_reason = ""
if cmd:
    if re.search(r'(?i)\bgit\b[^\r\n;|&]*\bpush\b[^\r\n;|&]*((?<![-\w])--force(?![-\w])|(?<![-\w])-f(?![-\w]))', cmd) and not re.search(r'(?i)--force-with-lease', cmd):
        deny_reason = "Destructive 'git push --force' is blocked by agent-skills PreToolUse guardrail. Use '--force-with-lease' only after explicit user confirmation."
    elif re.search(r'(?i)\bgit\b[^\r\n;|&]*\breset\b[^\r\n;|&]*--hard\b', cmd):
        deny_reason = "Destructive 'git reset --hard' is blocked by agent-skills PreToolUse guardrail. Create a safety snapshot via diagnose-git-state and confirm with the user first."
    elif re.search(r'(?i)\bgit\b[^\r\n;|&]*\b(add|stage|commit)\b[^\r\n;|&]*(^|[\s"\'/\\])(_agents|\.agents)($|[\s"\'/\\])', cmd):
        deny_reason = "Submodule Isolation Guardrail: staging or committing '_agents' or '.agents' submodule paths in host workspace commits is prohibited."

if not deny_reason and re.search(r'(?i)\.rs$', path) and written:
    if re.search(r'(?m)(^|[^\w])unsafe\s*(\{|fn\b|trait\b|impl\b|extern\b)|#\[unsafe\(', written):
        deny_reason = "Safe Rust Invariant: 'unsafe' constructs and Rust 2024 '#[unsafe(...)]' attributes are strictly prohibited in Rust codebases."

emit(resolved_fmt, bool(deny_reason), deny_reason)
PYEOF
  exit 0
fi

# Minimal shell fallback when python3 is unavailable
RESOLVED_FMT="$FORMAT"
if [[ "$RESOLVED_FMT" == "auto" ]]; then
  if echo "$RAW_PAYLOAD" | grep -q '"toolName"'; then
    RESOLVED_FMT="copilot"
  else
    RESOLVED_FMT="agy"
  fi
fi

DENY_REASON=""
if echo "$RAW_PAYLOAD" | grep -Eqi 'git[[:space:]].*push.*(--force|-f)' && ! echo "$RAW_PAYLOAD" | grep -qi -- '--force-with-lease'; then
  DENY_REASON="Destructive 'git push --force' is blocked by agent-skills PreToolUse guardrail."
elif echo "$RAW_PAYLOAD" | grep -Eqi 'git[[:space:]].*reset.*--hard'; then
  DENY_REASON="Destructive 'git reset --hard' is blocked by agent-skills PreToolUse guardrail."
elif echo "$RAW_PAYLOAD" | grep -Eqi 'git[[:space:]].*(add|stage|commit).*(_agents|\.agents)'; then
  DENY_REASON="Submodule Isolation Guardrail: staging or committing '_agents' or '.agents' is prohibited."
fi

if [[ -n "$DENY_REASON" ]]; then
  if [[ "$RESOLVED_FMT" == "copilot" ]]; then
    echo "{\"permissionDecision\":\"deny\",\"reason\":\"${DENY_REASON}\"}"
  else
    echo "{\"decision\":\"deny\",\"reason\":\"${DENY_REASON}\"}"
  fi
else
  if [[ "$RESOLVED_FMT" == "copilot" ]]; then
    echo '{}'
  else
    echo '{"decision":"allow"}'
  fi
fi
exit 0
