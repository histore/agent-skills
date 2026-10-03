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
            if [ "$ROLE_COUNT" -eq 23 ]; then
                assert_condition 0 "All 23 roles are registered in model-tiers.json" "Expected 23 roles, found $ROLE_COUNT"
            else
                assert_condition 1 "All 23 roles are registered in model-tiers.json" "Expected 23 roles, found $ROLE_COUNT"
            fi

            # Validate Cost-Efficiency Policy
            HAS_COST_POLICY=$(jq '.cost_efficiency_policy.default_to_cost_efficient // false' "$MODEL_TIERS_FILE")
            if [ "$HAS_COST_POLICY" = "true" ]; then
                assert_condition 0 "Cost-efficiency policy is defined and enforces cost-efficient defaults" "cost_efficiency_policy missing or not true"
            else
                assert_condition 1 "Cost-efficiency policy is defined and enforces cost-efficient defaults" "cost_efficiency_policy missing or not true"
            fi
            HAS_PRO_DEFAULT=$(jq '.execution_modes.multi_agent.tier_dispatch | [.[].model_class] | any(. == "pro")' "$MODEL_TIERS_FILE")
            if [ "$HAS_PRO_DEFAULT" = "false" ]; then
                assert_condition 0 "No tier dispatches to high-cost 'pro' model class by default" "Found tier with 'pro' default model class"
            else
                assert_condition 1 "No tier dispatches to high-cost 'pro' model class by default" "Found tier with 'pro' default model class"
            fi

            HAS_REASONING_RULE=$(jq '.cost_efficiency_policy.high_reasoning_requires_cost_advantage // false' "$MODEL_TIERS_FILE")
            if [ "$HAS_REASONING_RULE" = "true" ]; then
                assert_condition 0 "Cost-efficiency policy restricts high reasoning levels to when cost-efficient" "high_reasoning_requires_cost_advantage missing or not true"
            else
                assert_condition 1 "Cost-efficiency policy restricts high reasoning levels to when cost-efficient" "high_reasoning_requires_cost_advantage missing or not true"
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
if [ "$SKILL_COUNT" -eq 23 ]; then
    assert_condition 0 "Exactly 23 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 23 directories"
else
    assert_condition 1 "Exactly 23 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 23 skill directories, found $SKILL_COUNT"
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
    done < <(grep -rnw --exclude-dir=".git" --include="*.md" "$REPO_ROOT" -e "$pattern" 2>/dev/null | cut -d: -f1 | sort -u || true)

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

# 5. Validate model detection persistent caching functionality
echo -e "\n\033[33m5. Testing detect-models.sh 24h caching...\033[0m"
TEMP_CACHE=$(mktemp 2>/dev/null || echo "/tmp/model-cache-test.json")
# 5.1 Fresh probe test
PROBE1_OUT=$(bash "$REPO_ROOT/scripts/detect-models.sh" --cache-path "$TEMP_CACHE" --force 2>/dev/null || true)
if echo "$PROBE1_OUT" | grep -q '"cached": false'; then
    assert_condition 0 "Fresh probe returns 'cached: false'" "Expected 'cached: false' on fresh probe"
else
    assert_condition 1 "Fresh probe returns 'cached: false'" "Expected 'cached: false' on fresh probe"
fi

if [ -f "$TEMP_CACHE" ]; then
    assert_condition 0 "Cache file was persisted to disk" "Cache file was not created"
else
    assert_condition 1 "Cache file was persisted to disk" "Cache file was not created"
fi

# 5.2 Cached retrieval test
PROBE2_OUT=$(bash "$REPO_ROOT/scripts/detect-models.sh" --cache-path "$TEMP_CACHE" 2>/dev/null || true)
if echo "$PROBE2_OUT" | grep -q '"cached": true'; then
    assert_condition 0 "Second call returns 'cached: true'" "Expected 'cached: true' on second call"
else
    assert_condition 1 "Second call returns 'cached: true'" "Expected 'cached: true' on second call"
fi

# 5.3 Force refresh test
PROBE3_OUT=$(bash "$REPO_ROOT/scripts/detect-models.sh" --cache-path "$TEMP_CACHE" --force 2>/dev/null || true)
if echo "$PROBE3_OUT" | grep -q '"cached": false'; then
    assert_condition 0 "Call with --force bypasses cache and returns 'cached: false'" "Expected 'cached: false' with --force"
else
    assert_condition 1 "Call with --force bypasses cache and returns 'cached: false'" "Expected 'cached: false' with --force"
fi
rm -f "$TEMP_CACHE" 2>/dev/null || true

# 6. Validate relative markdown links across all .md files
echo -e "\n\033[33m6. Validating markdown relative links...\033[0m"
BROKEN_LINKS=()
while IFS= read -r md_file; do
    md_dir="$(dirname "$md_file")"
    # Extract links like [text](link)
    # Using python/perl or pure bash/awk
    if command -v python3 >/dev/null 2>&1; then
        while IFS= read -r rel_link; do
            if [ -n "$rel_link" ]; then
                target_path="$md_dir/$rel_link"
                if [ ! -e "$target_path" ]; then
                    BROKEN_LINKS+=("${md_file#$REPO_ROOT/} -> $rel_link")
                fi
            fi
        done < <(python3 -c "
import re, sys
content = open('$md_file', 'r', encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', content):
    link = m.group(2).split('#')[0].strip()
    if link and not link.startswith(('http://', 'https://', 'mailto:', 'file:', '#')):
        print(link)
" 2>/dev/null || true)
    fi
done < <(find "$REPO_ROOT" -type f -name "*.md" -not -path '*/.*' 2>/dev/null)

if [ ${#BROKEN_LINKS[@]} -eq 0 ]; then
    assert_condition 0 "All relative markdown links resolve successfully" "Broken markdown links found"
else
    assert_condition 1 "All relative markdown links resolve successfully" "Broken markdown links found: ${BROKEN_LINKS[*]}"
fi

# 7. Validate PowerShell command hygiene in markdown files (must include -NoProfile)
echo -e "\n\033[33m7. Checking PowerShell command hygiene (must use -NoProfile)...\033[0m"
MISSING_NOPROFILE=()
while IFS= read -r md_file; do
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if echo "$line" | grep -Eq '^\s*powershell(\.exe)?\s+|`powershell(\.exe)?\s+'; then
            if ! echo "$line" | grep -q -- '-NoProfile'; then
                MISSING_NOPROFILE+=("${md_file#$REPO_ROOT/}:$line_num")
            fi
        fi
    done < "$md_file"
done < <(find "$REPO_ROOT" -type f -name "*.md" -not -path '*/.*' 2>/dev/null)

if [ ${#MISSING_NOPROFILE[@]} -eq 0 ]; then
    assert_condition 0 "All powershell command invocations include -NoProfile" "powershell commands missing -NoProfile"
else
    assert_condition 1 "All powershell command invocations include -NoProfile" "powershell commands missing -NoProfile in: ${MISSING_NOPROFILE[*]}"
fi

# 8. Validate get-arch-diff submodule exclusions (_agents and .agents)
echo -e "\n\033[33m8. Validating get-arch-diff submodule exclusions...\033[0m"
ARCH_DIFF_PS1="$REPO_ROOT/skills/ask-architecture-sync/scripts/get-arch-diff.ps1"
ARCH_DIFF_SH="$REPO_ROOT/skills/ask-architecture-sync/scripts/get-arch-diff.sh"

if [ -f "$ARCH_DIFF_PS1" ] && grep -q '_agents' "$ARCH_DIFF_PS1" && grep -q '\.agents' "$ARCH_DIFF_PS1"; then
    assert_condition 0 "get-arch-diff.ps1 excludes _agents and .agents submodules" "get-arch-diff.ps1 missing exclusions"
else
    assert_condition 1 "get-arch-diff.ps1 excludes _agents and .agents submodules" "get-arch-diff.ps1 missing exclusions"
fi

if [ -f "$ARCH_DIFF_SH" ] && grep -F -q '(^|/)_agents(/|$)' "$ARCH_DIFF_SH" && grep -F -q '(^|/)\.agents(/|$)' "$ARCH_DIFF_SH"; then
    assert_condition 0 "get-arch-diff.sh regex correctly matches and excludes _agents and .agents submodules" "get-arch-diff.sh missing or flawed exclusions"
else
    assert_condition 1 "get-arch-diff.sh regex correctly matches and excludes _agents and .agents submodules" "get-arch-diff.sh missing or flawed exclusions"
fi

# 9. Validate model tier references in all 23 skills
echo -e "\n\033[33m9. Validate model tier references in all 23 skills...\033[0m"
MISSING_TIER_REF=()
for skill_dir in "$REPO_ROOT"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"
    if [ -f "$skill_file" ]; then
        if ! grep -q 'rules/model-tiers\.json' "$skill_file"; then
            MISSING_TIER_REF+=("$skill_name")
        fi
    fi
done

if [ ${#MISSING_TIER_REF[@]} -eq 0 ]; then
    assert_condition 0 "All 23 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json reference"
else
    assert_condition 1 "All 23 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json: ${MISSING_TIER_REF[*]}"
fi

# 10. Validate Tooling & Path Compatibility and host project orientation in all 23 skills
echo -e "\n\033[33m10. Validating Tooling & Path Compatibility and host project orientation...\033[0m"
MISSING_PATH_COMPAT=()
for skill_dir in "$REPO_ROOT"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"
    if [ -f "$skill_file" ]; then
        has_compat=$(grep -c 'Tooling & Path Compatibility' "$skill_file" || true)
        has_host=$(grep -E -c '(host project|host repository)' "$skill_file" || true)
        if [ "$has_compat" -eq 0 ] || [ "$has_host" -eq 0 ]; then
            MISSING_PATH_COMPAT+=("$skill_name")
        fi
    fi
done

if [ ${#MISSING_PATH_COMPAT[@]} -eq 0 ]; then
    assert_condition 0 "All 23 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation"
else
    assert_condition 1 "All 23 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation: ${MISSING_PATH_COMPAT[*]}"
fi

# 11. Validate Submodule Asset Resolution in all 23 skills
echo -e "\n\033[33m11. Validating Submodule Asset Resolution in all 23 skills...\033[0m"
MISSING_ASSET_RES=()
for skill_dir in "$REPO_ROOT"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"
    if [ -f "$skill_file" ]; then
        if ! grep -q 'Submodule Asset Resolution' "$skill_file"; then
            MISSING_ASSET_RES+=("$skill_name")
        fi
    fi
done

if [ ${#MISSING_ASSET_RES[@]} -eq 0 ]; then
    assert_condition 0 "All 23 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution"
else
    assert_condition 1 "All 23 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution: ${MISSING_ASSET_RES[*]}"
fi

# 12. Validate deterministic script lookups in ask-architecture-sync (No recursive disk scans)
echo -e "\n\033[33m12. Validating deterministic script lookups in ask-architecture-sync...\033[0m"
ARCH_SYNC_FILE="$REPO_ROOT/skills/ask-architecture-sync/SKILL.md"
if grep -E -q 'Get-ChildItem.*-Recurse|find[[:space:]]+\.[[:space:]]+-name' "$ARCH_SYNC_FILE"; then
    assert_condition 1 "ask-architecture-sync avoids recursive filesystem scans" "ask-architecture-sync contains recursive scans"
else
    assert_condition 0 "ask-architecture-sync avoids recursive filesystem scans" "ask-architecture-sync contains recursive scans"
fi

# 13. Validate safe Rust requirement (no unsafe) in governance & skills
echo -e "\n\033[33m13. Validating safe Rust requirement (no unsafe) across governance and skills...\033[0m"
RUST_AUDIT_FILES=(
    "$REPO_ROOT/AGENTS.md"
    "$REPO_ROOT/rules/subagents.md"
    "$REPO_ROOT/skills/ask-architect/SKILL.md"
    "$REPO_ROOT/skills/ask-developer/SKILL.md"
    "$REPO_ROOT/skills/ask-security-auditor/SKILL.md"
    "$REPO_ROOT/skills/ask-verification/SKILL.md"
)
MISSING_SAFE_RUST=()
for rf in "${RUST_AUDIT_FILES[@]}"; do
    if [ -f "$rf" ]; then
        if ! grep -E -q 'Rust.*unsafe' "$rf"; then
            MISSING_SAFE_RUST+=("$(basename "$rf")")
        fi
    fi
done

if [ ${#MISSING_SAFE_RUST[@]} -eq 0 ]; then
    assert_condition 0 "All key governance and skills files enforce safe Rust (no unsafe)" "Missing safe Rust rule"
else
    assert_condition 1 "All key governance and skills files enforce safe Rust (no unsafe)" "Missing safe Rust rule in: ${MISSING_SAFE_RUST[*]}"
fi

# 14. Validate GitTroubleshooter backup branch safety snapshot resolution
echo -e "\n\033[33m14. Validating GitTroubleshooter backup branch safety snapshot resolution...\033[0m"
GIT_TROUBLE_FILE="$REPO_ROOT/skills/ask-git-troubleshooter/SKILL.md"
if grep -q '\$branch = (git branch --show-current)' "$GIT_TROUBLE_FILE"; then
    assert_condition 0 "GitTroubleshooter properly resolves \$branch before creating safety snapshot" "GitTroubleshooter uses undefined \$branch"
else
    assert_condition 1 "GitTroubleshooter properly resolves \$branch before creating safety snapshot" "GitTroubleshooter uses undefined \$branch"
fi

# 15. Validate CommitManager submodule isolation guardrail
echo -e "\n\033[33m15. Validating CommitManager submodule isolation guardrail...\033[0m"
COMMIT_MGR_FILE="$REPO_ROOT/skills/ask-commit-manager/SKILL.md"
if grep -q 'Submodule Isolation Guardrail' "$COMMIT_MGR_FILE"; then
    assert_condition 0 "CommitManager enforces Submodule Isolation Guardrail" "CommitManager missing Submodule Isolation Guardrail"
else
    assert_condition 1 "CommitManager enforces Submodule Isolation Guardrail" "CommitManager missing Submodule Isolation Guardrail"
fi

# 16. Validate get-arch-diff git config host repository scoping (-C flag)
echo -e "\n\033[33m16. Validating get-arch-diff git config host repository scoping...\033[0m"
ARCH_DIFF_PS1="$REPO_ROOT/skills/ask-architecture-sync/scripts/get-arch-diff.ps1"
if grep -E -q 'git\s+-C\s+\$repoRoot\s+config\s+--local' "$ARCH_DIFF_PS1"; then
    assert_condition 0 "get-arch-diff.ps1 scopes git config calls to host repo (-C \$repoRoot)" "get-arch-diff.ps1 missing -C \$repoRoot for git config"
else
    assert_condition 1 "get-arch-diff.ps1 scopes git config calls to host repo (-C \$repoRoot)" "get-arch-diff.ps1 missing -C \$repoRoot for git config"
fi

ARCH_DIFF_SH="$REPO_ROOT/skills/ask-architecture-sync/scripts/get-arch-diff.sh"
if grep -E -q 'git\s+-C\s+"\$REPO_ROOT"\s+config\s+--local' "$ARCH_DIFF_SH"; then
    assert_condition 0 "get-arch-diff.sh scopes git config calls to host repo (-C \"\$REPO_ROOT\")" "get-arch-diff.sh missing -C \"\$REPO_ROOT\" for git config"
else
    assert_condition 1 "get-arch-diff.sh scopes git config calls to host repo (-C \"\$REPO_ROOT\")" "get-arch-diff.sh missing -C \"\$REPO_ROOT\" for git config"
fi

# 17. Validate ReleaseManager null-safety and submodule dirty status handling
echo -e "\n\033[33m17. Validating ReleaseManager null-safety and submodule status handling...\033[0m"
RELEASE_MGR_FILE="$REPO_ROOT/skills/ask-release-manager/SKILL.md"
if grep -E -q '\(git branch --show-current\)\.Trim\(\)' "$RELEASE_MGR_FILE"; then
    assert_condition 1 "ReleaseManager avoids unsafe direct Trim on git branch --show-current" "ReleaseManager has unsafe Trim on empty git branch output"
else
    assert_condition 0 "ReleaseManager avoids unsafe direct Trim on git branch --show-current" "ReleaseManager has unsafe Trim on empty git branch output"
fi

if grep -E -q '(--ignore-submodules=dirty|_agents)' "$RELEASE_MGR_FILE"; then
    assert_condition 0 "ReleaseManager handles submodule dirty status gracefully" "ReleaseManager does not handle submodule dirty status"
else
    assert_condition 1 "ReleaseManager handles submodule dirty status gracefully" "ReleaseManager does not handle submodule dirty status"
fi

# 18. Validate CommitManager and PRManager host workspace change scoping
echo -e "\n\033[33m18. Validating CommitManager and PRManager host workspace change scoping...\033[0m"
if grep -E -q '(host workspace|host project)' "$COMMIT_MGR_FILE"; then
    assert_condition 0 "CommitManager scopes uncommitted changes to host workspace" "CommitManager missing host workspace scoping"
else
    assert_condition 1 "CommitManager scopes uncommitted changes to host workspace" "CommitManager missing host workspace scoping"
fi

PR_MGR_FILE="$REPO_ROOT/skills/ask-pr-manager/SKILL.md"
if grep -q 'host project changes' "$PR_MGR_FILE"; then
    assert_condition 0 "PRManager scopes uncommitted changes to host project" "PRManager missing host project scoping"
else
    assert_condition 1 "PRManager scopes uncommitted changes to host project" "PRManager missing host project scoping"
fi

# 19. Validate Control deterministic detect-models path resolution
echo -e "\n\033[33m19. Validating Control deterministic detect-models path resolution...\033[0m"
CONTROL_FILE="$REPO_ROOT/skills/ask-control/SKILL.md"
if grep -q 'Where-Object { Test-Path $_ }' "$CONTROL_FILE"; then
    assert_condition 0 "Control includes deterministic detect-models path resolution" "Control lacks deterministic detect-models path resolution"
else
    assert_condition 1 "Control includes deterministic detect-models path resolution" "Control lacks deterministic detect-models path resolution"
fi

# 20. Validate evals dataset and runner integrity
echo -e "\n\033[33m20. Validating evals dataset and runner integrity...\033[0m"
EVALS_JSON_FILE="$REPO_ROOT/evals/eval-cases.json"
if [ -f "$EVALS_JSON_FILE" ]; then
    assert_condition 0 "evals/eval-cases.json exists" "evals/eval-cases.json not found"
else
    assert_condition 1 "evals/eval-cases.json exists" "evals/eval-cases.json not found"
fi

if [ -f "$REPO_ROOT/scripts/run-evals.ps1" ] && [ -f "$REPO_ROOT/scripts/run-evals.sh" ]; then
    assert_condition 0 "run-evals scripts exist (.ps1 and .sh)" "run-evals scripts missing"
else
    assert_condition 1 "run-evals scripts exist (.ps1 and .sh)" "run-evals scripts missing"
fi

# 21. Validate telemetry logging and dashboard scripts
echo -e "\n\033[33m21. Validating telemetry logging and dashboard scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/record-telemetry.ps1" ] && [ -f "$REPO_ROOT/scripts/record-telemetry.sh" ]; then
    assert_condition 0 "record-telemetry scripts exist (.ps1 and .sh)" "record-telemetry scripts missing"
else
    assert_condition 1 "record-telemetry scripts exist (.ps1 and .sh)" "record-telemetry scripts missing"
fi

if [ -f "$REPO_ROOT/scripts/show-telemetry.ps1" ] && [ -f "$REPO_ROOT/scripts/show-telemetry.sh" ]; then
    assert_condition 0 "show-telemetry scripts exist (.ps1 and .sh)" "show-telemetry scripts missing"
else
    assert_condition 1 "show-telemetry scripts exist (.ps1 and .sh)" "show-telemetry scripts missing"
fi

# 22. Validate ask-control telemetry hook and eval integration
echo -e "\n\033[33m22. Validating ask-control telemetry hook and eval integration...\033[0m"
if grep -q 'record-telemetry' "$CONTROL_FILE" && grep -q 'show-telemetry' "$CONTROL_FILE"; then
    assert_condition 0 "Control documents record-telemetry and show-telemetry hooks" "Control missing telemetry hook documentation"
else
    assert_condition 1 "Control documents record-telemetry and show-telemetry hooks" "Control missing telemetry hook documentation"
fi

if grep -q 'run-evals' "$CONTROL_FILE"; then
    assert_condition 0 "Control documents run-evals benchmark integration" "Control missing run-evals documentation"
else
    assert_condition 1 "Control documents run-evals benchmark integration" "Control missing run-evals documentation"
fi

# 23. Validate tech stack detection and fast-gate scripts
echo -e "\n\033[33m23. Validating tech stack detection and fast-gate scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/detect-tech-stack.ps1" ] && [ -f "$REPO_ROOT/scripts/detect-tech-stack.sh" ]; then
    assert_condition 0 "detect-tech-stack scripts exist (.ps1 and .sh)" "detect-tech-stack scripts missing"
else
    assert_condition 1 "detect-tech-stack scripts exist (.ps1 and .sh)" "detect-tech-stack scripts missing"
fi

if [ -f "$REPO_ROOT/scripts/run-fast-gate.ps1" ] && [ -f "$REPO_ROOT/scripts/run-fast-gate.sh" ]; then
    assert_condition 0 "run-fast-gate scripts exist (.ps1 and .sh)" "run-fast-gate scripts missing"
else
    assert_condition 1 "run-fast-gate scripts exist (.ps1 and .sh)" "run-fast-gate scripts missing"
fi

# 24. Validate guardrails scanner scripts
echo -e "\n\033[33m24. Validating guardrails scanner scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/scan-guardrails.ps1" ] && [ -f "$REPO_ROOT/scripts/scan-guardrails.sh" ]; then
    assert_condition 0 "scan-guardrails scripts exist (.ps1 and .sh)" "scan-guardrails scripts missing"
else
    assert_condition 1 "scan-guardrails scripts exist (.ps1 and .sh)" "scan-guardrails scripts missing"
fi

# 25. Validate requirements linter scripts
echo -e "\n\033[33m25. Validating requirements linter scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/lint-requirements.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-requirements.sh" ]; then
    assert_condition 0 "lint-requirements scripts exist (.ps1 and .sh)" "lint-requirements scripts missing"
else
    assert_condition 1 "lint-requirements scripts exist (.ps1 and .sh)" "lint-requirements scripts missing"
fi

# 26. Validate SemVer calculator scripts
echo -e "\n\033[33m26. Validating SemVer calculator scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/calculate-semver.ps1" ] && [ -f "$REPO_ROOT/scripts/calculate-semver.sh" ]; then
    assert_condition 0 "calculate-semver scripts exist (.ps1 and .sh)" "calculate-semver scripts missing"
else
    assert_condition 1 "calculate-semver scripts exist (.ps1 and .sh)" "calculate-semver scripts missing"
fi

# 27. Validate i18n key audit scripts
echo -e "\n\033[33m27. Validating i18n key audit scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/audit-i18n.ps1" ] && [ -f "$REPO_ROOT/scripts/audit-i18n.sh" ]; then
    assert_condition 0 "audit-i18n scripts exist (.ps1 and .sh)" "audit-i18n scripts missing"
else
    assert_condition 1 "audit-i18n scripts exist (.ps1 and .sh)" "audit-i18n scripts missing"
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
