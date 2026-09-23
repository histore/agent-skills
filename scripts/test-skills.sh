#!/usr/bin/env bash
# ==============================================================================
# test-skills.sh - Automated validator and test suite for agent-skills
# Validates skill structure, YAML frontmatter, model-tiers.json, ghost roles,
# and asserts clean LF line endings.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
MODEL_TIERS_FILE="$REPO_ROOT/rules/model-tiers.json"

CHECKS_PASSED=0
ERRORS=()

assert_condition() {
    local condition="$1"
    local success_msg="$2"
    local failure_msg="$3"

    if [ "$condition" -eq 0 ]; then
        echo -e "  \033[32m[PASS]\033[0m $success_msg"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "  \033[31m[FAIL]\033[0m $failure_msg"
        ERRORS+=("$failure_msg")
    fi
}

echo -e "\033[36m=============================================\033[0m"
echo -e "\033[36mRunning Agent Skills Test & Validation Suite\033[0m"
echo -e "\033[36m=============================================\033[0m"

# 1. Validate rules/model-tiers.json
echo -e "\n\033[33m1. Validating rules/model-tiers.json...\033[0m"
if [ -f "$MODEL_TIERS_FILE" ]; then
    assert_condition 0 "model-tiers.json exists" "model-tiers.json not found"
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$MODEL_TIERS_FILE" 2>/dev/null; then
            assert_condition 0 "model-tiers.json is valid JSON" "model-tiers.json has invalid JSON syntax"
            ROLE_COUNT=$(jq '.execution_modes.multi_agent.tier_dispatch | [.[].roles[]] | length' "$MODEL_TIERS_FILE")
            if [ "$ROLE_COUNT" -eq 22 ]; then
                assert_condition 0 "All 22 roles are registered in model-tiers.json" "Expected 22 roles, found $ROLE_COUNT"
            else
                assert_condition 1 "All 22 roles are registered in model-tiers.json" "Expected 22 roles, found $ROLE_COUNT"
            fi
        else
            assert_condition 1 "model-tiers.json is valid JSON" "model-tiers.json failed jq parsing"
        fi
    fi
else
    assert_condition 1 "model-tiers.json exists" "model-tiers.json missing"
fi

# 2. Validate skills directory
echo -e "\n\033[33m2. Validating skills directory structure and frontmatter...\033[0m"
SKILL_COUNT=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ "$SKILL_COUNT" -eq 22 ]; then
    assert_condition 0 "Exactly 22 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 22 directories"
else
    assert_condition 1 "Exactly 22 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 22 skill directories, found $SKILL_COUNT"
fi

for skill_path in "$SKILLS_DIR"/*; do
    if [ -d "$skill_path" ]; then
        skill_name="$(basename "$skill_path")"
        skill_md="$skill_path/SKILL.md"

        if [ -f "$skill_md" ]; then
            assert_condition 0 "$skill_name/SKILL.md exists" "Missing SKILL.md in $skill_name"

            # Check frontmatter name
            fm_name=$(awk '/^name:/{print $2; exit}' "$skill_md" | tr -d '\r')
            if [ "$fm_name" = "$skill_name" ]; then
                assert_condition 0 "$skill_name frontmatter 'name: $skill_name' is valid" "$skill_name name mismatch: got '$fm_name'"
            else
                assert_condition 1 "$skill_name frontmatter 'name: $skill_name' is valid" "$skill_name name mismatch: got '$fm_name'"
            fi

            # Check description exists
            if grep -q '^description:' "$skill_md"; then
                assert_condition 0 "$skill_name has description in frontmatter" "Missing description in $skill_name"
            else
                assert_condition 1 "$skill_name has description in frontmatter" "Missing description in $skill_name"
            fi
        else
            assert_condition 1 "$skill_name/SKILL.md exists" "Missing SKILL.md in $skill_name"
        fi
    fi
done

# 3. Check for Ghost / Orphan Roles
echo -e "\n\033[33m3. Checking for ghost / orphan roles in markdown documentation...\033[0m"
GHOST_PATTERNS=("TerminalEngineSpecialist" "Tiebreaker")
for pattern in "${GHOST_PATTERNS[@]}"; do
    FOUND_FILES=()
    while IFS= read -r match_file; do
        if [ -n "$match_file" ]; then
            FOUND_FILES+=("$match_file")
        fi
    done < <(grep -rnw --exclude-dir=".git" "$REPO_ROOT" -e "$pattern" 2>/dev/null | cut -d: -f1 | sort -u || true)

    if [ ${#FOUND_FILES[@]} -eq 0 ]; then
        assert_condition 0 "Zero occurrences of ghost role '$pattern'" "Found ghost role '$pattern'"
    else
        assert_condition 1 "Zero occurrences of ghost role '$pattern'" "Found ghost role '$pattern' in: ${FOUND_FILES[*]}"
    fi
done

# 4. Check for CRLF line endings
echo -e "\n\033[33m4. Checking line endings (must be LF)...\033[0m"
CRLF_COUNT=$(find "$REPO_ROOT" -type f -not -path '*/.*' -exec file {} + 2>/dev/null | grep "CRLF" | wc -l || true)
if [ "$CRLF_COUNT" -eq 0 ]; then
    assert_condition 0 "All repository files use LF line endings" "CRLF line endings detected"
else
    assert_condition 1 "All repository files use LF line endings" "CRLF line endings detected in $CRLF_COUNT files"
fi

# Summary
echo -e "\n\033[36m=============================================\033[0m"
echo -e "\033[36mTest Suite Summary\033[0m"
echo -e "\033[36m=============================================\033[0m"
echo -e "\033[32mTotal checks passed: $CHECKS_PASSED\033[0m"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "\033[31mTotal failures: ${#ERRORS[@]}\033[0m"
    for err in "${ERRORS[@]}"; do
        echo -e "  \033[31m- $err\033[0m"
    done
    exit 1
else
    echo -e "\033[32mAll validation checks passed successfully! (0 errors)\033[0m"
    exit 0
fi
