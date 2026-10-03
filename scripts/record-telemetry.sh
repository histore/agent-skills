#!/usr/bin/env bash
# ==============================================================================
# Records structured lifecycle telemetry and phase transitions for ask-skills.
# ==============================================================================
set -euo pipefail

PHASE=""
EVENT=""
STATUS="success"
DURATION_MS=0
PROFILE=""
SESSION_ID=""
DETAILS=""
TELEMETRY_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase|-p)
      PHASE="$2"
      shift 2
      ;;
    --event|-e)
      EVENT="$2"
      shift 2
      ;;
    --status|-s)
      STATUS="$2"
      shift 2
      ;;
    --duration-ms|-d)
      DURATION_MS="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --session-id)
      SESSION_ID="$2"
      shift 2
      ;;
    --details)
      DETAILS="$2"
      shift 2
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

if [[ -z "$PHASE" || -z "$EVENT" ]]; then
  echo "Usage: record-telemetry.sh --phase <phase> --event <event> [options]" >&2
  exit 1
fi

if [[ -z "$TELEMETRY_PATH" ]]; then
  BASE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/agent-skills"
  mkdir -p "$BASE_DIR"
  TELEMETRY_PATH="${BASE_DIR}/telemetry.jsonl"
fi

# Rotate if > 10MB
if [[ -f "$TELEMETRY_PATH" ]]; then
  SIZE=$(wc -c < "$TELEMETRY_PATH" 2>/dev/null || stat -c%s "$TELEMETRY_PATH" 2>/dev/null || echo 0)
  if (( SIZE > 10485760 )); then
    mv -f "$TELEMETRY_PATH" "${TELEMETRY_PATH}.bak" 2>/dev/null || true
  fi
fi

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="${CONVERSATION_ID:-session-$(date +%Y%m%d)}"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write JSONL
if command -v python3 &>/dev/null; then
  python3 -c "
import json

record = {
    'timestamp': '$TIMESTAMP',
    'session_id': '$SESSION_ID',
    'phase': '$PHASE',
    'event': '$EVENT',
    'status': '$STATUS',
    'duration_ms': int('$DURATION_MS') if '$DURATION_MS'.isdigit() else 0
}
if '$PROFILE':
    record['profile'] = '$PROFILE'
if '$DETAILS':
    try:
        record['details'] = json.loads('$DETAILS')
    except Exception:
        record['details'] = '$DETAILS'

with open('$TELEMETRY_PATH', 'a', encoding='utf-8') as f:
    f.write(json.dumps(record) + '\n')
" 2>/dev/null || true
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"session_id\":\"$SESSION_ID\",\"phase\":\"$PHASE\",\"event\":\"$EVENT\",\"status\":\"$STATUS\",\"duration_ms\":$DURATION_MS}" >> "$TELEMETRY_PATH"
fi
