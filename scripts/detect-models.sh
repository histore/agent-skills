#!/usr/bin/env bash
# detect-models.sh - Probes the AI environment, available models, and optimal execution mode.

set -e

output_path=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output) output_path="$2"; shift ;;
        *) ;;
    esac
    shift
done

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
    fi

    json_output=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "platform": "$platform",
  "execution_mode": "$execution_mode",
  "supports_subagents": $supports_subagents,
  "detected_models": $models_json,
  "recommended_tiers": {
    "tier_1": { "model_class": "pro", "reasoning_effort": "high" },
    "tier_2": { "model_class": "flash", "reasoning_effort": "high" },
    "tier_3": { "model_class": "flash", "reasoning_effort": "medium" },
    "tier_4": { "model_class": "flash_lite", "fallback": "flash", "reasoning_effort": "low" }
  }
}
EOF
)

elif command -v gh &>/dev/null; then
    json_output=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "platform": "copilot",
  "execution_mode": "sequential_persona",
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
  "platform": "generic",
  "execution_mode": "sequential_persona",
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

if [[ -n "$output_path" ]]; then
    mkdir -p "$(dirname "$output_path")"
    echo "$json_output" > "$output_path"
fi

echo "$json_output"
