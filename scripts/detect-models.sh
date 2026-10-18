#!/usr/bin/env bash
# ==============================================================================
# detect-models.sh - Probes the AI environment, available models, and optimal
# execution mode. Persists detection results to a cross-session cache with a
# 24-hour TTL (configurable) to eliminate redundant probing.
# ==============================================================================

set -e

output_path=""
cache_path=""
max_age_hours=24
force=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output) output_path="$2"; shift 2 ;;
        -c|--cache-path) cache_path="$2"; shift 2 ;;
        -m|--max-age-hours) max_age_hours="$2"; shift 2 ;;
        -f|--force) force=true; shift ;;
        *) shift ;;
    esac
done

# 1. Determine persistent cache location across sessions & skills
if [[ -z "$cache_path" ]]; then
    base_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    cache_path="$base_cache_dir/agent-skills/model-cache.json"
fi

# 2. Check existing cache unless --force was specified
if [[ "$force" = false && -f "$cache_path" ]]; then
    # Calculate file age in seconds
    now_epoch=$(date +%s)
    if stat -c %Y "$cache_path" &>/dev/null; then
        file_epoch=$(stat -c %Y "$cache_path")
    elif stat -f %m "$cache_path" &>/dev/null; then
        file_epoch=$(stat -f %m "$cache_path")
    else
        file_epoch=0
    fi

    age_seconds=$((now_epoch - file_epoch))
    max_age_seconds=$((max_age_hours * 3600))

    if [[ "$age_seconds" -ge 0 && "$age_seconds" -lt "$max_age_seconds" ]]; then
        # Cache is valid and fresh
        if command -v jq &>/dev/null; then
            cached_output=$(jq --arg cache_file "$cache_path" '. + {cached: true, cache_file: $cache_file}' "$cache_path" 2>/dev/null || sed 's/"cached": false/"cached": true/' "$cache_path")
        else
            cached_output=$(sed 's/"cached": false/"cached": true/' "$cache_path")
        fi

        if [[ -n "$output_path" ]]; then
            mkdir -p "$(dirname "$output_path")"
            echo "$cached_output" > "$output_path"
        fi
        echo "$cached_output"
        exit 0
    fi
fi

# 3. Perform fresh environment probe
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if command -v agy &>/dev/null; then
    platform="antigravity"
    execution_mode="multi_agent"
    supports_subagents=true

    # Probe available models via agy models (with timeout guard if available)
    models_json="[]"
    if command -v timeout >/dev/null 2>&1; then
        raw_models=$(timeout 3 agy models 2>/dev/null || true)
    else
        raw_models=$(agy models 2>/dev/null || true)
    fi
    if [[ -n "$raw_models" ]]; then
        models_array=()
        while IFS= read -r line; do
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]] && [[ "${BASH_REMATCH[1]}" != "Fetching" ]]; then
                m_id="${BASH_REMATCH[1]}"
                m_name="${BASH_REMATCH[2]}"
                models_array+=("{\"id\":\"$m_id\",\"name\":\"$m_name\"}")
            fi
        done <<< "$raw_models"

        if [ ${#models_array[@]} -gt 0 ]; then
            models_json="["$(IFS=,; echo "${models_array[*]}")"]"
        fi
        opus_high=$(echo "$raw_models" | grep -E 'opus.*high' | head -n1 | awk '{print $1}')
        sonnet_high=$(echo "$raw_models" | grep -E 'sonnet.*high' | head -n1 | awk '{print $1}')
        flash_high=$(echo "$raw_models" | grep -E 'flash.*high' | head -n1 | awk '{print $1}')
        flash_med=$(echo "$raw_models" | grep -E 'flash.*medium' | head -n1 | awk '{print $1}')
        flash_low=$(echo "$raw_models" | grep -E 'flash.*low' | head -n1 | awk '{print $1}')

        t1="${opus_high:-${flash_high:-inherit}}"
        t2="${sonnet_high:-${flash_high:-inherit}}"
        t3="${flash_med:-${flash_high:-inherit}}"
        t4="${flash_low:-${flash_med:-flash}}"
    fi

    json_output=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "cached": false,
  "cache_file": "$cache_path",
  "platform": "$platform",
  "execution_mode": "$execution_mode",
  "cost_efficiency": true,
  "cost_guardrail": {
    "enabled": true,
    "max_routine_cost_class": "versatile",
    "flagship_threshold_input_per_m": 4.00,
    "flagship_threshold_output_per_m": 20.00,
    "throttle_routine_to_cost_efficient": true
  },
  "supports_subagents": $supports_subagents,
  "detected_models": $models_json,
  "recommended_tiers": {
    "tier_1": { "model_class": "inherit", "fallback": "flash", "exception_model_class": "pro", "reasoning_effort": "high_extended" },
    "tier_2": { "model_class": "inherit", "fallback": "flash", "exception_model_class": "pro", "reasoning_effort": "high" },
    "tier_3": { "model_class": "inherit", "fallback": "flash", "reasoning_effort": "medium" },
    "tier_4": { "model_class": "flash", "fallback": "flash_lite", "reasoning_effort": "low" }
  },
  "active_model_mapping": {
    "tier_1_deep_reasoning": "$t1",
    "tier_2_analytical": "$t2",
    "tier_3_balanced": "$t3",
    "tier_4_deterministic": "$t4"
  }
}
EOF
)

elif command -v gh &>/dev/null; then
    json_output=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "cached": false,
  "cache_file": "$cache_path",
  "platform": "copilot",
  "execution_mode": "sequential_persona",
  "cost_efficiency": true,
  "cost_guardrail": {
    "enabled": true,
    "max_routine_cost_class": "versatile",
    "flagship_threshold_input_per_m": 4.00,
    "flagship_threshold_output_per_m": 20.00,
    "throttle_routine_to_cost_efficient": true
  },
  "supports_subagents": false,
  "detected_models": [],
  "recommended_tiers": {
    "tier_1": { "reasoning_effort": "high", "strategy": "maximum_thinking" },
    "tier_2": { "reasoning_effort": "high", "strategy": "analytical" },
    "tier_3": { "reasoning_effort": "medium", "strategy": "balanced" },
    "tier_4": { "reasoning_effort": "low", "strategy": "deterministic" }
  }
}
EOF
)

else
    json_output=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "cached": false,
  "cache_file": "$cache_path",
  "platform": "generic",
  "execution_mode": "sequential_persona",
  "cost_efficiency": true,
  "cost_guardrail": {
    "enabled": true,
    "max_routine_cost_class": "versatile",
    "flagship_threshold_input_per_m": 4.00,
    "flagship_threshold_output_per_m": 20.00,
    "throttle_routine_to_cost_efficient": true
  },
  "supports_subagents": false,
  "detected_models": [],
  "recommended_tiers": {
    "tier_1": { "reasoning_effort": "high", "strategy": "deep_reasoning" },
    "tier_2": { "reasoning_effort": "high", "strategy": "focused_analysis" },
    "tier_3": { "reasoning_effort": "medium", "strategy": "implementation" },
    "tier_4": { "reasoning_effort": "low", "strategy": "fast_execution" }
  }
}
EOF
)
fi

# 4. Save to persistent cache file
mkdir -p "$(dirname "$cache_path")" 2>/dev/null || true
echo "$json_output" > "$cache_path" 2>/dev/null || true

# 5. Save to explicit output_path if requested
if [[ -n "$output_path" ]]; then
    mkdir -p "$(dirname "$output_path")"
    echo "$json_output" > "$output_path"
fi

echo "$json_output"
