#!/usr/bin/env bash
# ==============================================================================
# Displays and summarizes lifecycle telemetry metrics for ask-skills.
# ==============================================================================
set -euo pipefail

LIMIT=25
SESSION_ID=""
JSON_OUTPUT=false
TELEMETRY_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit|-l)
      LIMIT="$2"
      shift 2
      ;;
    --session-id|-s)
      SESSION_ID="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --telemetry-path)
      TELEMETRY_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TELEMETRY_PATH" ]]; then
  BASE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/agent-skills"
  TELEMETRY_PATH="${BASE_DIR}/telemetry.jsonl"
fi

if [[ ! -f "$TELEMETRY_PATH" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo '{"total_records": 0, "records": []}'
  else
    echo "No telemetry records found at: $TELEMETRY_PATH"
  fi
  exit 0
fi

if command -v python3 &>/dev/null; then
  python3 -c "
import json

telemetry_path = '$TELEMETRY_PATH'
session_id = '$SESSION_ID'
limit = int('$LIMIT')
json_output = '$JSON_OUTPUT' == 'true'

records = []
with open(telemetry_path, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
            if not session_id or r.get('session_id') == session_id:
                records.append(r)
        except Exception:
            pass

recent = records[-limit:] if limit > 0 else records

if json_output:
    print(json.dumps({'total_records': len(records), 'displayed_records': len(recent), 'records': recent}, indent=2))
else:
    print('=============================================')
    print('ask-skills Lifecycle Telemetry Dashboard')
    print(f'Log: {telemetry_path}')
    print(f'Total Records: {len(records)} | Showing: {len(recent)}')
    print('=============================================')
    for r in recent:
        ts = r.get('timestamp', '')
        phase = r.get('phase', '')
        ev = r.get('event', '')
        st = r.get('status', '')
        dur = r.get('duration_ms', 0)
        prof = r.get('profile', '-')
        print(f'{ts} | {phase:<22} | {ev:<14} | {st:<10} | {dur:>6}ms | {prof}')
"
else
  tail -n "$LIMIT" "$TELEMETRY_PATH"
fi
