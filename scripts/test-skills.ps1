<#
.SYNOPSIS
    Automated validator and test suite for agent-skills repository.
.DESCRIPTION
    Validates skill integrity, YAML frontmatter, model tier mappings,
    detects ghost/orphan roles, and asserts LF line endings.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/test-skills.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Running Agent Skills Test & Validation Suite" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$skillsDir = Join-Path $repoRoot "skills"
$rulesDir = Join-Path $repoRoot "rules"
$modelTiersFile = Join-Path $rulesDir "model-tiers.json"

$errors = [System.Collections.Generic.List[string]]::new()
$checksPassed = 0

# Helper function to record test results
function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$SuccessMessage,
        [string]$FailureMessage
    )
    if ($Condition) {
        Write-Host "  [PASS] $SuccessMessage" -ForegroundColor Green
        $script:checksPassed++
    } else {
        Write-Host "  [FAIL] $FailureMessage" -ForegroundColor Red
        $script:errors.Add($FailureMessage)
    }
}

# 1. Validate rules/model-tiers.json exists and is valid JSON
Write-Host "`n1. Validating rules/model-tiers.json..." -ForegroundColor Yellow
$modelTiersExist = Test-Path $modelTiersFile
Assert-Condition $modelTiersExist "model-tiers.json exists" "model-tiers.json not found at $modelTiersFile"

$registeredRoles = @()
if ($modelTiersExist) {
    try {
        $rawJson = Get-Content -Path $modelTiersFile -Raw -Encoding UTF8
        $modelTiersData = $rawJson | ConvertFrom-Json
        Assert-Condition ($null -ne $modelTiersData.execution_modes) "model-tiers.json parsed successfully" "model-tiers.json has invalid structure"

        $tierDispatch = $modelTiersData.execution_modes.multi_agent.tier_dispatch
        $registeredRoles = @(
            $tierDispatch.tier_1_deep_reasoning.roles +
            $tierDispatch.tier_2_analytical.roles +
            $tierDispatch.tier_3_balanced.roles +
            $tierDispatch.tier_4_fast_deterministic.roles
        )
        Assert-Condition ($registeredRoles.Count -eq 23) "All 23 roles are registered in model-tiers.json (Found $($registeredRoles.Count))" "Expected 23 roles in model-tiers.json, but found $($registeredRoles.Count)"

        # Validate Cost-Efficiency Policy
        $hasCostEfficiency = ($null -ne $modelTiersData.cost_efficiency_policy -and $modelTiersData.cost_efficiency_policy.default_to_cost_efficient -eq $true)
        Assert-Condition $hasCostEfficiency "Cost-efficiency policy is defined and enforces cost-efficient defaults" "model-tiers.json lacks cost_efficiency_policy or default_to_cost_efficient is false"

        $hasProModelClassDefault = ($tierDispatch.PSObject.Properties | Where-Object { $_.Value.model_class -eq "pro" }).Count -gt 0
        Assert-Condition (-not $hasProModelClassDefault) "No tier dispatches to high-cost 'pro' model class by default" "Found tier dispatch configured with 'pro' as default model class"

        $hasReasoningCostRule = ($null -ne $modelTiersData.cost_efficiency_policy -and $modelTiersData.cost_efficiency_policy.high_reasoning_requires_cost_advantage -eq $true)
        Assert-Condition $hasReasoningCostRule "Cost-efficiency policy restricts high reasoning levels to when cost-efficient" "model-tiers.json lacks high_reasoning_requires_cost_advantage"
    } catch {
        Assert-Condition $false "model-tiers.json parses as valid JSON" "Failed to parse model-tiers.json: $_"
    }
}

# 2. Validate all 23 skills in skills/ directory
Write-Host "`n2. Validating skills directory structure and frontmatter..." -ForegroundColor Yellow
$skillDirs = Get-ChildItem -Path $skillsDir -Directory | Sort-Object Name
Assert-Condition ($skillDirs.Count -eq 23) "Exactly 23 skill directories found in skills/ (Found $($skillDirs.Count))" "Expected 23 skill directories, but found $($skillDirs.Count)"

foreach ($sDir in $skillDirs) {
    $skillMd = Join-Path $sDir.FullName "SKILL.md"
    $hasSkillMd = Test-Path $skillMd
    Assert-Condition $hasSkillMd "$($sDir.Name)/SKILL.md exists" "Missing SKILL.md in $($sDir.FullName)"

    if ($hasSkillMd) {
        $content = Get-Content -Path $skillMd -Raw -Encoding UTF8
        # Match YAML frontmatter
        if ($content -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n') {
            $fm = $matches[1]
            $hasName = $fm -match 'name:\s*([^\r\n]+)'
            $nameVal = if ($hasName) { $matches[1].Trim() } else { "" }
            $hasDesc = $fm -match 'description:\s*([^\r\n]+)'

            Assert-Condition ($hasName -and $nameVal -eq $sDir.Name) "$($sDir.Name) frontmatter 'name: $($sDir.Name)' is valid" "$($sDir.Name) frontmatter name mismatch: expected '$($sDir.Name)', got '$nameVal'"
            Assert-Condition $hasDesc "$($sDir.Name) frontmatter has non-empty 'description'" "$($sDir.Name) missing description in frontmatter"
        } else {
            Assert-Condition $false "$($sDir.Name) has valid YAML frontmatter" "$($sDir.Name) SKILL.md lacks YAML frontmatter delimiters (---)"
        }
    }
}

# 3. Check for Ghost / Orphan Roles across all markdown files
Write-Host "`n3. Checking for ghost / orphan roles in markdown documentation..." -ForegroundColor Yellow
$ghostRolePatterns = @(
    "TerminalEngineSpecialist",
    "Tiebreaker"
)

$markdownFiles = Get-ChildItem -Path $repoRoot -Recurse -File -Filter "*.md" | Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($pattern in $ghostRolePatterns) {
    $matchesFound = @()
    foreach ($file in $markdownFiles) {
        $lines = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        if ($lines -match "\b$pattern\b") {
            $matchesFound += $file.FullName.Replace($repoRoot + "\", "")
        }
    }
    Assert-Condition ($matchesFound.Count -eq 0) "Zero occurrences of ghost role '$pattern'" "Found ghost role '$pattern' in: $($matchesFound -join ', ')"
}

# 4. Check for CRLF line endings
Write-Host "`n4. Checking line endings (must be LF)..." -ForegroundColor Yellow
$crlfFiles = [System.Collections.Generic.List[string]]::new()
$trackedFiles = Get-ChildItem -Path $repoRoot -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($file in $trackedFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) {
            $crlfFiles.Add($file.FullName.Replace($repoRoot + "\", ""))
            break
        }
    }
}
Assert-Condition ($crlfFiles.Count -eq 0) "All repository files use LF line endings" "CRLF line endings detected in: $($crlfFiles -join ', ')"

# 5. Validate model detection persistent caching functionality
Write-Host "`n5. Testing detect-models.ps1 24h caching..." -ForegroundColor Yellow
$tempCache = [System.IO.Path]::GetTempFileName()
try {
    # 5.1 Fresh probe test
    $probe1Raw = pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache -Force
    $probe1Obj = $probe1Raw | ConvertFrom-Json
    Assert-Condition ($probe1Obj.cached -eq $false) "Fresh probe returns 'cached: false'" "Expected 'cached: false' on fresh probe"
    Assert-Condition (Test-Path $tempCache) "Cache file was persisted to disk" "Cache file was not created"

    # 5.2 Cached retrieval test
    $probe2Raw = pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache
    $probe2Obj = $probe2Raw | ConvertFrom-Json
    Assert-Condition ($probe2Obj.cached -eq $true) "Second call returns 'cached: true'" "Expected 'cached: true' on second call"
    Assert-Condition ($probe2Obj.platform -eq $probe1Obj.platform) "Cached platform matches original probe" "Platform mismatch in cache"

    # 5.3 Force refresh test
    $probe3Raw = pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache -Force
    $probe3Obj = $probe3Raw | ConvertFrom-Json
    Assert-Condition ($probe3Obj.cached -eq $false) "Call with -Force bypasses cache and returns 'cached: false'" "Expected 'cached: false' with -Force"
} finally {
    if (Test-Path $tempCache) {
        Remove-Item -Path $tempCache -Force -ErrorAction SilentlyContinue
    }
}

# 6. Validate relative markdown links across all .md files
Write-Host "`n6. Validating markdown relative links..." -ForegroundColor Yellow
$brokenLinks = [System.Collections.Generic.List[string]]::new()
$allMdFiles = Get-ChildItem -Path $repoRoot -Recurse -File -Filter "*.md" | Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($file in $allMdFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $linkMatches = [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)')
    foreach ($m in $linkMatches) {
        $link = $m.Groups[2].Value
        if ($link -match '^(http|https|mailto|#|file:)') { continue }
        $linkPath = $link.Split('#')[0]
        if ([string]::IsNullOrWhiteSpace($linkPath)) { continue }
        try {
            $resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($file.DirectoryName, $linkPath))
            if (-not (Test-Path $resolved)) {
                $brokenLinks.Add("$($file.FullName.Replace($repoRoot + '\', '')) -> $link")
            }
        } catch {
            $brokenLinks.Add("$($file.FullName.Replace($repoRoot + '\', '')) -> $link (Invalid path format)")
        }
    }
}
Assert-Condition ($brokenLinks.Count -eq 0) "All relative markdown links resolve successfully" "Broken markdown links found: $($brokenLinks -join ', ')"

# 7. Validate PowerShell command hygiene in markdown files (must include -NoProfile)
Write-Host "`n7. Checking PowerShell command hygiene (must use -NoProfile)..." -ForegroundColor Yellow
$missingNoProfile = [System.Collections.Generic.List[string]]::new()
foreach ($file in $allMdFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $lines = $content -split '\r?\n'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Match actual powershell command invocation (command line or backticked command) but ignore prose mentions
        if (($line -match '^\s*powershell(\.exe)?\s+' -or $line -match '`powershell(\.exe)?\s+') -and $line -notmatch '-NoProfile') {
            $missingNoProfile.Add("$($file.FullName.Replace($repoRoot + '\', '')):$($i+1)")
        }
    }
}
Assert-Condition ($missingNoProfile.Count -eq 0) "All powershell command invocations include -NoProfile" "powershell commands missing -NoProfile in: $($missingNoProfile -join ', ')"

# 8. Validate get-arch-diff submodule exclusions (_agents and .agents)
Write-Host "`n8. Validating get-arch-diff submodule exclusions..." -ForegroundColor Yellow
$archDiffPs1 = Join-Path $repoRoot "skills\ask-architecture-sync\scripts\get-arch-diff.ps1"
$archDiffSh = Join-Path $repoRoot "skills\ask-architecture-sync\scripts\get-arch-diff.sh"

$hasPs1Exclusion = $false
if (Test-Path $archDiffPs1) {
    $ps1Content = Get-Content -Path $archDiffPs1 -Raw -Encoding UTF8
    $hasPs1Exclusion = ($ps1Content -match '_agents' -and $ps1Content -match '\.agents')
    # Functional regex test
    $ps1ExclusionMatches = ($ps1Content -match '\(\^\|\[\\\\\/\]\)_agents\(\[\\\\\/\]\|\$\)' -and $ps1Content -match '\(\^\|\[\\\\\/\]\)\\\.agents\(\[\\\\\/\]\|\$\)')
    Assert-Condition $ps1ExclusionMatches "get-arch-diff.ps1 regex correctly matches and excludes _agents and .agents paths" "get-arch-diff.ps1 regex flawed"
}
Assert-Condition $hasPs1Exclusion "get-arch-diff.ps1 excludes _agents and .agents submodules" "get-arch-diff.ps1 missing _agents or .agents exclusion"

$hasShExclusion = $false
if (Test-Path $archDiffSh) {
    $shContent = Get-Content -Path $archDiffSh -Raw -Encoding UTF8
    $hasShExclusion = ($shContent -match '_agents' -and $shContent -match '\.agents')
    # Functional regex test
    $shExclusionMatches = ($shContent -match '\(\^\|\/\)_agents\(\/\|\$\)' -and $shContent -match '\(\^\|\/\)\\\.agents\(\/\|\$\)')
    Assert-Condition $shExclusionMatches "get-arch-diff.sh regex correctly matches and excludes _agents and .agents paths" "get-arch-diff.sh regex flawed"
}
Assert-Condition $hasShExclusion "get-arch-diff.sh excludes _agents and .agents submodules" "get-arch-diff.sh missing _agents or .agents exclusion"

# 9. Validate model tier references in all 23 skills
Write-Host "`n9. Validating model tier references in all 23 skills..." -ForegroundColor Yellow
$missingTierRef = [System.Collections.Generic.List[string]]::new()
foreach ($sDir in $skillDirs) {
    $skillMd = Join-Path $sDir.FullName "SKILL.md"
    if (Test-Path $skillMd) {
        $content = Get-Content -Path $skillMd -Raw -Encoding UTF8
        if ($content -notmatch 'rules/model-tiers\.json') {
            $missingTierRef.Add($sDir.Name)
        }
    }
}
Assert-Condition ($missingTierRef.Count -eq 0) "All 23 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json reference: $($missingTierRef -join ', ')"

# 10. Validate Tooling & Path Compatibility and host project orientation in all 23 skills
Write-Host "`n10. Validating Tooling & Path Compatibility and host project orientation..." -ForegroundColor Yellow
$missingPathCompat = [System.Collections.Generic.List[string]]::new()
foreach ($sDir in $skillDirs) {
    $skillMd = Join-Path $sDir.FullName "SKILL.md"
    if (Test-Path $skillMd) {
        $content = Get-Content -Path $skillMd -Raw -Encoding UTF8
        $hasCompatHeader = ($content -match 'Tooling & Path Compatibility')
        $hasHostRef = ($content -match 'host project' -or $content -match 'host repository')
        if (-not ($hasCompatHeader -and $hasHostRef)) {
            $missingPathCompat.Add("$($sDir.Name) (Header: $hasCompatHeader, HostRef: $hasHostRef)")
        }
    }
}
Assert-Condition ($missingPathCompat.Count -eq 0) "All 23 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation: $($missingPathCompat -join ', ')"

# 11. Validate Submodule Asset Resolution in all 23 skills
Write-Host "`n11. Validating Submodule Asset Resolution in all 23 skills..." -ForegroundColor Yellow
$missingAssetRes = [System.Collections.Generic.List[string]]::new()
foreach ($sDir in $skillDirs) {
    $skillMd = Join-Path $sDir.FullName "SKILL.md"
    if (Test-Path $skillMd) {
        $content = Get-Content -Path $skillMd -Raw -Encoding UTF8
        if ($content -notmatch 'Submodule Asset Resolution') {
            $missingAssetRes.Add($sDir.Name)
        }
    }
}
Assert-Condition ($missingAssetRes.Count -eq 0) "All 23 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution: $($missingAssetRes -join ', ')"

# 12. Validate deterministic script lookups in ask-architecture-sync (No recursive disk scans)
Write-Host "`n12. Validating deterministic script lookups in ask-architecture-sync..." -ForegroundColor Yellow
$archSyncSkill = Join-Path $skillsDir "ask-architecture-sync\SKILL.md"
$archSyncContent = Get-Content -Path $archSyncSkill -Raw -Encoding UTF8
$hasRecursivePs1 = ($archSyncContent -match 'Get-ChildItem.*-Recurse')
$hasRecursiveSh = ($archSyncContent -match 'find\s+\.\s+-name')
Assert-Condition (-not $hasRecursivePs1) "ask-architecture-sync does not use recursive Get-ChildItem scans" "ask-architecture-sync still uses recursive Get-ChildItem"
Assert-Condition (-not $hasRecursiveSh) "ask-architecture-sync does not use recursive find scans" "ask-architecture-sync still uses recursive find"

# 13. Validate safe Rust requirement (no unsafe) in governance & skills
Write-Host "`n13. Validating safe Rust requirement (no unsafe) across governance and skills..." -ForegroundColor Yellow
$rustAuditFiles = @(
    (Join-Path $repoRoot "AGENTS.md"),
    (Join-Path $repoRoot "rules\subagents.md"),
    (Join-Path $skillsDir "ask-architect\SKILL.md"),
    (Join-Path $skillsDir "ask-developer\SKILL.md"),
    (Join-Path $skillsDir "ask-security-auditor\SKILL.md"),
    (Join-Path $skillsDir "ask-verification\SKILL.md")
)
$missingSafeRust = [System.Collections.Generic.List[string]]::new()
foreach ($f in $rustAuditFiles) {
    if (Test-Path $f) {
        $txt = Get-Content -Path $f -Raw -Encoding UTF8
        if ($txt -notmatch 'Rust.*unsafe') {
            $missingSafeRust.Add((Split-Path -Leaf $f))
        }
    }
}
Assert-Condition ($missingSafeRust.Count -eq 0) "All key governance and skills files enforce safe Rust (no unsafe)" "Missing safe Rust rule in: $($missingSafeRust -join ', ')"

# 14. Validate GitTroubleshooter backup branch safety snapshot resolution
Write-Host "`n14. Validating GitTroubleshooter backup branch safety snapshot resolution..." -ForegroundColor Yellow
$gitTroubleSkill = Join-Path $skillsDir "ask-git-troubleshooter\SKILL.md"
$gitTroubleContent = Get-Content -Path $gitTroubleSkill -Raw -Encoding UTF8
$hasBranchDef = ($gitTroubleContent -match '\$branch\s*=\s*\(git branch --show-current\)')
Assert-Condition $hasBranchDef "GitTroubleshooter properly resolves `$branch before creating safety snapshot" "GitTroubleshooter uses undefined `$branch in safety snapshot"

# 15. Validate CommitManager submodule isolation guardrail
Write-Host "`n15. Validating CommitManager submodule isolation guardrail..." -ForegroundColor Yellow
$commitMgrSkill = Join-Path $skillsDir "ask-commit-manager\SKILL.md"
$commitMgrContent = Get-Content -Path $commitMgrSkill -Raw -Encoding UTF8
$hasSubIsolation = ($commitMgrContent -match 'Submodule Isolation Guardrail')
Assert-Condition $hasSubIsolation "CommitManager enforces Submodule Isolation Guardrail" "CommitManager missing Submodule Isolation Guardrail"

# 16. Validate get-arch-diff git config host repository scoping (-C flag)
Write-Host "`n16. Validating get-arch-diff git config host repository scoping..." -ForegroundColor Yellow
$archDiffPs1Content = Get-Content -Path (Join-Path $skillsDir "ask-architecture-sync\scripts\get-arch-diff.ps1") -Raw -Encoding UTF8
$hasPs1ConfigScope = ($archDiffPs1Content -match 'git\s+-C\s+\$repoRoot\s+config\s+--local')
Assert-Condition $hasPs1ConfigScope "get-arch-diff.ps1 scopes git config calls to host repo (-C `$repoRoot)" "get-arch-diff.ps1 missing -C `$repoRoot for git config"

$archDiffShContent = Get-Content -Path (Join-Path $skillsDir "ask-architecture-sync\scripts\get-arch-diff.sh") -Raw -Encoding UTF8
$hasShConfigScope = ($archDiffShContent -match 'git\s+-C\s+"\$REPO_ROOT"\s+config\s+--local')
Assert-Condition $hasShConfigScope "get-arch-diff.sh scopes git config calls to host repo (-C `"\$REPO_ROOT`")" "get-arch-diff.sh missing -C `"\$REPO_ROOT`" for git config"

# 17. Validate ReleaseManager null-safety and submodule dirty status handling
Write-Host "`n17. Validating ReleaseManager null-safety and submodule status handling..." -ForegroundColor Yellow
$releaseMgrSkill = Join-Path $skillsDir "ask-release-manager\SKILL.md"
$releaseMgrContent = Get-Content -Path $releaseMgrSkill -Raw -Encoding UTF8
$hasUnsafeTrim = ($releaseMgrContent -match '\(git branch --show-current\)\.Trim\(\)')
Assert-Condition (-not $hasUnsafeTrim) "ReleaseManager avoids unsafe direct Trim on git branch --show-current" "ReleaseManager has unsafe Trim on empty git branch output"
$hasSubmoduleStatusIgnore = ($releaseMgrContent -match '--ignore-submodules=dirty' -or $releaseMgrContent -match '_agents')
Assert-Condition $hasSubmoduleStatusIgnore "ReleaseManager handles submodule dirty status gracefully" "ReleaseManager does not handle submodule dirty status"

# 18. Validate CommitManager and PRManager host workspace change scoping
Write-Host "`n18. Validating CommitManager and PRManager host workspace change scoping..." -ForegroundColor Yellow
$hasCommitHostScope = ($commitMgrContent -match 'host workspace' -or $commitMgrContent -match 'host project')
Assert-Condition $hasCommitHostScope "CommitManager scopes uncommitted changes to host workspace" "CommitManager missing host workspace scoping"

$prMgrSkill = Join-Path $skillsDir "ask-pr-manager\SKILL.md"
$prMgrContent = Get-Content -Path $prMgrSkill -Raw -Encoding UTF8
$hasPrHostScope = ($prMgrContent -match 'host project changes')
Assert-Condition $hasPrHostScope "PRManager scopes uncommitted changes to host project" "PRManager missing host project scoping"

# 19. Validate Control deterministic detect-models path resolution
Write-Host "`n19. Validating Control deterministic detect-models path resolution..." -ForegroundColor Yellow
$controlSkill = Join-Path $skillsDir "ask-control\SKILL.md"
$controlContent = Get-Content -Path $controlSkill -Raw -Encoding UTF8
$hasDeterministicDetect = ($controlContent -match 'Where-Object \{ Test-Path \$_ \}')
Assert-Condition $hasDeterministicDetect "Control includes deterministic detect-models path resolution" "Control lacks deterministic detect-models path resolution"

# 20. Validate evals dataset and runner integrity
Write-Host "`n20. Validating evals dataset and runner integrity..." -ForegroundColor Yellow
$evalsJsonFile = Join-Path $repoRoot "evals\eval-cases.json"
$evalsExist = Test-Path $evalsJsonFile
Assert-Condition $evalsExist "evals/eval-cases.json exists" "evals/eval-cases.json not found"

if ($evalsExist) {
    try {
        $rawEvals = Get-Content -Path $evalsJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasCases = ($null -ne $rawEvals.eval_cases -and $rawEvals.eval_cases.Count -ge 5)
        Assert-Condition $hasCases "evals/eval-cases.json contains at least 5 benchmark test cases (Found $($rawEvals.eval_cases.Count))" "evals/eval-cases.json has fewer than 5 cases"
    } catch {
        Assert-Condition $false "evals/eval-cases.json parses as valid JSON" "Failed to parse evals/eval-cases.json: $_"
    }
}

$runEvalsPs1 = Join-Path $repoRoot "scripts\run-evals.ps1"
$runEvalsSh = Join-Path $repoRoot "scripts\run-evals.sh"
Assert-Condition (Test-Path $runEvalsPs1) "scripts/run-evals.ps1 exists" "scripts/run-evals.ps1 not found"
Assert-Condition (Test-Path $runEvalsSh) "scripts/run-evals.sh exists" "scripts/run-evals.sh not found"

if (Test-Path $runEvalsPs1) {
    try {
        $evalOutput = pwsh -NoProfile -ExecutionPolicy Bypass -File $runEvalsPs1 -JsonOutput | ConvertFrom-Json
        $evalPass = ($evalOutput.failed -eq 0 -and $evalOutput.passed -ge 5)
        Assert-Condition $evalPass "run-evals.ps1 benchmark passes 100% (Passed: $($evalOutput.passed)/$($evalOutput.total))" "run-evals.ps1 failed benchmarks: $($evalOutput.failed) failures"
    } catch {
        Assert-Condition $false "run-evals.ps1 executes successfully" "Execution error running run-evals.ps1: $_"
    }
}

# 21. Validate telemetry logging and dashboard scripts
Write-Host "`n21. Validating telemetry logging and dashboard scripts..." -ForegroundColor Yellow
$recordTelPs1 = Join-Path $repoRoot "scripts\record-telemetry.ps1"
$recordTelSh = Join-Path $repoRoot "scripts\record-telemetry.sh"
$showTelPs1 = Join-Path $repoRoot "scripts\show-telemetry.ps1"
$showTelSh = Join-Path $repoRoot "scripts\show-telemetry.sh"

Assert-Condition (Test-Path $recordTelPs1) "scripts/record-telemetry.ps1 exists" "scripts/record-telemetry.ps1 not found"
Assert-Condition (Test-Path $recordTelSh) "scripts/record-telemetry.sh exists" "scripts/record-telemetry.sh not found"
Assert-Condition (Test-Path $showTelPs1) "scripts/show-telemetry.ps1 exists" "scripts/show-telemetry.ps1 not found"
Assert-Condition (Test-Path $showTelSh) "scripts/show-telemetry.sh exists" "scripts/show-telemetry.sh not found"

# 22. Validate ask-control telemetry hook and eval integration
Write-Host "`n22. Validating ask-control telemetry hook and eval integration..." -ForegroundColor Yellow
$controlHasTelemetry = ($controlContent -match 'record-telemetry' -and $controlContent -match 'show-telemetry')
Assert-Condition $controlHasTelemetry "Control documents record-telemetry and show-telemetry hooks" "Control missing telemetry hook documentation"
$controlHasEvals = ($controlContent -match 'run-evals')
Assert-Condition $controlHasEvals "Control documents run-evals benchmark integration" "Control missing run-evals documentation"

# 23. Validate tech stack detection and fast-gate scripts
Write-Host "`n23. Validating tech stack detection and fast-gate scripts..." -ForegroundColor Yellow
$detectStackPs1 = Join-Path $repoRoot "scripts\detect-tech-stack.ps1"
$detectStackSh = Join-Path $repoRoot "scripts\detect-tech-stack.sh"
$runFastGatePs1 = Join-Path $repoRoot "scripts\run-fast-gate.ps1"
$runFastGateSh = Join-Path $repoRoot "scripts\run-fast-gate.sh"

Assert-Condition (Test-Path $detectStackPs1) "scripts/detect-tech-stack.ps1 exists" "scripts/detect-tech-stack.ps1 not found"
Assert-Condition (Test-Path $detectStackSh) "scripts/detect-tech-stack.sh exists" "scripts/detect-tech-stack.sh not found"
Assert-Condition (Test-Path $runFastGatePs1) "scripts/run-fast-gate.ps1 exists" "scripts/run-fast-gate.ps1 not found"
Assert-Condition (Test-Path $runFastGateSh) "scripts/run-fast-gate.sh exists" "scripts/run-fast-gate.sh not found"

if (Test-Path $detectStackPs1) {
    try {
        $stackOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $detectStackPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($null -ne $stackOut.stack) "detect-tech-stack.ps1 outputs valid JSON object with stack field" "detect-tech-stack.ps1 invalid output"
    } catch {
        Assert-Condition $false "detect-tech-stack.ps1 executes cleanly" "Execution error: $_"
    }
}

if (Test-Path $runFastGatePs1) {
    try {
        $gateOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $runFastGatePs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($gateOut.status -eq "pass") "run-fast-gate.ps1 passes or gracefully bypasses on non-executable repo" "run-fast-gate.ps1 returned failure"
    } catch {
        Assert-Condition $false "run-fast-gate.ps1 executes cleanly" "Execution error: $_"
    }
}

# 24. Validate guardrails scanner scripts
Write-Host "`n24. Validating guardrails scanner scripts..." -ForegroundColor Yellow
$scanGuardPs1 = Join-Path $repoRoot "scripts\scan-guardrails.ps1"
$scanGuardSh = Join-Path $repoRoot "scripts\scan-guardrails.sh"
Assert-Condition (Test-Path $scanGuardPs1) "scripts/scan-guardrails.ps1 exists" "scripts/scan-guardrails.ps1 not found"
Assert-Condition (Test-Path $scanGuardSh) "scripts/scan-guardrails.sh exists" "scripts/scan-guardrails.sh not found"

if (Test-Path $scanGuardPs1) {
    try {
        $guardOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $scanGuardPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($guardOut.status -eq "pass") "scan-guardrails.ps1 passes on repository files (0 violations)" "scan-guardrails.ps1 detected $($guardOut.violations_count) violations"
    } catch {
        Assert-Condition $false "scan-guardrails.ps1 executes cleanly" "Execution error: $_"
    }
}

# 25. Validate requirements linter scripts
Write-Host "`n25. Validating requirements linter scripts..." -ForegroundColor Yellow
$lintReqPs1 = Join-Path $repoRoot "scripts\lint-requirements.ps1"
$lintReqSh = Join-Path $repoRoot "scripts\lint-requirements.sh"
Assert-Condition (Test-Path $lintReqPs1) "scripts/lint-requirements.ps1 exists" "scripts/lint-requirements.ps1 not found"
Assert-Condition (Test-Path $lintReqSh) "scripts/lint-requirements.sh exists" "scripts/lint-requirements.sh not found"

if (Test-Path $lintReqPs1) {
    try {
        $nextIdOut = (pwsh -NoProfile -ExecutionPolicy Bypass -File $lintReqPs1 -NextId -Scope "AUTH").Trim()
        Assert-Condition ($nextIdOut -match '^REQ-AUTH-[0-9]{3}$') "lint-requirements.ps1 allocates valid scoped next ID ($nextIdOut)" "lint-requirements.ps1 invalid next ID output: $nextIdOut"
    } catch {
        Assert-Condition $false "lint-requirements.ps1 executes cleanly" "Execution error: $_"
    }
}

# 26. Validate SemVer calculator scripts
Write-Host "`n26. Validating SemVer calculator scripts..." -ForegroundColor Yellow
$calcSemverPs1 = Join-Path $repoRoot "scripts\calculate-semver.ps1"
$calcSemverSh = Join-Path $repoRoot "scripts\calculate-semver.sh"
Assert-Condition (Test-Path $calcSemverPs1) "scripts/calculate-semver.ps1 exists" "scripts/calculate-semver.ps1 not found"
Assert-Condition (Test-Path $calcSemverSh) "scripts/calculate-semver.sh exists" "scripts/calculate-semver.sh not found"

if (Test-Path $calcSemverPs1) {
    try {
        $semverOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $calcSemverPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($semverOut.next_version -match '^v[0-9]+\.[0-9]+\.[0-9]+$') "calculate-semver.ps1 calculates valid SemVer tag ($($semverOut.next_version))" "calculate-semver.ps1 invalid output"
    } catch {
        Assert-Condition $false "calculate-semver.ps1 executes cleanly" "Execution error: $_"
    }
}

# 27. Validate i18n key audit scripts
Write-Host "`n27. Validating i18n key audit scripts..." -ForegroundColor Yellow
$auditI18nPs1 = Join-Path $repoRoot "scripts\audit-i18n.ps1"
$auditI18nSh = Join-Path $repoRoot "scripts\audit-i18n.sh"
Assert-Condition (Test-Path $auditI18nPs1) "scripts/audit-i18n.ps1 exists" "scripts/audit-i18n.ps1 not found"
Assert-Condition (Test-Path $auditI18nSh) "scripts/audit-i18n.sh exists" "scripts/audit-i18n.sh not found"

if (Test-Path $auditI18nPs1) {
    try {
        $i18nOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $auditI18nPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($i18nOut.status -eq "pass") "audit-i18n.ps1 passes on repository files" "audit-i18n.ps1 returned failure"
    } catch {
        Assert-Condition $false "audit-i18n.ps1 executes cleanly" "Execution error: $_"
    }
}

# 28. Validate PR summary generator scripts
Write-Host "`n28. Validating PR summary generator scripts..." -ForegroundColor Yellow
$genPrPs1 = Join-Path $repoRoot "scripts\generate-pr-summary.ps1"
$genPrSh = Join-Path $repoRoot "scripts\generate-pr-summary.sh"
Assert-Condition (Test-Path $genPrPs1) "scripts/generate-pr-summary.ps1 exists" "scripts/generate-pr-summary.ps1 not found"
Assert-Condition (Test-Path $genPrSh) "scripts/generate-pr-summary.sh exists" "scripts/generate-pr-summary.sh not found"

if (Test-Path $genPrPs1) {
    try {
        $prOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $genPrPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($null -ne $prOut.suggested_title) "generate-pr-summary.ps1 outputs valid JSON with title" "generate-pr-summary.ps1 invalid output"
    } catch {
        Assert-Condition $false "generate-pr-summary.ps1 executes cleanly" "Execution error: $_"
    }
}

# 29. Validate Git state diagnostic scripts
Write-Host "`n29. Validating Git state diagnostic scripts..." -ForegroundColor Yellow
$diagGitPs1 = Join-Path $repoRoot "scripts\diagnose-git-state.ps1"
$diagGitSh = Join-Path $repoRoot "scripts\diagnose-git-state.sh"
Assert-Condition (Test-Path $diagGitPs1) "scripts/diagnose-git-state.ps1 exists" "scripts/diagnose-git-state.ps1 not found"
Assert-Condition (Test-Path $diagGitSh) "scripts/diagnose-git-state.sh exists" "scripts/diagnose-git-state.sh not found"

if (Test-Path $diagGitPs1) {
    try {
        $diagOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $diagGitPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($null -ne $diagOut.state) "diagnose-git-state.ps1 outputs valid state object ($($diagOut.state))" "diagnose-git-state.ps1 invalid output"
    } catch {
        Assert-Condition $false "diagnose-git-state.ps1 executes cleanly" "Execution error: $_"
    }
}

# 30. Validate documentation link linter scripts
Write-Host "`n30. Validating documentation link linter scripts..." -ForegroundColor Yellow
$lintDocsPs1 = Join-Path $repoRoot "scripts\lint-docs.ps1"
$lintDocsSh = Join-Path $repoRoot "scripts\lint-docs.sh"
Assert-Condition (Test-Path $lintDocsPs1) "scripts/lint-docs.ps1 exists" "scripts/lint-docs.ps1 not found"
Assert-Condition (Test-Path $lintDocsSh) "scripts/lint-docs.sh exists" "scripts/lint-docs.sh not found"

if (Test-Path $lintDocsPs1) {
    try {
        $docsOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $lintDocsPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($docsOut.status -eq "pass") "lint-docs.ps1 passes on repository files (0 broken links)" "lint-docs.ps1 found broken links: $($docsOut.broken_links_count)"
    } catch {
        Assert-Condition $false "lint-docs.ps1 executes cleanly" "Execution error: $_"
    }
}

# 31. Validate Clean Architecture rules and linter scripts
Write-Host "`n31. Validating Clean Architecture rules and linter scripts..." -ForegroundColor Yellow
$cleanArchRulesFile = Join-Path $repoRoot "rules\clean-architecture.json"
$cleanArchPs1 = Join-Path $repoRoot "scripts\lint-clean-architecture.ps1"
$cleanArchSh = Join-Path $repoRoot "scripts\lint-clean-architecture.sh"

Assert-Condition (Test-Path $cleanArchRulesFile) "rules/clean-architecture.json exists" "rules/clean-architecture.json not found"
Assert-Condition (Test-Path $cleanArchPs1) "scripts/lint-clean-architecture.ps1 exists" "scripts/lint-clean-architecture.ps1 not found"
Assert-Condition (Test-Path $cleanArchSh) "scripts/lint-clean-architecture.sh exists" "scripts/lint-clean-architecture.sh not found"

if (Test-Path $cleanArchPs1) {
    try {
        $archOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $cleanArchPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($archOut.status -eq "pass") "lint-clean-architecture.ps1 passes on repository files (0 errors)" "lint-clean-architecture.ps1 detected $($archOut.error_count) errors"
    } catch {
        Assert-Condition $false "lint-clean-architecture.ps1 executes cleanly" "Execution error: $_"
    }
}

# 32. Validate changelog generator scripts
Write-Host "`n32. Validating changelog generator scripts..." -ForegroundColor Yellow
$changelogPs1 = Join-Path $repoRoot "scripts\generate-changelog.ps1"
$changelogSh = Join-Path $repoRoot "scripts\generate-changelog.sh"

Assert-Condition (Test-Path $changelogPs1) "scripts/generate-changelog.ps1 exists" "scripts/generate-changelog.ps1 not found"
Assert-Condition (Test-Path $changelogSh) "scripts/generate-changelog.sh exists" "scripts/generate-changelog.sh not found"

if (Test-Path $changelogPs1) {
    try {
        $clOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $changelogPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($null -ne $clOut.version -and $null -ne $clOut.markdown) "generate-changelog.ps1 outputs valid JSON with markdown ($($clOut.version))" "generate-changelog.ps1 invalid output"
    } catch {
        Assert-Condition $false "generate-changelog.ps1 executes cleanly" "Execution error: $_"
    }
}

# 33. Validate security audit scripts
Write-Host "`n33. Validating security audit scripts..." -ForegroundColor Yellow
$secAuditPs1 = Join-Path $repoRoot "scripts\run-security-audit.ps1"
$secAuditSh = Join-Path $repoRoot "scripts\run-security-audit.sh"

Assert-Condition (Test-Path $secAuditPs1) "scripts/run-security-audit.ps1 exists" "scripts/run-security-audit.ps1 not found"
Assert-Condition (Test-Path $secAuditSh) "scripts/run-security-audit.sh exists" "scripts/run-security-audit.sh not found"

if (Test-Path $secAuditPs1) {
    try {
        $secOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $secAuditPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($secOut.status -eq "pass") "run-security-audit.ps1 executes cleanly and returns pass ($($secOut.status))" "run-security-audit.ps1 reported failure"
    } catch {
        Assert-Condition $false "run-security-audit.ps1 executes cleanly" "Execution error: $_"
    }
}

# 34. Validate test coverage parser scripts
Write-Host "`n34. Validating test coverage parser scripts..." -ForegroundColor Yellow
$coveragePs1 = Join-Path $repoRoot "scripts\check-test-coverage.ps1"
$coverageSh = Join-Path $repoRoot "scripts\check-test-coverage.sh"

Assert-Condition (Test-Path $coveragePs1) "scripts/check-test-coverage.ps1 exists" "scripts/check-test-coverage.ps1 not found"
Assert-Condition (Test-Path $coverageSh) "scripts/check-test-coverage.sh exists" "scripts/check-test-coverage.sh not found"

if (Test-Path $coveragePs1) {
    try {
        $covOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $coveragePs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($covOut.status -eq "pass") "check-test-coverage.ps1 executes cleanly and returns pass ($($covOut.status))" "check-test-coverage.ps1 reported failure"
    } catch {
        Assert-Condition $false "check-test-coverage.ps1 executes cleanly" "Execution error: $_"
    }
}

# 35. Validate database migration linter scripts
Write-Host "`n35. Validating database migration linter scripts..." -ForegroundColor Yellow
$dbMigPs1 = Join-Path $repoRoot "scripts\lint-db-migrations.ps1"
$dbMigSh = Join-Path $repoRoot "scripts\lint-db-migrations.sh"

Assert-Condition (Test-Path $dbMigPs1) "scripts/lint-db-migrations.ps1 exists" "scripts/lint-db-migrations.ps1 not found"
Assert-Condition (Test-Path $dbMigSh) "scripts/lint-db-migrations.sh exists" "scripts/lint-db-migrations.sh not found"

if (Test-Path $dbMigPs1) {
    try {
        $dbOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $dbMigPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($dbOut.status -eq "pass") "lint-db-migrations.ps1 executes cleanly and returns pass ($($dbOut.status))" "lint-db-migrations.ps1 reported failure"
    } catch {
        Assert-Condition $false "lint-db-migrations.ps1 executes cleanly" "Execution error: $_"
    }
}

# 36. Validate API contract linter scripts
Write-Host "`n36. Validating API contract linter scripts..." -ForegroundColor Yellow
$apiContractPs1 = Join-Path $repoRoot "scripts\lint-api-contracts.ps1"
$apiContractSh = Join-Path $repoRoot "scripts\lint-api-contracts.sh"

Assert-Condition (Test-Path $apiContractPs1) "scripts/lint-api-contracts.ps1 exists" "scripts/lint-api-contracts.ps1 not found"
Assert-Condition (Test-Path $apiContractSh) "scripts/lint-api-contracts.sh exists" "scripts/lint-api-contracts.sh not found"

if (Test-Path $apiContractPs1) {
    try {
        $apiOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $apiContractPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($apiOut.status -eq "pass") "lint-api-contracts.ps1 executes cleanly and returns pass ($($apiOut.status))" "lint-api-contracts.ps1 reported failure"
    } catch {
        Assert-Condition $false "lint-api-contracts.ps1 executes cleanly" "Execution error: $_"
    }
}

# 37. Validate orphaned assets detector scripts
Write-Host "`n37. Validating orphaned assets detector scripts..." -ForegroundColor Yellow
$orphansPs1 = Join-Path $repoRoot "scripts\find-orphaned-assets.ps1"
$orphansSh = Join-Path $repoRoot "scripts\find-orphaned-assets.sh"

Assert-Condition (Test-Path $orphansPs1) "scripts/find-orphaned-assets.ps1 exists" "scripts/find-orphaned-assets.ps1 not found"
Assert-Condition (Test-Path $orphansSh) "scripts/find-orphaned-assets.sh exists" "scripts/find-orphaned-assets.sh not found"

if (Test-Path $orphansPs1) {
    try {
        $orphOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $orphansPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($orphOut.status -eq "pass") "find-orphaned-assets.ps1 executes cleanly and returns pass ($($orphOut.status))" "find-orphaned-assets.ps1 reported failure"
    } catch {
        Assert-Condition $false "find-orphaned-assets.ps1 executes cleanly" "Execution error: $_"
    }
}

# 38. Validate CI workflow linter scripts
Write-Host "`n38. Validating CI workflow linter scripts..." -ForegroundColor Yellow
$ciLintPs1 = Join-Path $repoRoot "scripts\lint-ci-workflows.ps1"
$ciLintSh = Join-Path $repoRoot "scripts\lint-ci-workflows.sh"

Assert-Condition (Test-Path $ciLintPs1) "scripts/lint-ci-workflows.ps1 exists" "scripts/lint-ci-workflows.ps1 not found"
Assert-Condition (Test-Path $ciLintSh) "scripts/lint-ci-workflows.sh exists" "scripts/lint-ci-workflows.sh not found"

if (Test-Path $ciLintPs1) {
    try {
        $ciOut = pwsh -NoProfile -ExecutionPolicy Bypass -File $ciLintPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($ciOut.status -eq "pass") "lint-ci-workflows.ps1 executes cleanly and returns pass ($($ciOut.status))" "lint-ci-workflows.ps1 reported failure"
    } catch {
        Assert-Condition $false "lint-ci-workflows.ps1 executes cleanly" "Execution error: $_"
    }
}

# Summary Report
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Test Suite Summary" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Total checks passed: $checksPassed" -ForegroundColor Green
if ($errors.Count -gt 0) {
    Write-Host "Total failures: $($errors.Count)" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "All validation checks passed successfully! (0 errors)" -ForegroundColor Green
    exit 0
}
