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
            if [ "$ROLE_COUNT" -eq 6 ]; then
                assert_condition 0 "All 6 roles are registered in model-tiers.json" "Expected 6 roles, found $ROLE_COUNT"
            else
                assert_condition 1 "All 6 roles are registered in model-tiers.json" "Expected 6 roles, found $ROLE_COUNT"
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
if [ "$SKILL_COUNT" -eq 6 ]; then
    assert_condition 0 "Exactly 6 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 6 directories"
else
    assert_condition 1 "Exactly 6 skill directories found in skills/ (Found $SKILL_COUNT)" "Expected 6 skill directories, found $SKILL_COUNT"
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

# 3. Check for Ghost / Orphan Roles & SSOT Synchronization
echo -e "\n\033[33m3. Checking for ghost / orphan roles and SSOT synchronization in markdown documentation...\033[0m"
GHOST_PATTERNS=("TerminalEngineSpecialist" "Tiebreaker" "RequirementEngineer" "CodeReviewer" "SecurityAuditor" "DevOpsEngineer" "LocalizationSpecialist" "DatabaseSpecialist" "ApiContractSpecialist" "PerformanceOptimizer" "RefactoringSpecialist" "DocumentationSpecialist" "ArchitectureSync" "UIDesigner" "CodeExplainer" "PRManager")
FOUND_GHOSTS=()
for pattern in "${GHOST_PATTERNS[@]}"; do
    while IFS= read -r match_file; do
        if [ -n "$match_file" ]; then
            FOUND_GHOSTS+=("$match_file ($pattern)")
        fi
    done < <(grep -rnw --exclude-dir=".git" --include="*.md" "$REPO_ROOT" -e "$pattern" 2>/dev/null | cut -d: -f1 | sort -u || true)
done

if [ ${#FOUND_GHOSTS[@]} -eq 0 ]; then
    assert_condition 0 "Zero occurrences of retired V1 or ghost roles across all markdown files" "Found retired/ghost roles"
else
    assert_condition 1 "Zero occurrences of retired V1 or ghost roles across all markdown files" "Found retired/ghost roles in: ${FOUND_GHOSTS[*]}"
fi

# 4. Check OS-native line endings (CRLF on Windows/MINGW, LF on Linux/macOS)
OS_UNAME_TEST="$(uname -s 2>/dev/null || echo "")"
case "$OS_UNAME_TEST" in
    MINGW*|MSYS*|CYGWIN*) EXPECTED_OS_EOL="CRLF" ;;
    *) EXPECTED_OS_EOL="LF" ;;
esac
echo -e "\n\033[33m4. Checking line endings (must be ${EXPECTED_OS_EOL})...\033[0m"
if [ "$EXPECTED_OS_EOL" = "LF" ]; then
    CRLF_COUNT=$(find "$REPO_ROOT" -type f -not -path '*/.*' -exec file {} + 2>/dev/null | grep "CRLF" | wc -l || true)
    if [ "$CRLF_COUNT" -eq 0 ]; then
        assert_condition 0 "All repository files use LF line endings" "CRLF line endings detected"
    else
        assert_condition 1 "All repository files use LF line endings" "CRLF line endings detected in $CRLF_COUNT files"
    fi
else
    if bash "$REPO_ROOT/scripts/scan-guardrails.sh" --path "$REPO_ROOT" >/dev/null 2>&1; then
        assert_condition 0 "All repository files use OS-native CRLF line endings" "Line ending violations detected"
    else
        assert_condition 1 "All repository files use OS-native CRLF line endings" "Line ending violations detected"
    fi
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
    if command -v python3 >/dev/null 2>&1; then
        while IFS= read -r rel_link; do
            rel_link="${rel_link%$'\r'}"
            if [ -n "$rel_link" ]; then
                target_path="$md_dir/$rel_link"
                if [ ! -e "$target_path" ]; then
                    BROKEN_LINKS+=("${md_file#$REPO_ROOT/} -> $rel_link")
                fi
            fi
        done < <(python3 - "$md_file" << 'EOF' 2>/dev/null || true
import re, sys
content = open(sys.argv[1], 'r', encoding='utf-8', errors='ignore').read()
content = re.sub(r'(?s)```.*?```|~~~.*?~~~', '', content)
content = re.sub(r'`[^`\r\n]+`', '', content)
for m in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', content):
    link = m.group(2).split('#')[0].strip()
    if link and not link.startswith(('http://', 'https://', 'mailto:', 'file:', '#')):
        print(link)
EOF
        )
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
    while IFS= read -r match; do
        if [ -n "$match" ]; then
            line_num="$(echo "$match" | cut -d: -f1)"
            line_content="$(echo "$match" | cut -d: -f2-)"
            if ! echo "$line_content" | grep -q -- '-NoProfile'; then
                MISSING_NOPROFILE+=("${md_file#$REPO_ROOT/}:$line_num")
            fi
        fi
    done < <(grep -nE '^\s*(pwsh|powershell)(\.exe)?\s+|`(pwsh|powershell)(\.exe)?\s+' "$md_file" 2>/dev/null || true)
done < <(find "$REPO_ROOT" -type f -name "*.md" -not -path '*/.*' 2>/dev/null)

if [ ${#MISSING_NOPROFILE[@]} -eq 0 ]; then
    assert_condition 0 "All powershell/pwsh command invocations include -NoProfile" "powershell/pwsh commands missing -NoProfile"
else
    assert_condition 1 "All powershell/pwsh command invocations include -NoProfile" "powershell/pwsh commands missing -NoProfile in: ${MISSING_NOPROFILE[*]}"
fi

# 8. Validate get-arch-diff submodule exclusions (_agents and .agents)
echo -e "\n\033[33m8. Validating get-arch-diff submodule exclusions...\033[0m"
ARCH_DIFF_PS1="$REPO_ROOT/scripts/get-arch-diff.ps1"
ARCH_DIFF_SH="$REPO_ROOT/scripts/get-arch-diff.sh"

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

# 9. Validate model tier references in all 6 skills
echo -e "\n\033[33m9. Validate model tier references in all 6 skills...\033[0m"
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
    assert_condition 0 "All 6 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json reference"
else
    assert_condition 1 "All 6 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json: ${MISSING_TIER_REF[*]}"
fi

# 10. Validate Tooling & Path Compatibility and host project orientation in all 6 skills
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
    assert_condition 0 "All 6 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation"
else
    assert_condition 1 "All 6 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation: ${MISSING_PATH_COMPAT[*]}"
fi

# 11. Validate Submodule Asset Resolution in all 6 skills
echo -e "\n\033[33m11. Validating Submodule Asset Resolution in all 6 skills...\033[0m"
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
    assert_condition 0 "All 6 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution"
else
    assert_condition 1 "All 6 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution: ${MISSING_ASSET_RES[*]}"
fi

# 12. Validate deterministic script lookups in ask-contract-specialist (No recursive disk scans)
echo -e "\n\033[33m12. Validating deterministic script lookups in ask-contract-specialist...\033[0m"
ARCH_SYNC_FILE="$REPO_ROOT/skills/ask-contract-specialist/SKILL.md"
if grep -E -q 'Get-ChildItem.*-Recurse|find[[:space:]]+\.[[:space:]]+-name' "$ARCH_SYNC_FILE"; then
    assert_condition 1 "ask-contract-specialist avoids recursive filesystem scans" "ask-contract-specialist contains recursive scans"
else
    assert_condition 0 "ask-contract-specialist avoids recursive filesystem scans" "ask-contract-specialist contains recursive scans"
fi

# 13. Validate safe Rust requirement (no unsafe) in governance & skills
echo -e "\n\033[33m13. Validating safe Rust requirement (no unsafe) across governance and skills...\033[0m"
RUST_AUDIT_FILES=(
    "$REPO_ROOT/AGENTS.md"
    "$REPO_ROOT/rules/subagents.md"
    "$REPO_ROOT/skills/ask-control/SKILL.md"
    "$REPO_ROOT/skills/ask-troubleshooter/SKILL.md"
    "$REPO_ROOT/skills/ask-contract-specialist/SKILL.md"
    "$REPO_ROOT/skills/ask-release-manager/SKILL.md"
    "$REPO_ROOT/skills/ask-skill-auditor/SKILL.md"
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

# 15. Validate Control submodule isolation guardrail
echo -e "\n\033[33m15. Validating Control submodule isolation guardrail...\033[0m"
CONTROL_FILE="$REPO_ROOT/skills/ask-control/SKILL.md"
if grep -q 'Submodule Isolation Guardrail' "$CONTROL_FILE"; then
    assert_condition 0 "Control enforces Submodule Isolation Guardrail" "Control missing Submodule Isolation Guardrail"
else
    assert_condition 1 "Control enforces Submodule Isolation Guardrail" "Control missing Submodule Isolation Guardrail"
fi

# 16. Validate get-arch-diff git config host repository scoping (-C flag)
echo -e "\n\033[33m16. Validating get-arch-diff git config host repository scoping...\033[0m"
ARCH_DIFF_PS1="$REPO_ROOT/scripts/get-arch-diff.ps1"
if grep -E -q 'git\s+-C\s+\$repoRoot\s+config\s+--local' "$ARCH_DIFF_PS1"; then
    assert_condition 0 "get-arch-diff.ps1 scopes git config calls to host repo (-C \$repoRoot)" "get-arch-diff.ps1 missing -C \$repoRoot for git config"
else
    assert_condition 1 "get-arch-diff.ps1 scopes git config calls to host repo (-C \$repoRoot)" "get-arch-diff.ps1 missing -C \$repoRoot for git config"
fi

ARCH_DIFF_SH="$REPO_ROOT/scripts/get-arch-diff.sh"
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

# 18. Validate Control host workspace change scoping
echo -e "\n\033[33m18. Validating Control host workspace change scoping...\033[0m"
if grep -E -q '(host workspace|host project)' "$CONTROL_FILE"; then
    assert_condition 0 "Control scopes uncommitted changes to host workspace" "Control missing host workspace scoping"
else
    assert_condition 1 "Control scopes uncommitted changes to host workspace" "Control missing host workspace scoping"
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
    EVALS_OUT=$(bash "$REPO_ROOT/scripts/run-evals.sh" --json 2>/dev/null || true)
    if echo "$EVALS_OUT" | grep -Eq '"failed":[[:space:]]*0' && ! echo "$EVALS_OUT" | grep -Eq '"passed":[[:space:]]*0([^0-9]|$)'; then
        assert_condition 0 "run-evals.sh benchmark passes 100%" "run-evals.sh failed benchmark cases"
    else
        assert_condition 1 "run-evals.sh benchmark passes 100%" "run-evals.sh failed benchmark cases"
    fi
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
    TEMP_FG_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'fg')
    git -C "$TEMP_FG_DIR" init -q 2>/dev/null || true
    printf 'pub fn bad() { unsafe { } }\n' > "$TEMP_FG_DIR/lib.rs"
    FG_OUT=$(bash "$REPO_ROOT/scripts/run-fast-gate.sh" "$TEMP_FG_DIR" --json 2>/dev/null || true)
    rm -rf "$TEMP_FG_DIR"
    if echo "$FG_OUT" | grep -Eq '"status":[[:space:]]*"fail"'; then
        assert_condition 0 "run-fast-gate.sh enforces guardrails even without build_cmd" "run-fast-gate.sh skipped guardrails when build_cmd was empty"
    else
        assert_condition 1 "run-fast-gate.sh enforces guardrails even without build_cmd" "run-fast-gate.sh skipped guardrails when build_cmd was empty"
    fi
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
    SV_SH_OUT=$(bash "$REPO_ROOT/scripts/calculate-semver.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$SV_SH_OUT" | grep -q '"next_version":' && echo "$SV_SH_OUT" | grep -q '"commits_analyzed":' && echo "$SV_SH_OUT" | grep -q '"release_notes":'; then
        assert_condition 0 "calculate-semver.sh outputs .ps1-compatible JSON schema" "calculate-semver.sh JSON schema mismatch: $SV_SH_OUT"
    else
        assert_condition 1 "calculate-semver.sh outputs .ps1-compatible JSON schema" "calculate-semver.sh JSON schema mismatch: $SV_SH_OUT"
    fi
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

# 28. Validate PR summary generator scripts
echo -e "\n\033[33m28. Validating PR summary generator scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/generate-pr-summary.ps1" ] && [ -f "$REPO_ROOT/scripts/generate-pr-summary.sh" ]; then
    assert_condition 0 "generate-pr-summary scripts exist (.ps1 and .sh)" "generate-pr-summary scripts missing"
    PR_SH_OUT=$(bash "$REPO_ROOT/scripts/generate-pr-summary.sh" --base main --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$PR_SH_OUT" | grep -q '"referenced_reqs":' && echo "$PR_SH_OUT" | grep -q '"pr_body_markdown":'; then
        assert_condition 0 "generate-pr-summary.sh outputs .ps1-compatible JSON schema" "generate-pr-summary.sh JSON schema mismatch: $PR_SH_OUT"
    else
        assert_condition 1 "generate-pr-summary.sh outputs .ps1-compatible JSON schema" "generate-pr-summary.sh JSON schema mismatch: $PR_SH_OUT"
    fi
else
    assert_condition 1 "generate-pr-summary scripts exist (.ps1 and .sh)" "generate-pr-summary scripts missing"
fi

# 29. Validate Git state diagnostic scripts
echo -e "\n\033[33m29. Validating Git state diagnostic scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/diagnose-git-state.ps1" ] && [ -f "$REPO_ROOT/scripts/diagnose-git-state.sh" ]; then
    assert_condition 0 "diagnose-git-state scripts exist (.ps1 and .sh)" "diagnose-git-state scripts missing"
    DIAG_SH_OUT=$(bash "$REPO_ROOT/scripts/diagnose-git-state.sh" "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$DIAG_SH_OUT" | grep -q '"state":' && echo "$DIAG_SH_OUT" | grep -q '"created_snapshot_branch":' && echo "$DIAG_SH_OUT" | grep -q '"is_cherry_pick_in_progress":'; then
        assert_condition 0 "diagnose-git-state.sh outputs full .ps1-compatible JSON schema" "diagnose-git-state.sh JSON schema mismatch: $DIAG_SH_OUT"
    else
        assert_condition 1 "diagnose-git-state.sh outputs full .ps1-compatible JSON schema" "diagnose-git-state.sh JSON schema mismatch: $DIAG_SH_OUT"
    fi
else
    assert_condition 1 "diagnose-git-state scripts exist (.ps1 and .sh)" "diagnose-git-state scripts missing"
fi

# 30. Validate documentation link linter scripts
echo -e "\n\033[33m30. Validating documentation link linter scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/lint-docs.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-docs.sh" ]; then
    assert_condition 0 "lint-docs scripts exist (.ps1 and .sh)" "lint-docs scripts missing"
else
    assert_condition 1 "lint-docs scripts exist (.ps1 and .sh)" "lint-docs scripts missing"
fi
# 31. Validate Clean Architecture rules and linter scripts
echo -e "\n\033[33m31. Validating Clean Architecture rules and linter scripts...\033[0m"
if [ -f "$REPO_ROOT/rules/clean-architecture.json" ]; then
    assert_condition 0 "rules/clean-architecture.json exists" "rules/clean-architecture.json not found"
else
    assert_condition 1 "rules/clean-architecture.json exists" "rules/clean-architecture.json not found"
fi

if [ -f "$REPO_ROOT/scripts/lint-clean-architecture.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-clean-architecture.sh" ]; then
    assert_condition 0 "lint-clean-architecture scripts exist (.ps1 and .sh)" "lint-clean-architecture scripts missing"
    TEMP_ARCH_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'arch')
    mkdir -p "$TEMP_ARCH_DIR/domain"
    printf "import React from 'infrastructure/db';\n" > "$TEMP_ARCH_DIR/domain/Widget.tsx"
    TSX_ARCH_OUT=$(bash "$REPO_ROOT/scripts/lint-clean-architecture.sh" "$TEMP_ARCH_DIR" --json 2>/dev/null || true)
    rm -rf "$TEMP_ARCH_DIR"
    if echo "$TSX_ARCH_OUT" | grep -Eq '"status":[[:space:]]*"fail"'; then
        assert_condition 0 "lint-clean-architecture.sh catches boundary violation in .tsx files" "lint-clean-architecture.sh missed .tsx boundary violation"
    else
        assert_condition 1 "lint-clean-architecture.sh catches boundary violation in .tsx files" "lint-clean-architecture.sh missed .tsx boundary violation"
    fi
else
    assert_condition 1 "lint-clean-architecture scripts exist (.ps1 and .sh)" "lint-clean-architecture scripts missing"
fi

# 32. Validate changelog generator scripts
echo -e "\n\033[33m32. Validating changelog generator scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/generate-changelog.ps1" ] && [ -f "$REPO_ROOT/scripts/generate-changelog.sh" ]; then
    assert_condition 0 "generate-changelog scripts exist (.ps1 and .sh)" "generate-changelog scripts missing"
    CL_SH_OUT=$(bash "$REPO_ROOT/scripts/generate-changelog.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$CL_SH_OUT" | grep -q '"markdown":'; then
        assert_condition 0 "generate-changelog.sh outputs markdown JSON field" "generate-changelog.sh missing markdown JSON field: $CL_SH_OUT"
    else
        assert_condition 1 "generate-changelog.sh outputs markdown JSON field" "generate-changelog.sh missing markdown JSON field: $CL_SH_OUT"
    fi
else
    assert_condition 1 "generate-changelog scripts exist (.ps1 and .sh)" "generate-changelog scripts missing"
fi

# 33. Validate security audit scripts
echo -e "\n\033[33m33. Validating security audit scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/run-security-audit.ps1" ] && [ -f "$REPO_ROOT/scripts/run-security-audit.sh" ]; then
    assert_condition 0 "run-security-audit scripts exist (.ps1 and .sh)" "run-security-audit scripts missing"
    SEC_SH_OUT=$(bash "$REPO_ROOT/scripts/run-security-audit.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$SEC_SH_OUT" | grep -q '"ecosystem_audits":'; then
        assert_condition 0 "run-security-audit.sh outputs ecosystem_audits JSON field" "run-security-audit.sh missing ecosystem_audits: $SEC_SH_OUT"
    else
        assert_condition 1 "run-security-audit.sh outputs ecosystem_audits JSON field" "run-security-audit.sh missing ecosystem_audits: $SEC_SH_OUT"
    fi
else
    assert_condition 1 "run-security-audit scripts exist (.ps1 and .sh)" "run-security-audit scripts missing"
fi
# 34. Validate test coverage parser scripts
echo -e "\n\033[33m34. Validating test coverage parser scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/check-test-coverage.ps1" ] && [ -f "$REPO_ROOT/scripts/check-test-coverage.sh" ]; then
    assert_condition 0 "check-test-coverage scripts exist (.ps1 and .sh)" "check-test-coverage scripts missing"
    TEMP_COV_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'cov')
    mkdir -p "$TEMP_COV_DIR/coverage"
    printf '{"total":{"lines":{"pct":85.5},"branches":{"pct":72.0}}}\n' > "$TEMP_COV_DIR/coverage/coverage-summary.json"
    COV_SH_OUT=$(bash "$REPO_ROOT/scripts/check-test-coverage.sh" --repo-root "$TEMP_COV_DIR" --threshold 80 --json 2>/dev/null || true)
    rm -rf "$TEMP_COV_DIR"
    if echo "$COV_SH_OUT" | grep -q '"coverage_found":true' && echo "$COV_SH_OUT" | grep -q '"report_file":' && echo "$COV_SH_OUT" | grep -q '"branch_coverage_pct":'; then
        assert_condition 0 "check-test-coverage.sh discovers nested coverage/coverage-summary.json with full JSON schema" "check-test-coverage.sh failed nested discovery or JSON parity: $COV_SH_OUT"
    else
        assert_condition 1 "check-test-coverage.sh discovers nested coverage/coverage-summary.json with full JSON schema" "check-test-coverage.sh failed nested discovery or JSON parity: $COV_SH_OUT"
    fi
else
    assert_condition 1 "check-test-coverage scripts exist (.ps1 and .sh)" "check-test-coverage scripts missing"
fi
# 35. Validate database migration linter scripts
echo -e "\n\033[33m35. Validating database migration linter scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/lint-db-migrations.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-db-migrations.sh" ]; then
    assert_condition 0 "lint-db-migrations scripts exist (.ps1 and .sh)" "lint-db-migrations scripts missing"
    TEMP_DB_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'db')
    mkdir -p "$TEMP_DB_DIR/src/db"
    printf 'CREATE TABLE users(id INT);\n' > "$TEMP_DB_DIR/src/db/0001_init.sql"
    printf 'DROP TABLE users;\n' > "$TEMP_DB_DIR/src/db/0001_dup.sql"
    DB_SH_OUT=$(bash "$REPO_ROOT/scripts/lint-db-migrations.sh" --repo-root "$TEMP_DB_DIR" --json 2>/dev/null || true)
    rm -rf "$TEMP_DB_DIR"
    if echo "$DB_SH_OUT" | grep -q '"migrations_count":2' && echo "$DB_SH_OUT" | grep -q '"errors_count":1' && echo "$DB_SH_OUT" | grep -q '"errors":\['; then
        assert_condition 0 "lint-db-migrations.sh matches filename prefixes under src/ and outputs full JSON" "lint-db-migrations.sh failed filename matching or JSON schema: $DB_SH_OUT"
    else
        assert_condition 1 "lint-db-migrations.sh matches filename prefixes under src/ and outputs full JSON" "lint-db-migrations.sh failed filename matching or JSON schema: $DB_SH_OUT"
    fi
else
    assert_condition 1 "lint-db-migrations scripts exist (.ps1 and .sh)" "lint-db-migrations scripts missing"
fi

# 36. Validate API contract linter scripts
echo -e "\n\033[33m36. Validating API contract linter scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/lint-api-contracts.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-api-contracts.sh" ]; then
    assert_condition 0 "lint-api-contracts scripts exist (.ps1 and .sh)" "lint-api-contracts scripts missing"
    API_SH_OUT=$(bash "$REPO_ROOT/scripts/lint-api-contracts.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$API_SH_OUT" | grep -q '"errors":\[' && echo "$API_SH_OUT" | grep -q '"message":'; then
        assert_condition 0 "lint-api-contracts.sh outputs .ps1-compatible JSON schema" "lint-api-contracts.sh JSON schema mismatch: $API_SH_OUT"
    else
        assert_condition 1 "lint-api-contracts.sh outputs .ps1-compatible JSON schema" "lint-api-contracts.sh JSON schema mismatch: $API_SH_OUT"
    fi
else
    assert_condition 1 "lint-api-contracts scripts exist (.ps1 and .sh)" "lint-api-contracts scripts missing"
fi
# 37. Validate orphaned assets detector scripts
echo -e "\n\033[33m37. Validating orphaned assets detector scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/find-orphaned-assets.ps1" ] && [ -f "$REPO_ROOT/scripts/find-orphaned-assets.sh" ]; then
    assert_condition 0 "find-orphaned-assets scripts exist (.ps1 and .sh)" "find-orphaned-assets scripts missing"
    OA_SH_OUT=$(bash "$REPO_ROOT/scripts/find-orphaned-assets.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null || true)
    if echo "$OA_SH_OUT" | grep -q '"orphaned_assets":\[' && echo "$OA_SH_OUT" | grep -q '"orphaned_docs":\[' && echo "$OA_SH_OUT" | grep -q '"message":'; then
        assert_condition 0 "find-orphaned-assets.sh outputs .ps1-compatible JSON schema" "find-orphaned-assets.sh JSON schema mismatch: $OA_SH_OUT"
    else
        assert_condition 1 "find-orphaned-assets.sh outputs .ps1-compatible JSON schema" "find-orphaned-assets.sh JSON schema mismatch: $OA_SH_OUT"
    fi
else
    assert_condition 1 "find-orphaned-assets scripts exist (.ps1 and .sh)" "find-orphaned-assets scripts missing"
fi

# 38. Validate CI workflow linter scripts
echo -e "\n\033[33m38. Validating CI workflow linter scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/lint-ci-workflows.ps1" ] && [ -f "$REPO_ROOT/scripts/lint-ci-workflows.sh" ]; then
    assert_condition 0 "lint-ci-workflows scripts exist (.ps1 and .sh)" "lint-ci-workflows scripts missing"
else
    assert_condition 1 "lint-ci-workflows scripts exist (.ps1 and .sh)" "lint-ci-workflows scripts missing"
fi

# 39. Validate unified quality gates orchestrator scripts
echo -e "\n\033[33m39. Validating unified quality gates orchestrator scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/run-all-gates.ps1" ] && [ -f "$REPO_ROOT/scripts/run-all-gates.sh" ]; then
    assert_condition 0 "run-all-gates scripts exist (.ps1 and .sh)" "run-all-gates scripts missing"
    GATES_SH_OUT=$(bash "$REPO_ROOT/scripts/run-all-gates.sh" "$REPO_ROOT" --fast --json 2>/dev/null || true)
    if echo "$GATES_SH_OUT" | grep -q '"status":"pass"' && echo "$GATES_SH_OUT" | grep -q '"passed_gates":' && echo "$GATES_SH_OUT" | grep -q '"failed_gates":0'; then
        assert_condition 0 "run-all-gates.sh --fast --json executes cleanly with .ps1-compatible schema" "run-all-gates.sh failed or mismatched JSON schema: $GATES_SH_OUT"
    else
        assert_condition 1 "run-all-gates.sh --fast --json executes cleanly with .ps1-compatible schema" "run-all-gates.sh failed or mismatched JSON schema: $GATES_SH_OUT"
    fi
else
    assert_condition 1 "run-all-gates scripts exist (.ps1 and .sh)" "run-all-gates scripts missing"
fi

# 40. Validate test failure diagnostic scripts
echo -e "\n\033[33m40. Validating test failure diagnostic scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/collect-test-failures.ps1" ] && [ -f "$REPO_ROOT/scripts/collect-test-failures.sh" ]; then
    assert_condition 0 "collect-test-failures scripts exist (.ps1 and .sh)" "collect-test-failures scripts missing"
else
    assert_condition 1 "collect-test-failures scripts exist (.ps1 and .sh)" "collect-test-failures scripts missing"
fi

# 41. Validate startup benchmark scripts
echo -e "\n\033[33m41. Validating startup benchmark scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/benchmark-startup.ps1" ] && [ -f "$REPO_ROOT/scripts/benchmark-startup.sh" ]; then
    assert_condition 0 "benchmark-startup scripts exist (.ps1 and .sh)" "benchmark-startup scripts missing"
else
    assert_condition 1 "benchmark-startup scripts exist (.ps1 and .sh)" "benchmark-startup scripts missing"
fi

# 42. Validate feature specification inspector and scaffolding scripts
echo -e "\n\033[33m42. Validating feature specification inspector scripts...\033[0m"
if [ -f "$REPO_ROOT/scripts/inspect-feature-specs.ps1" ] && [ -f "$REPO_ROOT/scripts/inspect-feature-specs.sh" ]; then
    assert_condition 0 "inspect-feature-specs scripts exist (.ps1 and .sh)" "inspect-feature-specs scripts missing"
    TEMP_SPEC_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'specs')
    NEW_FEAT_SH=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$TEMP_SPEC_DIR" --new --id "FEAT-CORE-001" --title "Domain / Auth & Core" --phase 1 --scope "CORE" --json 2>/dev/null || true)
    if echo "$NEW_FEAT_SH" | grep -q '"status":"created"' && echo "$NEW_FEAT_SH" | grep -q '"roadmap_updated":false' && [ -f "$TEMP_SPEC_DIR/docs/features/FEAT-CORE-001-domain-auth-core.md" ]; then
        assert_condition 0 "inspect-feature-specs.sh --new scaffolds feature safely (slashes in title, boolean JSON)" "inspect-feature-specs.sh --new failed: $NEW_FEAT_SH"
    else
        assert_condition 1 "inspect-feature-specs.sh --new scaffolds feature safely (slashes in title, boolean JSON)" "inspect-feature-specs.sh --new failed: $NEW_FEAT_SH"
    fi
    NEW_CONCEPT_SH=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$TEMP_SPEC_DIR" --new-concept --concept-id "CONCEPT-AUTH-001" --title "OAuth2 / PKCE & Login" --scope "AUTH" --json 2>/dev/null || true)
    if echo "$NEW_CONCEPT_SH" | grep -q '"id":"CONCEPT-AUTH-001"' && [ -f "$TEMP_SPEC_DIR/docs/concepts/drafts/CONCEPT-AUTH-001-oauth2-pkce-login.md" ]; then
        assert_condition 0 "inspect-feature-specs.sh --new-concept --concept-id honors explicit ConceptId and special chars" "inspect-feature-specs.sh --new-concept failed: $NEW_CONCEPT_SH"
    else
        assert_condition 1 "inspect-feature-specs.sh --new-concept --concept-id honors explicit ConceptId and special chars" "inspect-feature-specs.sh --new-concept failed: $NEW_CONCEPT_SH"
    fi
    ARCH_CONCEPT_SH=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$TEMP_SPEC_DIR" --archive-concept "CONCEPT-AUTH-001" --json 2>/dev/null || true)
    if echo "$ARCH_CONCEPT_SH" | grep -q '"status":"archived"' && [ -f "$TEMP_SPEC_DIR/docs/concepts/archive/CONCEPT-AUTH-001-oauth2-pkce-login.md" ]; then
        assert_condition 0 "inspect-feature-specs.sh --archive-concept archives draft" "inspect-feature-specs.sh --archive-concept failed: $ARCH_CONCEPT_SH"
    else
        assert_condition 1 "inspect-feature-specs.sh --archive-concept archives draft" "inspect-feature-specs.sh --archive-concept failed: $ARCH_CONCEPT_SH"
    fi
    DRIFT_UPD_SH=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$TEMP_SPEC_DIR" --check-drift --update-state --json 2>/dev/null || true)
    DRIFT_SYNC_SH=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$TEMP_SPEC_DIR" --check-drift --json 2>/dev/null || true)
    if echo "$DRIFT_UPD_SH" | grep -q '"status":"drift_detected"' && echo "$DRIFT_SYNC_SH" | grep -q '"status":"synchronized"'; then
        assert_condition 0 "inspect-feature-specs.sh --check-drift and --update-state track spec hashes" "inspect-feature-specs.sh --check-drift failed: $DRIFT_UPD_SH | $DRIFT_SYNC_SH"
    else
        assert_condition 1 "inspect-feature-specs.sh --check-drift and --update-state track spec hashes" "inspect-feature-specs.sh --check-drift failed: $DRIFT_UPD_SH | $DRIFT_SYNC_SH"
    fi
    rm -rf "$TEMP_SPEC_DIR"
else
    assert_condition 1 "inspect-feature-specs scripts exist (.ps1 and .sh)" "inspect-feature-specs scripts missing"
fi
if [ -f "$REPO_ROOT/docs/templates/CONCEPT_TEMPLATE.md" ]; then
    assert_condition 0 "docs/templates/CONCEPT_TEMPLATE.md exists" "docs/templates/CONCEPT_TEMPLATE.md missing"
else
    assert_condition 1 "docs/templates/CONCEPT_TEMPLATE.md exists" "docs/templates/CONCEPT_TEMPLATE.md missing"
fi

# 43. Validate setup-agent-skills --init-docs and Next-Gen LLM Governance invariants
echo -e "\n\033[33m43. Validating project onboarding (--init-docs) and Next-Gen LLM Governance...\033[0m"
SETUP_PS1="$REPO_ROOT/scripts/setup-agent-skills.ps1"
SETUP_SH="$REPO_ROOT/scripts/setup-agent-skills.sh"
[ -f "$SETUP_PS1" ] && assert_condition 0 "scripts/setup-agent-skills.ps1 exists" "scripts/setup-agent-skills.ps1 not found" || assert_condition 1 "scripts/setup-agent-skills.ps1 exists" "scripts/setup-agent-skills.ps1 not found"
[ -f "$SETUP_SH" ] && assert_condition 0 "scripts/setup-agent-skills.sh exists" "scripts/setup-agent-skills.sh not found" || assert_condition 1 "scripts/setup-agent-skills.sh exists" "scripts/setup-agent-skills.sh not found"

if grep -q "MCP & External Tool Governance" "$REPO_ROOT/AGENTS.md"; then
    assert_condition 0 "AGENTS.md enforces MCP & External Tool Governance" "AGENTS.md missing MCP governance"
else
    assert_condition 1 "AGENTS.md enforces MCP & External Tool Governance" "AGENTS.md missing MCP governance"
fi
if grep -q 'Workspace: "share"' "$REPO_ROOT/skills/ask-control/SKILL.md"; then
    assert_condition 0 "ask-control documents isolated parallel worktrees" "ask-control missing parallel worktrees"
else
    assert_condition 1 "ask-control documents isolated parallel worktrees" "ask-control missing parallel worktrees"
fi
if grep -q "Accessibility (a11y)" "$REPO_ROOT/skills/ask-contract-specialist/SKILL.md"; then
    assert_condition 0 "ask-contract-specialist documents UI/UX & Accessibility (a11y)" "ask-contract-specialist missing a11y"
else
    assert_condition 1 "ask-contract-specialist documents UI/UX & Accessibility (a11y)" "ask-contract-specialist missing a11y"
fi

if [ -f "$SETUP_SH" ]; then
    # 43a. AGY-only project setup (--client agy / --skip-copilot -> _agents)
    TEMP_PROJ=$(mktemp -d 2>/dev/null || mktemp -d -t 'proj')
    if bash "$SETUP_SH" --project "$TEMP_PROJ" --init-docs --skip-copilot >/dev/null 2>&1; then
        if [ -f "$TEMP_PROJ/ARCHITECTURE.md" ] && [ -f "$TEMP_PROJ/docs/ROADMAP.md" ]; then
            assert_condition 0 "setup-agent-skills.sh --init-docs scaffolds ARCHITECTURE.md and docs/ROADMAP.md" "setup-agent-skills.sh --init-docs failed"
        else
            assert_condition 1 "setup-agent-skills.sh --init-docs scaffolds ARCHITECTURE.md and docs/ROADMAP.md" "setup-agent-skills.sh --init-docs missing files"
        fi
        if [ -e "$TEMP_PROJ/_agents" ] && [ ! -e "$TEMP_PROJ/.agents" ]; then
            assert_condition 0 "AGY-only project setup creates _agents without .agents" "AGY-only setup link mismatch"
        else
            assert_condition 1 "AGY-only project setup creates _agents without .agents" "AGY-only setup link mismatch"
        fi
    fi
    rm -rf "$TEMP_PROJ"

    # 43b. Copilot-only project setup (--client copilot -> .agents + .github/copilot-instructions.md)
    TEMP_COPILOT_PROJ=$(mktemp -d 2>/dev/null || mktemp -d -t 'proj_copilot')
    if bash "$SETUP_SH" --project "$TEMP_COPILOT_PROJ" --client copilot >/dev/null 2>&1; then
        if [ -f "$TEMP_COPILOT_PROJ/.agents/skills/ask-control/SKILL.md" ] && [ ! -e "$TEMP_COPILOT_PROJ/_agents" ]; then
            assert_condition 0 "Copilot-only project setup creates .agents (and not _agents)" "Copilot-only setup link mismatch"
        else
            assert_condition 1 "Copilot-only project setup creates .agents (and not _agents)" "Copilot-only setup link mismatch"
        fi
        COPILOT_INSTR="$TEMP_COPILOT_PROJ/.github/copilot-instructions.md"
        if [ -f "$COPILOT_INSTR" ] && grep -q '\./\.agents/scripts/' "$COPILOT_INSTR" && grep -q '\.agents/skills/' "$COPILOT_INSTR"; then
            assert_condition 0 "Provisioned .github/copilot-instructions.md resolves via .agents/" "Copilot instructions do not resolve via .agents/"
        else
            assert_condition 1 "Provisioned .github/copilot-instructions.md resolves via .agents/" "Copilot instructions do not resolve via .agents/"
        fi
    fi
    rm -rf "$TEMP_COPILOT_PROJ"

    # 43c. Global User-Level setup (--global -> ~/_agents for AGY and ~/.agents + Zero-Reload inlined instructions for Copilot)
    TEMP_HOME=$(mktemp -d 2>/dev/null || mktemp -d -t 'home')
    if bash "$SETUP_SH" --global --user-home "$TEMP_HOME" >/dev/null 2>&1; then
        if [ -f "$TEMP_HOME/_agents/skills/ask-control/SKILL.md" ] && [ -f "$TEMP_HOME/.gemini/config/skills/ask-control/SKILL.md" ]; then
            assert_condition 0 "Global user setup links ~/_agents and ~/.gemini/config/skills for AGY" "Global AGY setup failed"
        else
            assert_condition 1 "Global user setup links ~/_agents and ~/.gemini/config/skills for AGY" "Global AGY setup failed"
        fi
        USER_INSTR="$TEMP_HOME/.copilot/instructions/agent-skills.instructions.md"
        if [ -f "$TEMP_HOME/.agents/skills/ask-control/SKILL.md" ] && [ -f "$USER_INSTR" ] && grep -q 'applyTo: "\*\*/\*"' "$USER_INSTR" && grep -q 'Inner-Loop TDD' "$USER_INSTR"; then
            assert_condition 0 "Global user setup links ~/.agents and inlines Zero-Reload instructions for Copilot" "Global Copilot setup failed"
        else
            assert_condition 1 "Global user setup links ~/.agents and inlines Zero-Reload instructions for Copilot" "Global Copilot setup failed"
        fi
    fi
    rm -rf "$TEMP_HOME"
fi

# 44. Validate Shift-Left WorkingTree Guardrails (inline/2024 Safe-Rust) and Behavioral Trace Evals
echo -e "\n\033[33m44. Validating Shift-Left WorkingTree Guardrails & Behavioral Trace Evals...\033[0m"
TEMP_RUST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'rust')
git -C "$TEMP_RUST_DIR" init -q 2>/dev/null || true
printf '#[unsafe(no_mangle)]\npub fn demo() { let _x = unsafe { 42 }; }\n' > "$TEMP_RUST_DIR/lib.rs"
WT_GUARD_OUT=$(bash "$REPO_ROOT/scripts/scan-guardrails.sh" "$TEMP_RUST_DIR" --working-tree --json 2>/dev/null || true)
if echo "$WT_GUARD_OUT" | grep -q '"status":"fail"' && echo "$WT_GUARD_OUT" | grep -q 'unsafe'; then
    assert_condition 0 "scan-guardrails.sh --working-tree catches unstaged inline unsafe and Rust 2024 #[unsafe(...)]" "scan-guardrails.sh --working-tree missed unstaged unsafe Rust constructs"
else
    assert_condition 1 "scan-guardrails.sh --working-tree catches unstaged inline unsafe and Rust 2024 #[unsafe(...)]" "scan-guardrails.sh --working-tree missed unstaged unsafe Rust constructs"
fi
rm -rf "$TEMP_RUST_DIR"

TEMP_TRACE=$(mktemp 2>/dev/null || mktemp -t 'trace')
printf '{"case_id":"EVAL-GOV-001","tool_calls":[{"name":"run_command","arguments":{"CommandLine":"git status"}}]}\n' > "$TEMP_TRACE"
BAD_TRACE_RAW=$(bash "$REPO_ROOT/scripts/run-evals.sh" --case-id EVAL-GOV-001 --transcript "$TEMP_TRACE" --json 2>/dev/null || true)
if echo "$BAD_TRACE_RAW" | grep -Eq '"failed":[[:space:]]*1'; then
    assert_condition 0 "run-evals.sh --transcript deterministically flags prohibited 'git status' on Profile 0" "run-evals.sh --transcript failed to catch prohibited action"
else
    assert_condition 1 "run-evals.sh --transcript deterministically flags prohibited 'git status' on Profile 0" "run-evals.sh --transcript failed to catch prohibited action"
fi
rm -f "$TEMP_TRACE"

# 45. Validate code outline AST inspector scripts and next-gen LLM efficiency invariants
echo -e "\n\033[33m45. Validating code outline AST inspector scripts and next-gen LLM efficiency invariants...\033[0m"
if [ -f "$REPO_ROOT/scripts/get-code-outline.ps1" ] && [ -f "$REPO_ROOT/scripts/get-code-outline.sh" ]; then
    assert_condition 0 "get-code-outline scripts exist (.ps1 and .sh)" "get-code-outline scripts missing"
else
    assert_condition 1 "get-code-outline scripts exist (.ps1 and .sh)" "get-code-outline scripts missing"
fi

if bash "$REPO_ROOT/scripts/get-code-outline.sh" "$REPO_ROOT" --json 2>/dev/null | grep -q '"status":"pass"'; then
    assert_condition 0 "get-code-outline.sh executes cleanly and outputs valid JSON" "get-code-outline.sh execution failed"
else
    assert_condition 1 "get-code-outline.sh executes cleanly and outputs valid JSON" "get-code-outline.sh execution failed"
fi

if grep -q 'Surgical Edit First' "$REPO_ROOT/AGENTS.md" && grep -q 'Two-Zone Prompt Cache Architecture' "$REPO_ROOT/AGENTS.md"; then
    assert_condition 0 "AGENTS.md enforces Surgical Edit First and Two-Zone Prompt Cache Architecture" "AGENTS.md missing efficiency invariants"
else
    assert_condition 1 "AGENTS.md enforces Surgical Edit First and Two-Zone Prompt Cache Architecture" "AGENTS.md missing efficiency invariants"
fi

if grep -q 'Thinking Budget Clamping' "$REPO_ROOT/skills/ask-control/SKILL.md"; then
    assert_condition 0 "ask-control enforces Thinking Budget Clamping" "ask-control missing Thinking Budget Clamping"
else
    assert_condition 1 "ask-control enforces Thinking Budget Clamping" "ask-control missing Thinking Budget Clamping"
fi

if grep -q 'thinking_budget_guardrail' "$REPO_ROOT/rules/model-tiers.json" && grep -q 'split_phase_profile_b' "$REPO_ROOT/rules/model-tiers.json"; then
    assert_condition 0 "model-tiers.json documents thinking budget guardrail and split-phase execution" "model-tiers.json missing efficiency guardrails"
else
    assert_condition 1 "model-tiers.json documents thinking budget guardrail and split-phase execution" "model-tiers.json missing efficiency guardrails"
fi

# 46. Validate deferred formatting, prepare-commit scripts, and AGY 24KB rule cap
echo -e "\n\033[33m46. Validating deferred formatting, prepare-commit scripts, and AGY 24KB rule cap...\033[0m"
if [ -f "$REPO_ROOT/scripts/prepare-commit.ps1" ] && [ -f "$REPO_ROOT/scripts/prepare-commit.sh" ]; then
    assert_condition 0 "prepare-commit scripts exist (.ps1 and .sh)" "prepare-commit scripts missing"

    TEMP_PREP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'prep')
    printf 'plugins { id("com.diffplug.spotless") }\n' > "$TEMP_PREP_DIR/build.gradle.kts"
    GRADLE_STACK=$(bash "$REPO_ROOT/scripts/detect-tech-stack.sh" "$TEMP_PREP_DIR" --json 2>/dev/null || true)
    if echo "$GRADLE_STACK" | grep -q '"stack":"gradle"' && echo "$GRADLE_STACK" | grep -q -- '-x spotlessCheck' && echo "$GRADLE_STACK" | grep -q '"lint_cmd":""' && echo "$GRADLE_STACK" | grep -q 'spotlessCheck'; then
        assert_condition 0 "detect-tech-stack.sh excludes spotlessCheck from Gradle build/test and defers it exclusively to format_check_cmd" "detect-tech-stack.sh failed to isolate Gradle spotlessCheck"
    else
        assert_condition 1 "detect-tech-stack.sh excludes spotlessCheck from Gradle build/test and defers it exclusively to format_check_cmd" "detect-tech-stack.sh failed to isolate Gradle spotlessCheck"
    fi
    rm -f "$TEMP_PREP_DIR/build.gradle.kts"

    git -C "$TEMP_PREP_DIR" init -q 2>/dev/null || true
    git -C "$TEMP_PREP_DIR" config user.email "test@example.com"
    git -C "$TEMP_PREP_DIR" config user.name "Test User"
    git -C "$TEMP_PREP_DIR" config core.autocrlf false

    if [ "$EXPECTED_OS_EOL" = "CRLF" ]; then
        NAT_NL=$'\r\n'; ALT_NL=$'\n'; OVR_ATTR="eol=lf"; OVR_EC="lf"
    else
        NAT_NL=$'\n'; ALT_NL=$'\r\n'; OVR_ATTR="eol=crlf"; OVR_EC="crlf"
    fi

    printf '# Title%sLine 2%s' "$NAT_NL" "$NAT_NL" > "$TEMP_PREP_DIR/notes.md"
    printf 'alpha%sbeta%s' "$ALT_NL" "$ALT_NL" > "$TEMP_PREP_DIR/legacy.txt"
    git -C "$TEMP_PREP_DIR" add notes.md legacy.txt
    git -C "$TEMP_PREP_DIR" commit -q -m "chore: init"

    # 46a. Whitespace-only (EOL) diff -> needs_decision without draft message, then --revert-whitespace-only -> clean
    printf '# Title%sLine 2%s' "$ALT_NL" "$ALT_NL" > "$TEMP_PREP_DIR/notes.md"
    WS_DETECT=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --json 2>/dev/null || true)
    if echo "$WS_DETECT" | grep -q '"status":"needs_decision"' && echo "$WS_DETECT" | grep -q '"suggested_commit_message":""'; then
        assert_condition 0 "prepare-commit.sh detects whitespace/EOL-only diff and withholds commit message" "prepare-commit.sh failed whitespace detection or leaked draft message"
    else
        assert_condition 1 "prepare-commit.sh detects whitespace/EOL-only diff and withholds commit message" "prepare-commit.sh failed whitespace detection or leaked draft message"
    fi

    WS_REVERT=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --revert-whitespace-only --json 2>/dev/null || true)
    if echo "$WS_REVERT" | grep -q '"status":"clean"' && echo "$WS_REVERT" | grep -q '"reverted_whitespace_count":1'; then
        assert_condition 0 "prepare-commit.sh --revert-whitespace-only reverts noise diffs to HEAD" "prepare-commit.sh failed to revert whitespace-only diff"
    else
        assert_condition 1 "prepare-commit.sh --revert-whitespace-only reverts noise diffs to HEAD" "prepare-commit.sh failed to revert whitespace-only diff"
    fi

    # 46b. Real edit + non-native EOL on native file -> normalized under --direct
    printf '# Title%sLine 2%sLine 3%s' "$ALT_NL" "$ALT_NL" "$ALT_NL" > "$TEMP_PREP_DIR/notes.md"
    DIRECT_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --direct --json 2>/dev/null || true)
    if echo "$DIRECT_RES" | grep -q '"status":"ready"' && echo "$DIRECT_RES" | grep -q '"next_step":"execute_commit"' && echo "$DIRECT_RES" | grep -q '"normalized_count":1'; then
        assert_condition 0 "prepare-commit.sh --direct normalizes unambiguous non-native EOL and signals execute_commit" "prepare-commit.sh --direct failed on unambiguous edit: $DIRECT_RES"
    else
        assert_condition 1 "prepare-commit.sh --direct normalizes unambiguous non-native EOL and signals execute_commit" "prepare-commit.sh --direct failed on unambiguous edit: $DIRECT_RES"
    fi

    # 46c. Ambiguous legacy non-native EOL file -> pauses under --direct until --force-normalize
    printf 'alpha%sbeta%sgamma%s' "$ALT_NL" "$ALT_NL" "$ALT_NL" > "$TEMP_PREP_DIR/legacy.txt"
    AMBIG_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --direct --json 2>/dev/null || true)
    if echo "$AMBIG_RES" | grep -q '"status":"needs_decision"' && echo "$AMBIG_RES" | grep -q '"ambiguous_count":1'; then
        assert_condition 0 "prepare-commit.sh pauses for user decision on ambiguous legacy EOL file" "prepare-commit.sh normalized ambiguous file without permission"
    else
        assert_condition 1 "prepare-commit.sh pauses for user decision on ambiguous legacy EOL file" "prepare-commit.sh normalized ambiguous file without permission"
    fi

    FORCE_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --direct --force-normalize --json 2>/dev/null || true)
    if echo "$FORCE_RES" | grep -q '"status":"ready"' && echo "$FORCE_RES" | grep -q '"normalized_count":1'; then
        assert_condition 0 "prepare-commit.sh --force-normalize normalizes legacy EOL after confirmation" "prepare-commit.sh --force-normalize failed: $FORCE_RES"
    else
        assert_condition 1 "prepare-commit.sh --force-normalize normalizes legacy EOL after confirmation" "prepare-commit.sh --force-normalize failed: $FORCE_RES"
    fi

    # 46d. Governance/tooling mixed commit heuristic -> chore(tooling) without blank leaf
    git -C "$TEMP_PREP_DIR" add notes.md legacy.txt
    git -C "$TEMP_PREP_DIR" commit -q -m "chore: sync"
    mkdir -p "$TEMP_PREP_DIR/scripts"
    printf '* text=auto%s' "$NAT_NL" > "$TEMP_PREP_DIR/.gitattributes"
    printf '# Agents%s' "$NAT_NL" > "$TEMP_PREP_DIR/AGENTS.md"
    printf 'echo ok%s' "$NAT_NL" > "$TEMP_PREP_DIR/scripts/test-skills.sh"
    TOOLING_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --json 2>/dev/null || true)
    if echo "$TOOLING_RES" | grep -q '"status":"ready"' && echo "$TOOLING_RES" | grep -q '"suggested_commit_message":"chore(tooling): update \.gitattributes and 2 additional file(s)"'; then
        assert_condition 0 "prepare-commit.sh classifies dotfile+docs+scripts as chore(tooling) without blank leaf" "prepare-commit.sh misclassified governance/tooling commit"
    else
        assert_condition 1 "prepare-commit.sh classifies dotfile+docs+scripts as chore(tooling) without blank leaf" "prepare-commit.sh misclassified governance/tooling commit: $TOOLING_RES"
    fi

    # 46e. Project config overrides (.gitattributes and .editorconfig) + command -v file fallback
    if grep -q 'OS-Native Line Endings Invariant' "$REPO_ROOT/AGENTS.md" && grep -q 'command -v file' "$REPO_ROOT/scripts/prepare-commit.sh"; then
        assert_condition 0 "AGENTS.md enforces OS-Native Line Endings Invariant and prepare-commit.sh includes file fallback" "Missing invariant or file fallback"
    else
        assert_condition 1 "AGENTS.md enforces OS-Native Line Endings Invariant and prepare-commit.sh includes file fallback" "Missing invariant or file fallback"
    fi

    git -C "$TEMP_PREP_DIR" add .gitattributes AGENTS.md scripts/test-skills.sh
    git -C "$TEMP_PREP_DIR" commit -q -m "chore: baseline"
    printf '* text=auto%s*.bat text %s%s' "$NAT_NL" "$OVR_ATTR" "$NAT_NL" > "$TEMP_PREP_DIR/.gitattributes"
    printf 'root = true%s[*.ps1]%send_of_line = %s%s' "$NAT_NL" "$NAT_NL" "$OVR_EC" "$NAT_NL" > "$TEMP_PREP_DIR/.editorconfig"
    printf '@echo off%secho ok%s' "$NAT_NL" "$NAT_NL" > "$TEMP_PREP_DIR/scripts/build.bat"
    printf 'Write-Host ok%s' "$NAT_NL" > "$TEMP_PREP_DIR/scripts/check.ps1"
    printf 'hello%sworld%s' "$ALT_NL" "$ALT_NL" > "$TEMP_PREP_DIR/default.txt"
    OV_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_PREP_DIR" --direct --json 2>/dev/null || true)
    has_cr() { [ "$(LC_ALL=C tr -cd '\r' < "$1" 2>/dev/null | wc -c)" -gt 0 ]; }
    if [ "$EXPECTED_OS_EOL" = "CRLF" ]; then
        OV_OK=$(! has_cr "$TEMP_PREP_DIR/scripts/build.bat" && ! has_cr "$TEMP_PREP_DIR/scripts/check.ps1" && has_cr "$TEMP_PREP_DIR/default.txt" && echo 1 || echo 0)
    else
        OV_OK=$(has_cr "$TEMP_PREP_DIR/scripts/build.bat" && has_cr "$TEMP_PREP_DIR/scripts/check.ps1" && ! has_cr "$TEMP_PREP_DIR/default.txt" && echo 1 || echo 0)
    fi
    if echo "$OV_RES" | grep -q '"status":"ready"' && [ "$OV_OK" -eq 1 ]; then
        assert_condition 0 "prepare-commit.sh and scan-guardrails.sh honor .gitattributes/.editorconfig EOL overrides while defaulting others to OS-native ${EXPECTED_OS_EOL}" "Project EOL override or OS-native default failed: $OV_RES"
    else
        assert_condition 1 "prepare-commit.sh and scan-guardrails.sh honor .gitattributes/.editorconfig EOL overrides while defaulting others to OS-native ${EXPECTED_OS_EOL}" "Project EOL override or OS-native default failed: $OV_RES"
    fi

    rm -rf "$TEMP_PREP_DIR"
else
    assert_condition 1 "prepare-commit scripts exist (.ps1 and .sh)" "prepare-commit scripts missing"
fi

AGENTS_BYTES=$(wc -c < "$REPO_ROOT/AGENTS.md")
SUBAGENTS_BYTES=$(wc -c < "$REPO_ROOT/rules/subagents.md")
if [ "$AGENTS_BYTES" -le 24000 ] && [ "$SUBAGENTS_BYTES" -le 24000 ]; then
    assert_condition 0 "AGENTS.md (${AGENTS_BYTES} B) and rules/subagents.md (${SUBAGENTS_BYTES} B) stay within AGY 24KB rule limit" "Rule file exceeds 24000 bytes"
else
    assert_condition 1 "AGENTS.md (${AGENTS_BYTES} B) and rules/subagents.md (${SUBAGENTS_BYTES} B) stay within AGY 24KB rule limit" "Rule file exceeds 24000 bytes"
fi

AUDITOR_SKILL_FILE="$REPO_ROOT/skills/ask-skill-auditor/SKILL.md"
if [ -f "$AUDITOR_SKILL_FILE" ] && grep -q 'Rules A1' "$AUDITOR_SKILL_FILE" && grep -q 'CONVERGED & SATURATED' "$AUDITOR_SKILL_FILE" && grep -q 'Monotonic Audit Ratchet' "$AUDITOR_SKILL_FILE"; then
    assert_condition 0 "ask-skill-auditor enforces deterministic A1-A10 rules, anti-oscillation saturation gate, and monotonic self-audit" "ask-skill-auditor missing mandatory audit sections"
else
    assert_condition 1 "ask-skill-auditor enforces deterministic A1-A10 rules, anti-oscillation saturation gate, and monotonic self-audit" "ask-skill-auditor missing mandatory audit sections"
fi

# 47. Validate bash script parity, directory segment excludes, MIME/JSON checks, and eval coverage
echo -e "\n\033[33m47. Validating bash script parity, excludes, MIME/JSON checks, and eval coverage...\033[0m"
CONTRACT_SKILL_FILE="$REPO_ROOT/skills/ask-contract-specialist/SKILL.md"
if grep -q -- '-List\b' "$CONTRACT_SKILL_FILE" && grep -q -- '--list\b' "$CONTRACT_SKILL_FILE" && ! grep -qE 'ListAll|--list-all' "$CONTRACT_SKILL_FILE"; then
    assert_condition 0 "ask-contract-specialist uses valid -List/--list flags" "ask-contract-specialist contains invalid -ListAll/--list-all flag"
else
    assert_condition 1 "ask-contract-specialist uses valid -List/--list flags" "ask-contract-specialist contains invalid -ListAll/--list-all flag"
fi

if grep -q 'clean_release_tagging' "$REPO_ROOT/scripts/run-evals.sh" && grep -q 'targeted_test_first' "$REPO_ROOT/scripts/run-evals.sh"; then
    assert_condition 0 "run-evals.sh actively asserts clean_release_tagging and targeted_test_first" "run-evals.sh missing active invariant checks"
else
    assert_condition 1 "run-evals.sh actively asserts clean_release_tagging and targeted_test_first" "run-evals.sh missing active invariant checks"
fi

TEMP_PARITY_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'parity')
mkdir -p "$TEMP_PARITY_DIR/src/object_mapper/domain" "$TEMP_PARITY_DIR/src/App"
printf 'pub fn hello() -> i32 { 1 }\n' > "$TEMP_PARITY_DIR/src/lib.rs"
printf 'use crate::infrastructure::db;\npub fn bad() {}\n' > "$TEMP_PARITY_DIR/src/object_mapper/domain/model.rs"
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$TEMP_PARITY_DIR/src/App/App.csproj"
printf '{"token":"%s%s"}\n' "ghp_" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" > "$TEMP_PARITY_DIR/secret.json"

OUTLINE_SH_JSON=$(bash "$REPO_ROOT/scripts/get-code-outline.sh" --json "$TEMP_PARITY_DIR/src/lib.rs" 2>/dev/null || true)
if echo "$OUTLINE_SH_JSON" | grep -q '"status":"pass"' && echo "$OUTLINE_SH_JSON" | grep -q 'pub fn hello'; then
    assert_condition 0 "get-code-outline.sh --json handles flag-before-path and extracts signatures" "get-code-outline.sh --json failed: $OUTLINE_SH_JSON"
else
    assert_condition 1 "get-code-outline.sh --json handles flag-before-path and extracts signatures" "get-code-outline.sh --json failed: $OUTLINE_SH_JSON"
fi

ARCH_SH_JSON=$(bash "$REPO_ROOT/scripts/lint-clean-architecture.sh" "$TEMP_PARITY_DIR" --json 2>/dev/null || true)
if echo "$ARCH_SH_JSON" | grep -q '"status": "fail"' && echo "$ARCH_SH_JSON" | grep -q '"Type": "LayerBoundaryViolation"'; then
    assert_condition 0 "lint-clean-architecture.sh scans object_mapper/domain with PascalCase JSON parity" "lint-clean-architecture.sh skipped object_mapper dir or mismatched schema: $ARCH_SH_JSON"
else
    assert_condition 1 "lint-clean-architecture.sh scans object_mapper/domain with PascalCase JSON parity" "lint-clean-architecture.sh skipped object_mapper dir or mismatched schema: $ARCH_SH_JSON"
fi

GUARD_SH_JSON=$(bash "$REPO_ROOT/scripts/scan-guardrails.sh" --path "${TEMP_PARITY_DIR}/" --skip-line-endings --json 2>/dev/null || true)
if echo "$GUARD_SH_JSON" | grep -q '"status":"fail"' && echo "$GUARD_SH_JSON" | grep -q '"Rule":"SecretDetection"' && echo "$GUARD_SH_JSON" | grep -q 'secret.json'; then
    assert_condition 0 "scan-guardrails.sh handles trailing slash, .json secrets, and structured JSON parity" "scan-guardrails.sh missed .json secret or schema parity: $GUARD_SH_JSON"
else
    assert_condition 1 "scan-guardrails.sh handles trailing slash, .json secrets, and structured JSON parity" "scan-guardrails.sh missed .json secret or schema parity: $GUARD_SH_JSON"
fi

STACK_DOTNET_SH=$(bash "$REPO_ROOT/scripts/detect-tech-stack.sh" "$TEMP_PARITY_DIR" --json 2>/dev/null || true)
if echo "$STACK_DOTNET_SH" | grep -q '"stack":"dotnet"'; then
    assert_condition 0 "detect-tech-stack.sh discovers nested .csproj up to depth 2" "detect-tech-stack.sh missed nested .csproj: $STACK_DOTNET_SH"
else
    assert_condition 1 "detect-tech-stack.sh discovers nested .csproj up to depth 2" "detect-tech-stack.sh missed nested .csproj: $STACK_DOTNET_SH"
fi

FAIL_SH_JSON=$(bash "$REPO_ROOT/scripts/collect-test-failures.sh" --log-text "FAIL UserMapperTests" --json 2>/dev/null || true)
if echo "$FAIL_SH_JSON" | grep -q '"failed_count": 1' && echo "$FAIL_SH_JSON" | grep -q '"TestName": "UserMapperTests"'; then
    assert_condition 0 "collect-test-failures.sh --log-text extracts failed test diagnostics with PascalCase parity" "collect-test-failures.sh --log-text failed: $FAIL_SH_JSON"
else
    assert_condition 1 "collect-test-failures.sh --log-text extracts failed test diagnostics with PascalCase parity" "collect-test-failures.sh --log-text failed: $FAIL_SH_JSON"
fi

printf '{"eval_cases":[{"id":"EVAL-UNK-001","name":"Unknown","category":"governance","input":"test","expected":{"required_invariants":["nonexistent_invariant_xyz"]}}]}\n' > "$TEMP_PARITY_DIR/eval-unk.json"
UNK_EVAL_SH=$(bash "$REPO_ROOT/scripts/run-evals.sh" --eval-file "$TEMP_PARITY_DIR/eval-unk.json" --json 2>/dev/null || true)
if echo "$UNK_EVAL_SH" | grep -Eq '"failed":[[:space:]]*1'; then
    assert_condition 0 "run-evals.sh rejects unknown/unhandled required_invariants" "run-evals.sh silently passed an unknown required_invariant: $UNK_EVAL_SH"
else
    assert_condition 1 "run-evals.sh rejects unknown/unhandled required_invariants" "run-evals.sh silently passed an unknown required_invariant: $UNK_EVAL_SH"
fi

if grep -q '5 consolidated specialist capability packs' "$REPO_ROOT/README.md" && ! grep -q '4 consolidated specialist capability packs' "$REPO_ROOT/README.md"; then
    assert_condition 0 "README.md accurately lists 5 specialist capability packs" "README.md has stale specialist pack count"
else
    assert_condition 1 "README.md accurately lists 5 specialist capability packs" "README.md has stale specialist pack count"
fi

if grep -q 'safety-snapshot-\*' "$REPO_ROOT/skills/ask-git-troubleshooter/SKILL.md"; then
    assert_condition 0 "ask-git-troubleshooter documents safety-snapshot-* verification" "ask-git-troubleshooter snapshot verification mismatches diagnose-git-state"
else
    assert_condition 1 "ask-git-troubleshooter documents safety-snapshot-* verification" "ask-git-troubleshooter snapshot verification mismatches diagnose-git-state"
fi

rm -rf "$TEMP_PARITY_DIR"

# 48. Validate Clean Architecture word-boundary precision, staged whitespace revert, positional args & doc alignment
echo -e "\n\033[33m48. Validating Clean Architecture precision, staged whitespace revert, positional args & doc alignment...\033[0m"
TEMP_AUDIT_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'audit')
mkdir -p "$TEMP_AUDIT_DIR/domain" "$TEMP_AUDIT_DIR/staged-repo"
printf 'use uuid::Uuid;\nuse serde::Serialize;\npub struct Order { id: Uuid }\n' > "$TEMP_AUDIT_DIR/domain/Entity.rs"
UUID_ARCH_OUT=$(bash "$REPO_ROOT/scripts/lint-clean-architecture.sh" "$TEMP_AUDIT_DIR" --json 2>/dev/null || true)
if echo "$UUID_ARCH_OUT" | grep -q '"status": "pass"' && echo "$UUID_ARCH_OUT" | grep -q '"error_count": 0'; then
    assert_condition 0 "lint-clean-architecture.sh avoids false-positive substring matches on 'uuid' in domain/" "lint-clean-architecture.sh false positive: $UUID_ARCH_OUT"
else
    assert_condition 1 "lint-clean-architecture.sh avoids false-positive substring matches on 'uuid' in domain/" "lint-clean-architecture.sh false positive: $UUID_ARCH_OUT"
fi

git -C "$TEMP_AUDIT_DIR/staged-repo" init -q 2>/dev/null || true
git -C "$TEMP_AUDIT_DIR/staged-repo" config user.email "test@example.com"
git -C "$TEMP_AUDIT_DIR/staged-repo" config user.name "Test User"
git -C "$TEMP_AUDIT_DIR/staged-repo" config core.autocrlf false
if [ "$EXPECTED_OS_EOL" = "CRLF" ]; then
    ST_NAT=$'\r\n'; ST_ALT=$'\n'
else
    ST_NAT=$'\n'; ST_ALT=$'\r\n'
fi
printf '# Notes%sLine 1%s' "$ST_NAT" "$ST_NAT" > "$TEMP_AUDIT_DIR/staged-repo/notes.md"
git -C "$TEMP_AUDIT_DIR/staged-repo" add notes.md
git -C "$TEMP_AUDIT_DIR/staged-repo" commit -q -m "chore: init"
printf '# Notes%sLine 1%s' "$ST_ALT" "$ST_ALT" > "$TEMP_AUDIT_DIR/staged-repo/notes.md"
git -C "$TEMP_AUDIT_DIR/staged-repo" add notes.md
STAGED_REV_RES=$(bash "$REPO_ROOT/scripts/prepare-commit.sh" --repo-root "$TEMP_AUDIT_DIR/staged-repo" --revert-whitespace-only --json 2>/dev/null || true)
POST_STAGED_STATUS=$(git -C "$TEMP_AUDIT_DIR/staged-repo" status --porcelain 2>/dev/null || true)
if echo "$STAGED_REV_RES" | grep -q '"status":"clean"' && [ -z "$POST_STAGED_STATUS" ]; then
    assert_condition 0 "prepare-commit.sh reverts staged whitespace-only diffs cleanly from HEAD" "prepare-commit.sh failed staged revert: $STAGED_REV_RES | $POST_STAGED_STATUS"
else
    assert_condition 1 "prepare-commit.sh reverts staged whitespace-only diffs cleanly from HEAD" "prepare-commit.sh failed staged revert: $STAGED_REV_RES | $POST_STAGED_STATUS"
fi

CI_POS_OUT=$(bash "$REPO_ROOT/scripts/lint-ci-workflows.sh" "$REPO_ROOT" --strict --json 2>/dev/null || true)
if echo "$CI_POS_OUT" | grep -q '"status":"pass"' && echo "$CI_POS_OUT" | grep -q '"workflows_count":1'; then
    assert_condition 0 "lint-ci-workflows.sh accepts positional repo root argument" "lint-ci-workflows.sh positional arg failed: $CI_POS_OUT"
else
    assert_condition 1 "lint-ci-workflows.sh accepts positional repo root argument" "lint-ci-workflows.sh positional arg failed: $CI_POS_OUT"
fi
rm -rf "$TEMP_AUDIT_DIR"

if grep -q 'OS-Native Line Endings Invariant' "$GIT_TROUBLE_FILE" && ! grep -q '\* text=auto eol=lf' "$GIT_TROUBLE_FILE"; then
    assert_condition 0 "ask-git-troubleshooter aligns with OS-Native Line Endings Invariant" "ask-git-troubleshooter contradicts OS-Native Line Endings Invariant"
else
    assert_condition 1 "ask-git-troubleshooter aligns with OS-Native Line Endings Invariant" "ask-git-troubleshooter contradicts OS-Native Line Endings Invariant"
fi

if grep -q '19 Synthetic Scenario Benchmarks' "$REPO_ROOT/ARCHITECTURE.md"; then
    assert_condition 0 "ARCHITECTURE.md benchmark count reflects 19 eval cases" "ARCHITECTURE.md benchmark count is stale"
else
    assert_condition 1 "ARCHITECTURE.md benchmark count reflects 19 eval cases" "ARCHITECTURE.md benchmark count is stale"
fi

# 49. Validate cross-OS spec drift stability, ROADMAP count, and bash parity checks
echo -e "\n\033[33m49. Validating cross-OS spec drift stability, ROADMAP count, and bash parity checks...\033[0m"
DRIFT_SH_OUT=$(bash "$REPO_ROOT/scripts/inspect-feature-specs.sh" --repo-root "$REPO_ROOT" --check-drift --json 2>/dev/null || true)
if echo "$DRIFT_SH_OUT" | grep -q '"status":"synchronized"' && echo "$DRIFT_SH_OUT" | grep -q '"drift_count":0'; then
    assert_condition 0 "inspect-feature-specs.sh --check-drift is cross-OS synchronized (LF-normalized hashes)" "inspect-feature-specs.sh --check-drift reported drift: $DRIFT_SH_OUT"
else
    assert_condition 1 "inspect-feature-specs.sh --check-drift is cross-OS synchronized (LF-normalized hashes)" "inspect-feature-specs.sh --check-drift reported drift: $DRIFT_SH_OUT"
fi

if grep -q '5 On-Demand Specialist Capability Packs' "$REPO_ROOT/docs/ROADMAP.md"; then
    assert_condition 0 "docs/ROADMAP.md accurately lists 5 On-Demand Specialist Capability Packs" "docs/ROADMAP.md has stale specialist count"
else
    assert_condition 1 "docs/ROADMAP.md accurately lists 5 On-Demand Specialist Capability Packs" "docs/ROADMAP.md has stale specialist count"
fi

TEMP_PROTO_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'proto')
printf 'syntax = "proto3";\nmessage Item { string id = 1; string dup = 1; }\n' > "$TEMP_PROTO_DIR/test.proto"
PROTO_SH_OUT=$(bash "$REPO_ROOT/scripts/lint-api-contracts.sh" "$TEMP_PROTO_DIR" --json 2>/dev/null || true)
git -C "$TEMP_PROTO_DIR" init -q 2>/dev/null || true
git -C "$TEMP_PROTO_DIR" config user.email "test@example.com"
git -C "$TEMP_PROTO_DIR" config user.name "Test User"
git -C "$TEMP_PROTO_DIR" add test.proto
git -C "$TEMP_PROTO_DIR" commit -q -m "chore: init"
CLEAN_WT_GUARD=$(bash "$REPO_ROOT/scripts/scan-guardrails.sh" --path "$TEMP_PROTO_DIR" --working-tree --json 2>/dev/null || true)
rm -rf "$TEMP_PROTO_DIR"
if echo "$PROTO_SH_OUT" | grep -q '"status":"fail"' && echo "$PROTO_SH_OUT" | grep -q 'Duplicate field tag'; then
    assert_condition 0 "lint-api-contracts.sh detects duplicate Protobuf field tags with positional repo root" "lint-api-contracts.sh missed duplicate Protobuf tag: $PROTO_SH_OUT"
else
    assert_condition 1 "lint-api-contracts.sh detects duplicate Protobuf field tags with positional repo root" "lint-api-contracts.sh missed duplicate Protobuf tag: $PROTO_SH_OUT"
fi
if echo "$CLEAN_WT_GUARD" | grep -q '"status":"pass"' && echo "$CLEAN_WT_GUARD" | grep -q '"scanned_files_count":0'; then
    assert_condition 0 "scan-guardrails.sh --working-tree handles clean repo with 0 files safely under set -u" "scan-guardrails.sh --working-tree failed on 0 files: $CLEAN_WT_GUARD"
else
    assert_condition 1 "scan-guardrails.sh --working-tree handles clean repo with 0 files safely under set -u" "scan-guardrails.sh --working-tree failed on 0 files: $CLEAN_WT_GUARD"
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
