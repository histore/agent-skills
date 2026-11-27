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

$currentPs = (Get-Process -Id $PID).Path
$psExe = if ($currentPs -match 'pwsh(\.exe)?$') {
    $currentPs
} elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $cmd = Get-Command pwsh
    if ($cmd.Source -notmatch '[\\/]WindowsApps[\\/]' -and ($cmd.Version -and $cmd.Version.Major -gt 0)) {
        $cmd.Source
    } else {
        $currentPs
    }
} else {
    $currentPs
}

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
        Assert-Condition ($registeredRoles.Count -eq 6) "All 6 roles are registered in model-tiers.json (Found $($registeredRoles.Count))" "Expected 6 roles in model-tiers.json, but found $($registeredRoles.Count)"

        # Validate Cost-Efficiency Policy
        $hasCostEfficiency = ($null -ne $modelTiersData.cost_efficiency_policy -and $modelTiersData.cost_efficiency_policy.default_to_cost_efficient -eq $true)
        Assert-Condition $hasCostEfficiency "Cost-efficiency policy is defined and enforces cost-efficient defaults" "model-tiers.json lacks cost_efficiency_policy or default_to_cost_efficient is false"

        $hasProModelClassDefault = @($tierDispatch.PSObject.Properties | Where-Object { $_.Value.model_class -eq "pro" }).Count -gt 0
        Assert-Condition (-not $hasProModelClassDefault) "No tier dispatches to high-cost 'pro' model class by default" "Found tier dispatch configured with 'pro' as default model class"

        $hasReasoningCostRule = ($null -ne $modelTiersData.cost_efficiency_policy -and $modelTiersData.cost_efficiency_policy.high_reasoning_requires_cost_advantage -eq $true)
        Assert-Condition $hasReasoningCostRule "Cost-efficiency policy restricts high reasoning levels to when cost-efficient" "model-tiers.json lacks high_reasoning_requires_cost_advantage"

        $classesObj = $modelTiersData.cost_efficiency_policy.task_appraisal_and_model_classes.classes
        $copilotPrefs = $modelTiersData.platform_preferences.copilot
        $hasGpt6Family = ($classesObj.eco.models.copilot -match 'gpt-6' -and $classesObj.balanced.models.copilot -match 'gpt-6' -and $classesObj.premium.models.copilot -match 'gpt-6' -and ($copilotPrefs.tier_1 -join ',') -match 'gpt-6' -and ($copilotPrefs.tier_4 -join ',') -match 'gpt-6')
        Assert-Condition $hasGpt6Family "model-tiers.json maps the GPT-6 family across ECO, BALANCED, PREMIUM, and platform tiers" "model-tiers.json missing GPT-6 family coverage"
    } catch {
        Assert-Condition $false "model-tiers.json parses as valid JSON" "Failed to parse model-tiers.json: $_"
    }
}

# 2. Validate all 6 skills in skills/ directory
Write-Host "`n2. Validating skills directory structure and frontmatter..." -ForegroundColor Yellow
$skillDirs = Get-ChildItem -Path $skillsDir -Directory | Sort-Object Name
Assert-Condition ($skillDirs.Count -eq 6) "Exactly 6 skill directories found in skills/ (Found $($skillDirs.Count))" "Expected 6 skill directories, but found $($skillDirs.Count)"

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

# 3. Check for Ghost / Orphan Roles & Dynamic SSOT Cross-File Synchronization across all markdown files
Write-Host "`n3. Checking for ghost / orphan roles and SSOT synchronization in markdown documentation..." -ForegroundColor Yellow
$ghostRolePatterns = @(
    "TerminalEngineSpecialist",
    "Tiebreaker",
    "RequirementEngineer",
    "CodeReviewer",
    "SecurityAuditor",
    "DevOpsEngineer",
    "LocalizationSpecialist",
    "DatabaseSpecialist",
    "ApiContractSpecialist",
    "PerformanceOptimizer",
    "RefactoringSpecialist",
    "DocumentationSpecialist",
    "ArchitectureSync",
    "UIDesigner",
    "CodeExplainer",
    "PRManager"
)

$validSkillNames = @($skillDirs | ForEach-Object { $_.Name }) + @("ask-skills")
$markdownFiles = Get-ChildItem -Path $repoRoot -Recurse -File -Filter "*.md" | Where-Object { $_.FullName -notmatch '\\\.git\\' }
$ghostMatchesFound = [System.Collections.Generic.List[string]]::new()
$orphanSkillRefs = [System.Collections.Generic.List[string]]::new()

foreach ($file in $markdownFiles) {
    $lines = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $relFile = $file.FullName.Replace($repoRoot + "\", "")
    foreach ($pattern in $ghostRolePatterns) {
        if ($lines -match "\b$pattern\b") {
            $ghostMatchesFound.Add("$relFile ($pattern)")
        }
    }
    $askRefs = [regex]::Matches($lines, '\bask-[a-z0-9-]+\b') | ForEach-Object { $_.Value } | Select-Object -Unique
    foreach ($ref in $askRefs) {
        if ($ref -notin $validSkillNames) {
            $orphanSkillRefs.Add("$relFile ($ref)")
        }
    }
}
Assert-Condition ($ghostMatchesFound.Count -eq 0) "Zero occurrences of retired V1 or ghost roles across all markdown files" "Found retired/ghost roles in: $($ghostMatchesFound -join ', ')"
Assert-Condition ($orphanSkillRefs.Count -eq 0) "All 'ask-*' skill references across markdown files match active skills/ directories" "Found orphan skill references in: $($orphanSkillRefs -join ', ')"

# 4. Check for OS-native line endings (CRLF on Windows, LF on Linux/macOS)
$isWindowsOs = ($env:OS -eq 'Windows_NT') -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
$expectedEol = if ($isWindowsOs) { "CRLF" } else { "LF" }
Write-Host "`n4. Checking line endings (must be $expectedEol)..." -ForegroundColor Yellow
$wrongEolFiles = [System.Collections.Generic.List[string]]::new()
$trackedFiles = Get-ChildItem -Path $repoRoot -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($file in $trackedFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($expectedEol -eq "CRLF") {
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if (($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) -or ($bytes[$i] -eq 13 -and (($i + 1) -ge $bytes.Length -or $bytes[$i + 1] -ne 10))) {
                $wrongEolFiles.Add($file.FullName.Replace($repoRoot + "\", ""))
                break
            }
        }
    } else {
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 13) {
                $wrongEolFiles.Add($file.FullName.Replace($repoRoot + "\", ""))
                break
            }
        }
    }
}
Assert-Condition ($wrongEolFiles.Count -eq 0) "All repository files use $expectedEol line endings" "Non-$expectedEol line endings detected in: $($wrongEolFiles -join ', ')"

# 5. Validate model detection persistent caching functionality
Write-Host "`n5. Testing detect-models.ps1 24h caching..." -ForegroundColor Yellow
$tempCache = [System.IO.Path]::GetTempFileName()
try {
    # 5.1 Fresh probe test
    $probe1Raw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache -Force
    $probe1Obj = $probe1Raw | ConvertFrom-Json
    Assert-Condition ($probe1Obj.cached -eq $false) "Fresh probe returns 'cached: false'" "Expected 'cached: false' on fresh probe"
    Assert-Condition (Test-Path $tempCache) "Cache file was persisted to disk" "Cache file was not created"

    # 5.2 Cached retrieval test
    $probe2Raw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache
    $probe2Obj = $probe2Raw | ConvertFrom-Json
    Assert-Condition ($probe2Obj.cached -eq $true) "Second call returns 'cached: true'" "Expected 'cached: true' on second call"
    Assert-Condition ($probe2Obj.platform -eq $probe1Obj.platform) "Cached platform matches original probe" "Platform mismatch in cache"

    # 5.3 Force refresh test
    $probe3Raw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-models.ps1") -CachePath $tempCache -Force
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
    # Strip fenced code blocks and inline code spans before matching links
    $cleanContent = [regex]::Replace($content, '(?s)```.*?```|~~~.*?~~~', '')
    $cleanContent = [regex]::Replace($cleanContent, '`[^`\r\n]+`', '')
    $linkMatches = [regex]::Matches($cleanContent, '\[([^\]]+)\]\(([^)]+)\)')
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
        # Match actual powershell/pwsh command invocation (command line or backticked command) but ignore prose mentions
        if (($line -match '^\s*(pwsh|powershell)(\.exe)?\s+' -or $line -match '`(pwsh|powershell)(\.exe)?\s+') -and $line -notmatch '-NoProfile') {
            $missingNoProfile.Add("$($file.FullName.Replace($repoRoot + '\', '')):$($i+1)")
        }
    }
}
Assert-Condition ($missingNoProfile.Count -eq 0) "All powershell/pwsh command invocations include -NoProfile" "powershell/pwsh commands missing -NoProfile in: $($missingNoProfile -join ', ')"

# 8. Validate get-arch-diff submodule exclusions (_agents and .agents)
Write-Host "`n8. Validating get-arch-diff submodule exclusions..." -ForegroundColor Yellow
$archDiffPs1 = Join-Path $repoRoot "scripts\get-arch-diff.ps1"
$archDiffSh = Join-Path $repoRoot "scripts\get-arch-diff.sh"

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

# 9. Validate model tier references in all 6 skills
Write-Host "`n9. Validating model tier references in all 6 skills..." -ForegroundColor Yellow
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
Assert-Condition ($missingTierRef.Count -eq 0) "All 6 skills reference rules/model-tiers.json" "Skills missing rules/model-tiers.json reference: $($missingTierRef -join ', ')"

# 10. Validate Tooling & Path Compatibility and host project orientation in all 6 skills
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
Assert-Condition ($missingPathCompat.Count -eq 0) "All 6 skills have Tooling & Path Compatibility and host project orientation" "Skills missing path compatibility or host orientation: $($missingPathCompat -join ', ')"

# 11. Validate Submodule Asset Resolution in all 6 skills
Write-Host "`n11. Validating Submodule Asset Resolution in all 6 skills..." -ForegroundColor Yellow
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
Assert-Condition ($missingAssetRes.Count -eq 0) "All 6 skills explain Submodule Asset Resolution" "Skills missing Submodule Asset Resolution: $($missingAssetRes -join ', ')"

# 12. Validate deterministic script lookups in ask-contract-specialist (No recursive disk scans)
Write-Host "`n12. Validating deterministic script lookups in ask-contract-specialist..." -ForegroundColor Yellow
$contractSkill = Join-Path $skillsDir "ask-contract-specialist\SKILL.md"
$contractContent = Get-Content -Path $contractSkill -Raw -Encoding UTF8
$hasRecursivePs1 = ($contractContent -match 'Get-ChildItem.*-Recurse')
$hasRecursiveSh = ($contractContent -match 'find\s+\.\s+-name')
Assert-Condition (-not $hasRecursivePs1) "ask-contract-specialist does not use recursive Get-ChildItem scans" "ask-contract-specialist still uses recursive Get-ChildItem"
Assert-Condition (-not $hasRecursiveSh) "ask-contract-specialist does not use recursive find scans" "ask-contract-specialist still uses recursive find"

# 13. Validate safe Rust requirement (no unsafe) in governance & skills
Write-Host "`n13. Validating safe Rust requirement (no unsafe) across governance and skills..." -ForegroundColor Yellow
$rustAuditFiles = @(
    (Join-Path $repoRoot "AGENTS.md"),
    (Join-Path $repoRoot "rules\subagents.md"),
    (Join-Path $skillsDir "ask-control\SKILL.md"),
    (Join-Path $skillsDir "ask-troubleshooter\SKILL.md"),
    (Join-Path $skillsDir "ask-contract-specialist\SKILL.md"),
    (Join-Path $skillsDir "ask-release-manager\SKILL.md"),
    (Join-Path $skillsDir "ask-skill-auditor\SKILL.md")
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

# 15. Validate Control submodule isolation guardrail
Write-Host "`n15. Validating Control submodule isolation guardrail..." -ForegroundColor Yellow
$controlMgrSkill = Join-Path $skillsDir "ask-control\SKILL.md"
$controlMgrContent = Get-Content -Path $controlMgrSkill -Raw -Encoding UTF8
$hasSubIsolation = ($controlMgrContent -match 'Submodule Isolation Guardrail')
Assert-Condition $hasSubIsolation "Control enforces Submodule Isolation Guardrail" "Control missing Submodule Isolation Guardrail"

# 16. Validate get-arch-diff git config host repository scoping (-C flag)
Write-Host "`n16. Validating get-arch-diff git config host repository scoping..." -ForegroundColor Yellow
$archDiffPs1Content = Get-Content -Path (Join-Path $repoRoot "scripts\get-arch-diff.ps1") -Raw -Encoding UTF8
$hasPs1ConfigScope = ($archDiffPs1Content -match 'git\s+-C\s+\$repoRoot\s+config\s+--local')
Assert-Condition $hasPs1ConfigScope "get-arch-diff.ps1 scopes git config calls to host repo (-C `$repoRoot)" "get-arch-diff.ps1 missing -C `$repoRoot for git config"

$archDiffShContent = Get-Content -Path (Join-Path $repoRoot "scripts\get-arch-diff.sh") -Raw -Encoding UTF8
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

# 18. Validate Control host workspace change scoping
Write-Host "`n18. Validating Control host workspace change scoping..." -ForegroundColor Yellow
$hasCommitHostScope = ($controlMgrContent -match 'host workspace' -or $controlMgrContent -match 'host project')
Assert-Condition $hasCommitHostScope "Control scopes uncommitted changes to host workspace" "Control missing host workspace scoping"

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
        $evalOutput = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runEvalsPs1 -JsonOutput | ConvertFrom-Json
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
        $stackOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $detectStackPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($null -ne $stackOut.stack) "detect-tech-stack.ps1 outputs valid JSON object with stack field" "detect-tech-stack.ps1 invalid output"
    } catch {
        Assert-Condition $false "detect-tech-stack.ps1 executes cleanly" "Execution error: $_"
    }
}

if (Test-Path $runFastGatePs1) {
    try {
        $gateOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runFastGatePs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($gateOut.status -eq "pass") "run-fast-gate.ps1 passes or gracefully bypasses on non-executable repo" "run-fast-gate.ps1 returned failure"
    } catch {
        Assert-Condition $false "run-fast-gate.ps1 executes cleanly" "Execution error: $_"
    }

    # FEAT-GOV-002 AC-1, AC-2, AC-3: AC-* Traceability & Diff-Size-Guardrail
    $fgTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fg_gov002_" + [guid]::NewGuid().ToString("N"))
    $prevEap = $ErrorActionPreference
    try {
        New-Item -ItemType Directory -Path (Join-Path $fgTmp "docs\features") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fgTmp "src") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fgTmp "tests") -Force | Out-Null
        $ErrorActionPreference = 'Continue'
        git -C $fgTmp init -q 2>$null
        git -C $fgTmp config user.email "test@example.com" 2>$null
        git -C $fgTmp config user.name "Test" 2>$null
        Set-Content -Path (Join-Path $fgTmp "src\app.js") -Value "const a = 1;" -Encoding UTF8
        git -C $fgTmp add . 2>$null
        git -C $fgTmp commit -m "init" -q 2>$null
        $ErrorActionPreference = $prevEap

        # Modify executable code (>5 lines) to trigger code gate & diff-size warning
        Set-Content -Path (Join-Path $fgTmp "src\app.js") -Value "const a = 1;`nconst b = 2;`nconst c = 3;`nconst d = 4;`nconst e = 5;`nconst f = 6;" -Encoding UTF8

        # AC-2: PROPOSED spec must bypass AC-* traceability
        Set-Content -Path (Join-Path $fgTmp "docs\features\FEAT-TMP-001.md") -Value "---`nid: FEAT-TMP-001`nstatus: PROPOSED`n---`n- [ ] **AC-1**: test" -Encoding UTF8
        $outBypass = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runFastGatePs1 -ProjectRoot $fgTmp -SkipLint -MaxDiffLines 2 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($outBypass.status -eq "pass") "run-fast-gate.ps1 bypasses AC-* traceability for PROPOSED specs (AC-2)" "Expected pass for PROPOSED spec, got $($outBypass.status)"
        Assert-Condition ($outBypass.warnings.Count -ge 1 -and ($outBypass.warnings -join " ") -match "\[DiffSize\]") "run-fast-gate.ps1 emits [DiffSize] warning without failing (AC-3)" "Expected [DiffSize] warning, got: $($outBypass.warnings -join '; ')"

        # AC-1: IN_PROGRESS spec with uncovered AC-1 must fail Stage-1
        Set-Content -Path (Join-Path $fgTmp "docs\features\FEAT-TMP-001.md") -Value "---`nid: FEAT-TMP-001`nstatus: IN_PROGRESS`n---`n- [ ] **AC-1**: test" -Encoding UTF8
        $outFail = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runFastGatePs1 -ProjectRoot $fgTmp -SkipLint -JsonOutput | ConvertFrom-Json
        Assert-Condition ($outFail.status -eq "fail" -and $outFail.failed_step -eq "ACTraceability") "run-fast-gate.ps1 fails Stage-1 when IN_PROGRESS spec has uncovered AC-1 (AC-1)" "Expected ACTraceability fail, got $($outFail.status) / $($outFail.failed_step)"

        # AC-1: Adding test referencing AC-1 turns Stage-1 green
        Set-Content -Path (Join-Path $fgTmp "tests\app.test.js") -Value "// AC-1`ntest('AC-1 works', () => {});" -Encoding UTF8
        $outPass = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runFastGatePs1 -ProjectRoot $fgTmp -SkipLint -JsonOutput | ConvertFrom-Json
        Assert-Condition ($outPass.status -eq "pass") "run-fast-gate.ps1 passes Stage-1 once AC-1 is referenced in tests (AC-1)" "Expected pass after adding AC-1 test, got $($outPass.status)"
    } catch {
        Assert-Condition $false "run-fast-gate.ps1 FEAT-GOV-002 temp repo tests" "Exception: $_"
    } finally {
        $ErrorActionPreference = $prevEap
        Remove-Item -Path $fgTmp -Recurse -Force -ErrorAction SilentlyContinue
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
        $guardOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scanGuardPs1 -ScanPath $repoRoot -JsonOutput | ConvertFrom-Json
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
        $nextIdOut = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $lintReqPs1 -NextId -Scope "AUTH").Trim()
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
        $semverOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $calcSemverPs1 -JsonOutput | ConvertFrom-Json
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
        $i18nOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $auditI18nPs1 -JsonOutput | ConvertFrom-Json
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
        $prOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $genPrPs1 -JsonOutput | ConvertFrom-Json
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
        $diagOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $diagGitPs1 -JsonOutput | ConvertFrom-Json
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
        $docsOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $lintDocsPs1 -JsonOutput | ConvertFrom-Json
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
        $archOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $cleanArchPs1 -JsonOutput | ConvertFrom-Json
        Assert-Condition ($archOut.status -eq "pass") "lint-clean-architecture.ps1 passes on repository files (0 errors)" "lint-clean-architecture.ps1 detected $($archOut.error_count) errors"

        $tempArchDir = Join-Path ([System.IO.Path]::GetTempPath()) "arch_test_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $tempArchDir "domain") -Force | Out-Null
        Set-Content -Path (Join-Path $tempArchDir "domain\Widget.tsx") -Value "import React from 'infrastructure/db';" -NoNewline
        $tsxArchOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $cleanArchPs1 -TargetPath $tempArchDir -JsonOutput | ConvertFrom-Json
        Remove-Item -Path $tempArchDir -Recurse -Force -ErrorAction SilentlyContinue
        Assert-Condition ($tsxArchOut.status -eq "fail" -and $tsxArchOut.error_count -ge 1) "lint-clean-architecture.ps1 catches boundary violation in .tsx files" "lint-clean-architecture.ps1 missed .tsx boundary violation"
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
        $clOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $changelogPs1 -JsonOutput | ConvertFrom-Json
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
        $secOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $secAuditPs1 -JsonOutput | ConvertFrom-Json
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
        $covOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $coveragePs1 -JsonOutput | ConvertFrom-Json
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
        $dbOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $dbMigPs1 -JsonOutput | ConvertFrom-Json
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
        $apiOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $apiContractPs1 -JsonOutput | ConvertFrom-Json
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
        $orphOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $orphansPs1 -RepoRoot $repoRoot -JsonOutput | ConvertFrom-Json
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
        $ciOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $ciLintPs1 -RepoRoot $repoRoot -Strict -JsonOutput | ConvertFrom-Json
        Assert-Condition ($ciOut.status -eq "pass") "lint-ci-workflows.ps1 -Strict executes cleanly and returns pass ($($ciOut.status))" "lint-ci-workflows.ps1 -Strict reported failure or warning"
    } catch {
        Assert-Condition $false "lint-ci-workflows.ps1 executes cleanly" "Execution error: $_"
    }
}

# 39. Validate unified quality gates orchestrator scripts
Write-Host "`n39. Validating unified quality gates orchestrator scripts..." -ForegroundColor Yellow
$allGatesPs1 = Join-Path $repoRoot "scripts\run-all-gates.ps1"
$allGatesSh = Join-Path $repoRoot "scripts\run-all-gates.sh"

Assert-Condition (Test-Path $allGatesPs1) "scripts/run-all-gates.ps1 exists" "scripts/run-all-gates.ps1 not found"
Assert-Condition (Test-Path $allGatesSh) "scripts/run-all-gates.sh exists" "scripts/run-all-gates.sh not found"

if (Test-Path $allGatesPs1) {
    try {
        $gatesOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $allGatesPs1 -RepoRoot $repoRoot -Fast -JsonOutput | ConvertFrom-Json
        Assert-Condition ($gatesOut.status -eq "pass") "run-all-gates.ps1 executes cleanly and returns pass ($($gatesOut.status))" "run-all-gates.ps1 reported failure"
    } catch {
        Assert-Condition $false "run-all-gates.ps1 executes cleanly" "Execution error: $_"
    }
}

# 40. Validate test failure diagnostic scripts
Write-Host "`n40. Validating test failure diagnostic scripts..." -ForegroundColor Yellow
$failDiagPs1 = Join-Path $repoRoot "scripts\collect-test-failures.ps1"
$failDiagSh = Join-Path $repoRoot "scripts\collect-test-failures.sh"

Assert-Condition (Test-Path $failDiagPs1) "scripts/collect-test-failures.ps1 exists" "scripts/collect-test-failures.ps1 not found"
Assert-Condition (Test-Path $failDiagSh) "scripts/collect-test-failures.sh exists" "scripts/collect-test-failures.sh not found"

if (Test-Path $failDiagPs1) {
    try {
        $failOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $failDiagPs1 -RepoRoot $repoRoot -JsonOutput | ConvertFrom-Json
        Assert-Condition ($failOut.status -eq "pass") "collect-test-failures.ps1 executes cleanly and returns pass ($($failOut.status))" "collect-test-failures.ps1 reported failure"
    } catch {
        Assert-Condition $false "collect-test-failures.ps1 executes cleanly" "Execution error: $_"
    }
}

# 41. Validate startup benchmark scripts
Write-Host "`n41. Validating startup benchmark scripts..." -ForegroundColor Yellow
$benchPs1 = Join-Path $repoRoot "scripts\benchmark-startup.ps1"
$benchSh = Join-Path $repoRoot "scripts\benchmark-startup.sh"

Assert-Condition (Test-Path $benchPs1) "scripts/benchmark-startup.ps1 exists" "scripts/benchmark-startup.ps1 not found"
Assert-Condition (Test-Path $benchSh) "scripts/benchmark-startup.sh exists" "scripts/benchmark-startup.sh not found"

# 42. Validate feature specification inspector and scaffolding scripts
Write-Host "`n42. Validating feature specification inspector scripts..." -ForegroundColor Yellow
$inspectFeatPs1 = Join-Path $repoRoot "scripts\inspect-feature-specs.ps1"
$inspectFeatSh = Join-Path $repoRoot "scripts\inspect-feature-specs.sh"

Assert-Condition (Test-Path $inspectFeatPs1) "scripts/inspect-feature-specs.ps1 exists" "scripts/inspect-feature-specs.ps1 not found"
Assert-Condition (Test-Path $inspectFeatSh) "scripts/inspect-feature-specs.sh exists" "scripts/inspect-feature-specs.sh not found"

if (Test-Path $inspectFeatPs1) {
    try {
        $inspectRaw = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $inspectFeatPs1 -RepoRoot $repoRoot -JsonOutput).Trim()
        $jsonValid = ($inspectRaw -eq "[]") -or ($null -ne ($inspectRaw | ConvertFrom-Json))
        Assert-Condition $jsonValid "inspect-feature-specs.ps1 outputs valid JSON" "inspect-feature-specs.ps1 returned invalid JSON ($inspectRaw)"
        
        $conceptTmpl = Join-Path $repoRoot "docs\templates\CONCEPT_TEMPLATE.md"
        Assert-Condition (Test-Path $conceptTmpl) "docs/templates/CONCEPT_TEMPLATE.md exists" "docs/templates/CONCEPT_TEMPLATE.md not found"

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        try {
            $newOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $inspectFeatPs1 -RepoRoot $tempDir -New -Id "FEAT-CORE-001" -Title "Domain Baseline" -Phase 1 -Scope "CORE" -JsonOutput | ConvertFrom-Json
            Assert-Condition ($newOut.status -eq "created" -and (Test-Path (Join-Path $tempDir $newOut.file))) "inspect-feature-specs.ps1 scaffolds new feature spec" "inspect-feature-specs.ps1 scaffolding failed"

            $conceptOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $inspectFeatPs1 -RepoRoot $tempDir -NewConcept -ConceptId "CONCEPT-CORE-001" -Title "Domain Concept" -Scope "CORE" -JsonOutput | ConvertFrom-Json
            Assert-Condition ($conceptOut.status -eq "created" -and (Test-Path (Join-Path $tempDir $conceptOut.file))) "inspect-feature-specs.ps1 scaffolds new concept draft" "inspect-feature-specs.ps1 concept scaffolding failed"

            $archiveOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $inspectFeatPs1 -RepoRoot $tempDir -ArchiveConcept "CONCEPT-CORE-001" -JsonOutput | ConvertFrom-Json
            Assert-Condition ($archiveOut.status -eq "archived" -and (Test-Path (Join-Path $tempDir $archiveOut.destination))) "inspect-feature-specs.ps1 archives concept draft" "inspect-feature-specs.ps1 concept archiving failed"
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        }
    } catch {
        Assert-Condition $false "inspect-feature-specs.ps1 executes cleanly" "Execution error: $_"
    }
}

# 43. Validate setup-agent-skills -InitDocs onboarding and Next-Gen LLM Governance invariants
Write-Host "`n43. Validating project onboarding (-InitDocs) and Next-Gen LLM Governance..." -ForegroundColor Yellow
$setupPs1 = Join-Path $repoRoot "scripts\setup-agent-skills.ps1"
$setupSh = Join-Path $repoRoot "scripts\setup-agent-skills.sh"
Assert-Condition (Test-Path $setupPs1) "scripts/setup-agent-skills.ps1 exists" "scripts/setup-agent-skills.ps1 not found"
Assert-Condition (Test-Path $setupSh) "scripts/setup-agent-skills.sh exists" "scripts/setup-agent-skills.sh not found"

$agentsContent = Get-Content -Path (Join-Path $repoRoot "AGENTS.md") -Raw -Encoding UTF8
Assert-Condition ($agentsContent -match 'MCP & External Tool Governance') "AGENTS.md enforces MCP & External Tool Governance (Local-First Priority)" "AGENTS.md missing MCP & External Tool Governance"
Assert-Condition ($controlContent -match 'Workspace:\s*"share"') "ask-control documents isolated parallel worktrees (Workspace: share)" "ask-control missing parallel worktree documentation"
Assert-Condition ($contractContent -match 'Accessibility \(a11y\)') "ask-contract-specialist documents UI/UX Design Tokens & Multimodal Accessibility (a11y)" "ask-contract-specialist missing UI/UX & Accessibility section"

if (Test-Path $setupPs1) {
    function Remove-SafeReparsePoint([string]$p) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($item) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $item.Delete()
            } else {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 43a. AGY-only project setup (-Client agy / -SkipCopilot -> _agents)
    $tempProj = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempProj | Out-Null
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $setupPs1 -TargetProject $tempProj -InitDocs -SkipCopilot | Out-Null
        $hasInitArch = Test-Path (Join-Path $tempProj "ARCHITECTURE.md")
        $hasInitRoadmap = Test-Path (Join-Path $tempProj "docs\ROADMAP.md")
        $hasAgyLink = Test-Path (Join-Path $tempProj "_agents")
        $hasNoCopilotLink = -not (Test-Path (Join-Path $tempProj ".agents"))
        Assert-Condition ($hasInitArch -and $hasInitRoadmap) "setup-agent-skills.ps1 -InitDocs scaffolds ARCHITECTURE.md and docs/ROADMAP.md" "setup-agent-skills.ps1 -InitDocs failed to scaffold docs"
        Assert-Condition ($hasAgyLink -and $hasNoCopilotLink) "AGY-only project setup creates _agents without .agents" "AGY-only project setup link mismatch"
    } finally {
        Remove-SafeReparsePoint (Join-Path $tempProj "_agents")
        if (Test-Path $tempProj) { Remove-Item -LiteralPath $tempProj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 43b. Copilot-only project setup (-Client copilot -> .agents + .github/copilot-instructions.md)
    $tempCopilotProj = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempCopilotProj | Out-Null
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $setupPs1 -TargetProject $tempCopilotProj -Client copilot | Out-Null
        $hasDotAgents = Test-Path (Join-Path $tempCopilotProj ".agents\skills\ask-control\SKILL.md")
        $hasNoUnderscoreAgents = -not (Test-Path (Join-Path $tempCopilotProj "_agents"))
        $copilotFile = Join-Path $tempCopilotProj ".github\copilot-instructions.md"
        $copilotText = if (Test-Path $copilotFile) { Get-Content -LiteralPath $copilotFile -Raw -Encoding UTF8 } else { "" }
        Assert-Condition ($hasDotAgents -and $hasNoUnderscoreAgents) "Copilot-only project setup creates .agents (and not _agents)" "Copilot-only project setup link mismatch"
        Assert-Condition ($copilotText -match '\./\.agents/scripts/' -and $copilotText -match '\.agents/skills/') "Provisioned .github/copilot-instructions.md resolves via .agents/" "Copilot instructions do not resolve via .agents/"
    } finally {
        Remove-SafeReparsePoint (Join-Path $tempCopilotProj ".agents")
        if (Test-Path $tempCopilotProj) { Remove-Item -LiteralPath $tempCopilotProj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 43c. Global User-Level setup (-Global -> ~/_agents for AGY and ~/.agents + Zero-Reload inlined instructions for Copilot)
    $tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempHome | Out-Null
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $setupPs1 -Global -UserHome $tempHome | Out-Null
        $hasUserAgy = Test-Path (Join-Path $tempHome "_agents\skills\ask-control\SKILL.md")
        $hasGeminiSkills = Test-Path (Join-Path $tempHome ".gemini\config\skills\ask-control\SKILL.md")
        $hasUserCopilot = Test-Path (Join-Path $tempHome ".agents\skills\ask-control\SKILL.md")
        $userInstrPath = Join-Path $tempHome ".copilot\instructions\agent-skills.instructions.md"
        $userInstrText = if (Test-Path $userInstrPath) { Get-Content -LiteralPath $userInstrPath -Raw -Encoding UTF8 } else { "" }
        Assert-Condition ($hasUserAgy -and $hasGeminiSkills) "Global user setup links ~/_agents and ~/.gemini/config/skills for AGY" "Global AGY ~/_agents setup failed"
        Assert-Condition ($hasUserCopilot -and ($userInstrText -match 'applyTo:\s*"\*\*/\*"') -and ($userInstrText -match 'Inner-Loop TDD') -and ($userInstrText -match '\.agents/skills/')) "Global user setup links ~/.agents and inlines Zero-Reload instructions for Copilot" "Global Copilot ~/.agents setup failed"
    } finally {
        Remove-SafeReparsePoint (Join-Path $tempHome ".gemini\config\skills")
        Remove-SafeReparsePoint (Join-Path $tempHome ".gemini\config\rules")
        Remove-SafeReparsePoint (Join-Path $tempHome "_agents")
        Remove-SafeReparsePoint (Join-Path $tempHome ".agents")
        if (Test-Path $tempHome) { Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 43d. Direct clone into <project>/.agents: parent project works cleanly (even with -Force), self-targeting rejects .agents/.agents
    $tempDirectProj = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $directDotAgents = Join-Path $tempDirectProj ".agents"
    New-Item -ItemType Directory -Path (Join-Path $directDotAgents "scripts") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $directDotAgents ".github") -Force | Out-Null
    Copy-Item -LiteralPath $setupPs1 -Destination (Join-Path $directDotAgents "scripts\setup-agent-skills.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot ".github\copilot-instructions.md") -Destination (Join-Path $directDotAgents ".github\copilot-instructions.md") -Force
    try {
        $clonedSetupPs1 = Join-Path $directDotAgents "scripts\setup-agent-skills.ps1"
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $clonedSetupPs1 -TargetProject $tempDirectProj -Client copilot -Force | Out-Null
        $hasHostInstr = Test-Path (Join-Path $tempDirectProj ".github\copilot-instructions.md")
        $stillHasSource = Test-Path $clonedSetupPs1
        $noNestedDotAgents = -not (Test-Path (Join-Path $directDotAgents ".agents"))
        Assert-Condition ($hasHostInstr -and $stillHasSource -and $noNestedDotAgents) "Direct clone to .agents integrates into parent project without creating .agents/.agents" "Direct clone to .agents integration failed"

        $selfTargetFailed = $false
        try {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File $clonedSetupPs1 -TargetProject $directDotAgents -Client copilot 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $selfTargetFailed = $true }
        } catch {
            $selfTargetFailed = $true
        }
        $stillNoNested = -not (Test-Path (Join-Path $directDotAgents ".agents"))
        Assert-Condition ($selfTargetFailed -and $stillNoNested) "setup-agent-skills.ps1 rejects -TargetProject pointing to .agents itself (prevents .agents/.agents)" "setup-agent-skills.ps1 allowed self-targeting .agents/.agents"
    } finally {
        if (Test-Path $tempDirectProj) { Remove-Item -LiteralPath $tempDirectProj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 43e. Direct clone into ~/.agents with trailing/forward slash in -UserHome and -Force preserves repo
    $tempDirectHome = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $directHomeAgents = Join-Path $tempDirectHome ".agents"
    New-Item -ItemType Directory -Path (Join-Path $directHomeAgents "scripts") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $directHomeAgents ".github") -Force | Out-Null
    Copy-Item -LiteralPath $setupPs1 -Destination (Join-Path $directHomeAgents "scripts\setup-agent-skills.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot ".github\copilot-instructions.md") -Destination (Join-Path $directHomeAgents ".github\copilot-instructions.md") -Force
    try {
        $clonedHomeSetupPs1 = Join-Path $directHomeAgents "scripts\setup-agent-skills.ps1"
        $slashHome = $tempDirectHome.Replace('\', '/') + '/'
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $clonedHomeSetupPs1 -Global -Client copilot -UserHome $slashHome -Force | Out-Null
        $hasGlobalInstr = Test-Path (Join-Path $tempDirectHome ".copilot\instructions\agent-skills.instructions.md")
        $stillHasHomeRepo = Test-Path $clonedHomeSetupPs1
        $noNestedHomeAgents = -not (Test-Path (Join-Path $directHomeAgents ".agents"))
        Assert-Condition ($hasGlobalInstr -and $stillHasHomeRepo -and $noNestedHomeAgents) "Direct clone to ~/.agents with -Global -Force and slash-normalized UserHome preserves repo" "Direct clone to ~/.agents global setup failed"
    } finally {
        if (Test-Path $tempDirectHome) { Remove-Item -LiteralPath $tempDirectHome -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# 44. Validate Shift-Left WorkingTree Guardrails (inline/2024 Safe-Rust) and Behavioral Trace Evals
Write-Host "`n44. Validating Shift-Left WorkingTree Guardrails & Behavioral Trace Evals..." -ForegroundColor Yellow
$tempRustDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempRustDir | Out-Null
try {
    git -C $tempRustDir init -q 2>$null
    $badRustFile = Join-Path $tempRustDir "lib.rs"
    [System.IO.File]::WriteAllText($badRustFile, "#[unsafe(no_mangle)]`r`npub fn demo() { let _x = unsafe { 42 }; }`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $wtGuardOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scanGuardPs1 -ScanPath $tempRustDir -WorkingTree -JsonOutput | ConvertFrom-Json
    Assert-Condition ($wtGuardOut.status -eq "fail" -and $wtGuardOut.violations_count -ge 2) "scan-guardrails.ps1 -WorkingTree catches unstaged inline unsafe and Rust 2024 #[unsafe(...)]" "scan-guardrails.ps1 -WorkingTree missed unstaged unsafe Rust constructs"
} finally {
    if (Test-Path $tempRustDir) { Remove-Item -LiteralPath $tempRustDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$tempTrace = Join-Path ([System.IO.Path]::GetTempPath()) ("trace_" + [System.Guid]::NewGuid().ToString() + ".jsonl")
try {
    [System.IO.File]::WriteAllText($tempTrace, '{"case_id":"EVAL-GOV-001","tool_calls":[{"name":"run_command","arguments":{"CommandLine":"git status"}}]}' + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $badTraceRaw = $null
    try {
        $badTraceRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runEvalsPs1 -CaseId "EVAL-GOV-001" -TranscriptPath $tempTrace -JsonOutput 2>$null
    } catch {}
    $badTraceObj = if ($badTraceRaw) { $badTraceRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $badTraceObj -and $badTraceObj.failed -eq 1) "run-evals.ps1 -TranscriptPath deterministically flags prohibited 'git status' on Profile 0" "run-evals.ps1 -TranscriptPath failed to catch prohibited action"
} finally {
    if (Test-Path $tempTrace) { Remove-Item -LiteralPath $tempTrace -Force -ErrorAction SilentlyContinue }
}

# 45. Validate code outline AST inspector scripts and next-gen LLM efficiency invariants
Write-Host "`n45. Validating code outline AST inspector scripts and next-gen LLM efficiency invariants..." -ForegroundColor Yellow
$outlinePs1 = Join-Path $repoRoot "scripts\get-code-outline.ps1"
$outlineSh = Join-Path $repoRoot "scripts\get-code-outline.sh"
Assert-Condition (Test-Path $outlinePs1) "scripts/get-code-outline.ps1 exists" "scripts/get-code-outline.ps1 not found"
Assert-Condition (Test-Path $outlineSh) "scripts/get-code-outline.sh exists" "scripts/get-code-outline.sh not found"

if (Test-Path $outlinePs1) {
    try {
        $outlineOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $outlinePs1 -Path $repoRoot -JsonOutput | ConvertFrom-Json
        Assert-Condition ($outlineOut.status -eq "pass") "get-code-outline.ps1 executes cleanly and outputs valid JSON" "get-code-outline.ps1 reported failure"
    } catch {
        Assert-Condition $false "get-code-outline.ps1 executes cleanly" "Execution error: $_"
    }
}

Assert-Condition ($agentsContent -match 'Surgical Edit First') "AGENTS.md enforces Surgical Edit First Invariant" "AGENTS.md missing Surgical Edit First Invariant"
Assert-Condition ($agentsContent -match 'Two-Zone Prompt Cache Architecture') "AGENTS.md enforces Two-Zone Prompt Cache Architecture" "AGENTS.md missing Two-Zone Prompt Cache Architecture"
Assert-Condition ($controlContent -match 'Thinking Budget Clamping') "ask-control enforces Thinking Budget Clamping" "ask-control missing Thinking Budget Clamping"
$modelTiersRaw = Get-Content -Path $modelTiersFile -Raw -Encoding UTF8
Assert-Condition ($modelTiersRaw -match 'thinking_budget_guardrail' -and $modelTiersRaw -match 'split_phase_profile_b') "model-tiers.json documents thinking budget guardrail and split-phase execution" "model-tiers.json missing efficiency guardrails"

# 46. Validate deferred formatting, prepare-commit hygiene, and AGY 24KB rule cap
Write-Host "`n46. Validating deferred formatting, prepare-commit hygiene, and AGY 24KB rule cap..." -ForegroundColor Yellow
$prepCommitPs1 = Join-Path $repoRoot "scripts\prepare-commit.ps1"
$prepCommitSh = Join-Path $repoRoot "scripts\prepare-commit.sh"
Assert-Condition (Test-Path $prepCommitPs1) "scripts/prepare-commit.ps1 exists" "scripts/prepare-commit.ps1 not found"
Assert-Condition (Test-Path $prepCommitSh) "scripts/prepare-commit.sh exists" "scripts/prepare-commit.sh not found"

$agentsBytes = (Get-Item (Join-Path $repoRoot "AGENTS.md")).Length
$subagentsBytes = (Get-Item (Join-Path $repoRoot "rules\subagents.md")).Length
Assert-Condition ($agentsBytes -le 24000 -and $subagentsBytes -le 24000) "AGENTS.md ($agentsBytes B) and rules/subagents.md ($subagentsBytes B) stay within AGY 24KB rule limit" "Rule file exceeds 24000 bytes (AGENTS=$agentsBytes, subagents=$subagentsBytes)"

$auditorSkillContent = Get-Content -Path (Join-Path $skillsDir "ask-skill-auditor\SKILL.md") -Raw -Encoding UTF8
Assert-Condition ($auditorSkillContent -match 'Rules A1' -and $auditorSkillContent -match 'CONVERGED & SATURATED' -and $auditorSkillContent -match 'Monotonic Audit Ratchet') "ask-skill-auditor enforces deterministic A1-A10 rules, anti-oscillation saturation gate, and monotonic self-audit" "ask-skill-auditor missing mandatory audit sections"
Assert-Condition ($auditorSkillContent -match 'Platform & Client Capability Alignment' -and $auditorSkillContent -match 'Antigravity' -and $auditorSkillContent -match 'Copilot CLI' -and $auditorSkillContent -match 'routine_task_thresholds' -and $auditorSkillContent -notmatch '\$4\.00/M|\$20\.00/M') "ask-skill-auditor audits AGY/Copilot CLI platform capabilities and resolves cost-guardrail thresholds dynamically from SSOT" "ask-skill-auditor missing platform capability alignment or still hardcodes static dollar thresholds"

$subagentsContent = Get-Content -Path (Join-Path $repoRoot "rules\subagents.md") -Raw -Encoding UTF8
$readmeCostContent = Get-Content -Path (Join-Path $repoRoot "README.md") -Raw -Encoding UTF8
Assert-Condition ($subagentsContent -match 'routine_task_thresholds' -and $subagentsContent -notmatch '\$4\.00/M|\$20\.00/M' -and $readmeCostContent -notmatch '\$4\.00/M|\$20\.00/M' -and $modelTiersData.cost_efficiency_policy.cost_guardrail.routine_task_thresholds.threshold_mode -eq 'dynamic') "Cost-guardrail thresholds are managed dynamically in rules/model-tiers.json without hardcoded dollar prose in rules/subagents.md or README.md" "Static dollar thresholds found in rules/subagents.md or README.md, or threshold_mode is not 'dynamic' in rules/model-tiers.json"

$tempFmtDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempFmtDir | Out-Null
try {
    [System.IO.File]::WriteAllText((Join-Path $tempFmtDir "App.csproj"), "<Project Sdk=`"Microsoft.NET.Sdk`"></Project>`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $dotnetStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File $detectStackPs1 -ProjectRoot $tempFmtDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ([string]::IsNullOrEmpty($dotnetStack.lint_cmd) -and $dotnetStack.format_check_cmd -match 'dotnet format') "detect-tech-stack.ps1 separates dotnet format into format_check_cmd (fast inner-loop)" "detect-tech-stack.ps1 still couples dotnet format into lint_cmd"
    Remove-Item (Join-Path $tempFmtDir "App.csproj") -Force

    [System.IO.File]::WriteAllText((Join-Path $tempFmtDir "build.gradle.kts"), "plugins { id(`"com.diffplug.spotless`") }`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $gradleStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File $detectStackPs1 -ProjectRoot $tempFmtDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($gradleStack.stack -eq "gradle" -and $gradleStack.build_cmd -match '-x spotlessCheck' -and $gradleStack.test_cmd -match '-x spotlessCheck' -and [string]::IsNullOrEmpty($gradleStack.lint_cmd) -and $gradleStack.format_check_cmd -match 'spotlessCheck') "detect-tech-stack.ps1 excludes spotlessCheck from Gradle build/test and defers it exclusively to format_check_cmd" "detect-tech-stack.ps1 failed to isolate Gradle spotlessCheck ($($gradleStack | ConvertTo-Json -Compress))"
    Remove-Item (Join-Path $tempFmtDir "build.gradle.kts") -Force

    $nonNativeRust = Join-Path $tempFmtDir "sample.rs"
    [System.IO.File]::WriteAllText($nonNativeRust, "pub fn ok() -> i32 { 1 }`n", (New-Object System.Text.UTF8Encoding($false)))
    $skipEolOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scanGuardPs1 -ScanPath $tempFmtDir -SkipLineEndings -JsonOutput | ConvertFrom-Json
    Assert-Condition ($skipEolOut.status -eq "pass") "scan-guardrails.ps1 -SkipLineEndings defers line-ending check during inner-loop" "scan-guardrails.ps1 -SkipLineEndings failed on non-native EOL file"

    # Git repo tests for prepare-commit.ps1 (Windows target EOL = CRLF)
    $prepRepo = Join-Path $tempFmtDir "repo"
    New-Item -ItemType Directory -Path $prepRepo | Out-Null
    git -C $prepRepo init -q 2>$null
    git -C $prepRepo config user.email "test@example.com"
    git -C $prepRepo config user.name "Test User"
    git -C $prepRepo config core.autocrlf false

    $nativeCrlfFile = Join-Path $prepRepo "notes.md"
    $legacyLfFile = Join-Path $prepRepo "legacy.txt"
    [System.IO.File]::WriteAllText($nativeCrlfFile, "# Title`r`nLine 2`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($legacyLfFile, "alpha`nbeta`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $prepRepo add notes.md legacy.txt
    git -C $prepRepo commit -q -m "chore: init"

    # 46a. Whitespace-only (LF) change on CRLF file -> detected and reverted cleanly
    [System.IO.File]::WriteAllText($nativeCrlfFile, "# Title`nLine 2`n", (New-Object System.Text.UTF8Encoding($false)))
    $wsDetect = $null
    try { $wsDetect = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -JsonOutput 2>$null | ConvertFrom-Json } catch {}
    Assert-Condition ($null -ne $wsDetect -and $wsDetect.status -eq "needs_decision" -and ($wsDetect.whitespace_only_files -contains "notes.md") -and [string]::IsNullOrEmpty($wsDetect.suggested_commit_message)) "prepare-commit.ps1 detects whitespace/EOL-only diff against HEAD and withholds commit message until clean" "prepare-commit.ps1 failed to detect whitespace-only diff or leaked draft message"

    $wsRevert = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -RevertWhitespaceOnly -JsonOutput | ConvertFrom-Json
    Assert-Condition ($wsRevert.status -eq "clean" -and ($wsRevert.reverted_whitespace_files -contains "notes.md")) "prepare-commit.ps1 -RevertWhitespaceOnly reverts noise diffs to HEAD" "prepare-commit.ps1 failed to revert whitespace-only diff"

    # 46b. Real edit + LF on CRLF file -> normalized automatically to CRLF on Windows under -Direct
    [System.IO.File]::WriteAllText($nativeCrlfFile, "# Title`nLine 2`nLine 3`n", (New-Object System.Text.UTF8Encoding($false)))
    $directRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -Direct -JsonOutput | ConvertFrom-Json
    $notesAfterDirect = [System.IO.File]::ReadAllText($nativeCrlfFile, [System.Text.Encoding]::UTF8)
    Assert-Condition ($directRes.status -eq "ready" -and $directRes.target_eol -eq "CRLF" -and $directRes.next_step -eq "execute_commit" -and ($directRes.normalized_files -contains "notes.md") -and $notesAfterDirect.Contains("`r`n") -and ($notesAfterDirect -notmatch '(?<!\r)\n')) "prepare-commit.ps1 -Direct normalizes unambiguous LF->CRLF on Windows and signals execute_commit" "prepare-commit.ps1 -Direct failed on unambiguous Windows CRLF normalization"

    # 46c. Ambiguous legacy LF file -> pauses for user decision even with -Direct until -ForceNormalize
    [System.IO.File]::WriteAllText($legacyLfFile, "alpha`nbeta`ngamma`n", (New-Object System.Text.UTF8Encoding($false)))
    $ambigRes = $null
    try { $ambigRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -Direct -JsonOutput 2>$null | ConvertFrom-Json } catch {}
    Assert-Condition ($null -ne $ambigRes -and $ambigRes.status -eq "needs_decision" -and ($ambigRes.ambiguous_files -contains "legacy.txt")) "prepare-commit.ps1 pauses for user decision on ambiguous legacy LF file on Windows" "prepare-commit.ps1 normalized ambiguous file without permission"

    $forceRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -Direct -ForceNormalize -JsonOutput | ConvertFrom-Json
    $legacyAfterForce = [System.IO.File]::ReadAllText($legacyLfFile, [System.Text.Encoding]::UTF8)
    Assert-Condition ($forceRes.status -eq "ready" -and ($forceRes.normalized_files -contains "legacy.txt") -and $legacyAfterForce.Contains("`r`n") -and ($legacyAfterForce -notmatch '(?<!\r)\n')) "prepare-commit.ps1 -ForceNormalize normalizes legacy LF->CRLF on Windows after confirmation" "prepare-commit.ps1 -ForceNormalize failed"

    # 46d. Governance/tooling mixed commit heuristic -> chore(tooling) (not feat(tests))
    git -C $prepRepo add notes.md legacy.txt
    git -C $prepRepo commit -q -m "chore: sync"
    New-Item -ItemType Directory -Path (Join-Path $prepRepo "scripts") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $prepRepo ".gitattributes"), "* text=auto`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo "AGENTS.md"), "# Agents`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo "scripts\test-skills.ps1"), "Write-Host 'ok'`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $toolingRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -JsonOutput | ConvertFrom-Json
    Assert-Condition ($toolingRes.status -eq "ready" -and $toolingRes.suggested_commit_message -match '^chore\(tooling\): update \.gitattributes and 2 additional file\(s\)$') "prepare-commit.ps1 classifies dotfile+docs+scripts as chore(tooling) without blank leaf ($($toolingRes.suggested_commit_message))" "prepare-commit.ps1 misclassified governance/tooling commit or leaked blank leaf: $($toolingRes.suggested_commit_message)"

    # 46e. Project config overrides (.gitattributes eol=lf and .editorconfig end_of_line=lf) take precedence over OS-native CRLF on Windows
    Assert-Condition ($agentsContent -match 'OS-Native Line Endings Invariant') "AGENTS.md enforces OS-Native Line Endings Invariant" "AGENTS.md missing OS-Native Line Endings Invariant"
    $prepShRaw = Get-Content -Path $prepCommitSh -Raw -Encoding UTF8
    Assert-Condition ($prepShRaw -match 'command -v file') "prepare-commit.sh includes command -v file fallback allowlist" "prepare-commit.sh missing command -v file fallback"

    git -C $prepRepo add .gitattributes AGENTS.md scripts/test-skills.ps1
    git -C $prepRepo commit -q -m "chore: baseline"
    [System.IO.File]::WriteAllText((Join-Path $prepRepo ".gitattributes"), "* text=auto`r`n*.sh text eol=lf`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo ".editorconfig"), "root = true`r`n[*.md]`r`nend_of_line = lf`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo "scripts\build.sh"), "#!/usr/bin/env bash`necho ok`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo "README.md"), "# Readme`r`nLine 2`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $prepRepo "default.txt"), "hello`nworld`n", (New-Object System.Text.UTF8Encoding($false)))
    $ovRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $prepRepo -Direct -JsonOutput | ConvertFrom-Json
    $shBytes = [System.IO.File]::ReadAllBytes((Join-Path $prepRepo "scripts\build.sh"))
    $mdBytes = [System.IO.File]::ReadAllBytes((Join-Path $prepRepo "README.md"))
    $defText = [System.IO.File]::ReadAllText((Join-Path $prepRepo "default.txt"), [System.Text.Encoding]::UTF8)
    $shIsLf = -not ($shBytes -contains 13)
    $mdIsLf = -not ($mdBytes -contains 13)
    $defIsCrlf = $defText.Contains("`r`n") -and ($defText -notmatch '(?<!\r)\n')
    Assert-Condition ($ovRes.status -eq "ready" -and $shIsLf -and $mdIsLf -and $defIsCrlf) "prepare-commit.ps1 and scan-guardrails.ps1 honor .gitattributes/.editorconfig EOL overrides while defaulting others to OS-native CRLF" "Project EOL override or OS-native default failed (status=$($ovRes.status), shLf=$shIsLf, mdLf=$mdIsLf, defCrlf=$defIsCrlf)"
} finally {
    if (Test-Path $tempFmtDir) { Remove-Item -LiteralPath $tempFmtDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 47. Validate scalar-safe single-line linting, inspect-feature-specs flags, and eval invariant coverage
Write-Host "`n47. Validating scalar-safe single-line linting, CLI flags, and eval coverage..." -ForegroundColor Yellow
$contractSkillContent = Get-Content -Path (Join-Path $skillsDir "ask-contract-specialist\SKILL.md") -Raw -Encoding UTF8
Assert-Condition ($contractSkillContent -match '-List\b' -and $contractSkillContent -match '--list\b' -and $contractSkillContent -notmatch 'ListAll|--list-all') "ask-contract-specialist uses valid -List/--list flags for inspect-feature-specs" "ask-contract-specialist contains invalid -ListAll/--list-all flag"

$runEvalsRaw = Get-Content -Path $runEvalsPs1 -Raw -Encoding UTF8
Assert-Condition ($runEvalsRaw -match 'targeted_test_first' -and $runEvalsRaw -match 'zero_git_on_read' -and $runEvalsRaw -match 'zero_test_execution_on_markdown') "run-evals.ps1 actively asserts targeted_test_first, zero_git_on_read, and zero_test_execution_on_markdown" "run-evals.ps1 missing active invariant checks"

$tempSingleDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempSingleDir | Out-Null
try {
    [System.IO.File]::WriteAllText((Join-Path $tempSingleDir "single.md"), "[broken](missing-target.md)", (New-Object System.Text.UTF8Encoding($false)))
    $lintDocsPs1 = Join-Path $repoRoot "scripts\lint-docs.ps1"
    $singleDocOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $lintDocsPs1 -RepoRoot $tempSingleDir -JsonOutput 2>$null
    $singleDocObj = if ($singleDocOut) { $singleDocOut | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $singleDocObj -and $singleDocObj.status -eq "fail" -and $singleDocObj.broken_links_count -eq 1) "lint-docs.ps1 handles 1-line markdown files safely (array-wrapped Get-Content)" "lint-docs.ps1 failed on 1-line markdown file ($singleDocOut)"

    $singleReqFile = Join-Path $tempSingleDir "REQUIREMENTS.md"
    [System.IO.File]::WriteAllText($singleReqFile, "### [REQ-CORE-001] Single line req (APPROVED)", (New-Object System.Text.UTF8Encoding($false)))
    $lintReqPs1 = Join-Path $repoRoot "scripts\lint-requirements.ps1"
    $singleReqOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $lintReqPs1 -RequirementsPath $tempSingleDir -JsonOutput 2>$null
    $singleReqObj = if ($singleReqOut) { $singleReqOut | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $singleReqObj -and $singleReqObj.status -eq "pass" -and $singleReqObj.defined_count -eq 1) "lint-requirements.ps1 handles 1-line requirement files safely (array-wrapped Get-Content)" "lint-requirements.ps1 failed on 1-line requirements file ($singleReqOut)"

    $unknownEvalFile = Join-Path $tempSingleDir "eval-unknown.json"
    [System.IO.File]::WriteAllText($unknownEvalFile, '{"eval_cases":[{"id":"EVAL-UNK-001","name":"Unknown Check","category":"governance","input":"test","expected":{"required_invariants":["nonexistent_invariant_xyz"]}}]}', (New-Object System.Text.UTF8Encoding($false)))
    $unkEvalRaw = $null
    try { $unkEvalRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File $runEvalsPs1 -EvalFile $unknownEvalFile -JsonOutput 2>$null } catch {}
    $unkEvalObj = if ($unkEvalRaw) { $unkEvalRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $unkEvalObj -and $unkEvalObj.failed -eq 1) "run-evals.ps1 rejects unknown/unhandled required_invariants" "run-evals.ps1 silently passed an unknown required_invariant"
} finally {
    if (Test-Path $tempSingleDir) { Remove-Item -LiteralPath $tempSingleDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$readmeRaw = Get-Content -Path (Join-Path $repoRoot "README.md") -Raw -Encoding UTF8
Assert-Condition ($readmeRaw -match '5 consolidated specialist capability packs' -and $readmeRaw -notmatch '4 consolidated specialist capability packs') "README.md accurately lists 5 specialist capability packs" "README.md has stale specialist pack count"
Assert-Condition ($gitTroubleContent -match 'safety-snapshot-\*') "ask-git-troubleshooter documents safety-snapshot-* branch verification matching diagnose-git-state" "ask-git-troubleshooter snapshot verification mismatches diagnose-git-state"

# 48. Validate Clean Architecture word-boundary precision, staged whitespace revert, and doc alignment
Write-Host "`n48. Validating Clean Architecture word-boundary precision, staged whitespace revert, and doc alignment..." -ForegroundColor Yellow
$tempAuditDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path (Join-Path $tempAuditDir "domain") -Force | Out-Null
try {
    [System.IO.File]::WriteAllText((Join-Path $tempAuditDir "domain\Entity.rs"), "use uuid::Uuid;`r`nuse serde::Serialize;`r`npub struct Order { id: Uuid }`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $uuidArchOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $cleanArchPs1 -TargetPath $tempAuditDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($uuidArchOut.status -eq "pass" -and $uuidArchOut.error_count -eq 0) "lint-clean-architecture.ps1 avoids false-positive substring matches on 'uuid' in domain/" "lint-clean-architecture.ps1 reported false positive on uuid import"

    # Staged whitespace-only diff revert via prepare-commit.ps1
    $stagedRepo = Join-Path $tempAuditDir "staged-repo"
    New-Item -ItemType Directory -Path $stagedRepo | Out-Null
    git -C $stagedRepo init -q 2>$null
    git -C $stagedRepo config user.email "test@example.com"
    git -C $stagedRepo config user.name "Test User"
    git -C $stagedRepo config core.autocrlf false
    $stagedDoc = Join-Path $stagedRepo "notes.md"
    [System.IO.File]::WriteAllText($stagedDoc, "# Notes`r`nLine 1`r`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $stagedRepo add notes.md
    git -C $stagedRepo commit -q -m "chore: init"
    [System.IO.File]::WriteAllText($stagedDoc, "# Notes`nLine 1`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $stagedRepo add notes.md
    $stagedRevRes = & $psExe -NoProfile -ExecutionPolicy Bypass -File $prepCommitPs1 -RepoRoot $stagedRepo -RevertWhitespaceOnly -JsonOutput | ConvertFrom-Json
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $postGitStatus = (git -C $stagedRepo status --porcelain 2>$null)
    $ErrorActionPreference = $prevEap
    Assert-Condition ($stagedRevRes.status -eq "clean" -and ($stagedRevRes.reverted_whitespace_files -contains "notes.md") -and [string]::IsNullOrWhiteSpace($postGitStatus)) "prepare-commit.ps1 reverts staged whitespace-only diffs cleanly from HEAD" "prepare-commit.ps1 failed to revert staged whitespace-only diff ($postGitStatus)"
} finally {
    if (Test-Path $tempAuditDir) { Remove-Item -LiteralPath $tempAuditDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Assert-Condition ($gitTroubleContent -match 'OS-Native Line Endings Invariant' -and $gitTroubleContent -notmatch '\* text=auto eol=lf') "ask-git-troubleshooter aligns with OS-Native Line Endings Invariant" "ask-git-troubleshooter contradicts OS-Native Line Endings Invariant"
$archDocRaw = Get-Content -Path (Join-Path $repoRoot "ARCHITECTURE.md") -Raw -Encoding UTF8
Assert-Condition ($archDocRaw -match "$($rawEvals.eval_cases.Count)\s+Synthetic Scenario Benchmarks") "ARCHITECTURE.md benchmark count matches evals/eval-cases.json ($($rawEvals.eval_cases.Count))" "ARCHITECTURE.md benchmark count is stale"

# 49. Validate cross-OS spec drift stability, ROADMAP count, and single-gate failure detection
Write-Host "`n49. Validating cross-OS spec drift stability, ROADMAP count, and single-gate failure detection..." -ForegroundColor Yellow
$driftOut = & $psExe -NoProfile -ExecutionPolicy Bypass -File $inspectFeatPs1 -RepoRoot $repoRoot -CheckDrift -JsonOutput | ConvertFrom-Json
Assert-Condition ($driftOut.status -eq "synchronized" -and $driftOut.drift_count -eq 0) "inspect-feature-specs.ps1 -CheckDrift is cross-OS synchronized (LF-normalized hashes)" "inspect-feature-specs.ps1 -CheckDrift reported drift: $($driftOut | ConvertTo-Json -Compress)"

$roadmapRaw = Get-Content -Path (Join-Path $repoRoot "docs\ROADMAP.md") -Raw -Encoding UTF8
Assert-Condition ($roadmapRaw -match '5 On-Demand Specialist Capability Packs') "docs/ROADMAP.md accurately lists 5 On-Demand Specialist Capability Packs" "docs/ROADMAP.md has stale specialist count"

$tempGateDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path (Join-Path $tempGateDir "domain") -Force | Out-Null
try {
    [System.IO.File]::WriteAllText((Join-Path $tempGateDir "domain\Bad.rs"), "use crate::infrastructure::db;`r`npub fn x() {}`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $failGateRaw = $null
    try { $failGateRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File $allGatesPs1 -RepoRoot $tempGateDir -Fast -JsonOutput 2>$null } catch {}
    $failGateObj = if ($failGateRaw) { $failGateRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $failGateObj -and $failGateObj.status -eq "fail" -and $failGateObj.failed_gates -eq 1) "run-all-gates.ps1 detects single failing gate safely (PS 5.1 scalar array wrapping)" "run-all-gates.ps1 failed to report single failing gate ($failGateRaw)"
} finally {
    if (Test-Path $tempGateDir) { Remove-Item -LiteralPath $tempGateDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$badPwshChecks = @(Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter "*.ps1" | Where-Object {
    $raw = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    $raw -match "WindowsApps\\\\pwsh\\\.exe"
})
Assert-Condition ($badPwshChecks.Count -eq 0) "All PowerShell scripts guard full WindowsApps Store-alias paths safely" "Legacy WindowsApps\\pwsh.exe regex found in: $($badPwshChecks.Name -join ', ')"

# 50. Validate parent-path-safe doc linting, non-word Clean Arch imports, and Bash parity hardening
Write-Host "`n50. Validating parent-path-safe doc linting, non-word Clean Arch imports, and Bash parity hardening..." -ForegroundColor Yellow
$tempHardeningDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    # 50a. lint-docs.ps1 scans markdown files when RepoRoot itself is under a '.agents' parent directory
    $nestedAgentsRepo = Join-Path $tempHardeningDir ".agents"
    $nestedIgnored = Join-Path $nestedAgentsRepo "node_modules"
    New-Item -ItemType Directory -Path $nestedIgnored -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $nestedAgentsRepo "README.md"), "# Root Doc`r`n[Missing](missing.md)`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $nestedIgnored "IGNORED.md"), "# Ignored`r`n[Bad](nope.md)`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $docsParentRaw = $null
    try { $docsParentRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-docs.ps1") -RepoRoot $nestedAgentsRepo -JsonOutput 2>$null } catch {}
    $docsParentObj = if ($docsParentRaw) { $docsParentRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $docsParentObj -and $docsParentObj.scanned_markdowns -eq 1 -and $docsParentObj.broken_links_count -eq 1) "lint-docs.ps1 scans repos residing under .agents/ while excluding nested node_modules/" "lint-docs.ps1 failed parent-path scoping ($docsParentRaw)"

    # 50b. lint-clean-architecture.ps1 catches non-word-prefixed forbidden_imports (e.g. @prisma/client)
    $scopedArchRepo = Join-Path $tempHardeningDir "scoped-arch"
    New-Item -ItemType Directory -Path (Join-Path $scopedArchRepo "domain") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $scopedArchRepo ".agent-lint.json"), '{"layer_boundaries":[{"layer":"domain","path_pattern":"(?i)(^|[\\\\/])domain[\\\\/]","forbidden_imports":["@prisma/client"],"message":"No Prisma in domain"}]}', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $scopedArchRepo "domain\Order.ts"), "import { PrismaClient } from '@prisma/client';`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $scopedArchRaw = $null
    try { $scopedArchRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -TargetPath $scopedArchRepo -JsonOutput 2>$null } catch {}
    $scopedArchObj = if ($scopedArchRaw) { $scopedArchRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $scopedArchObj -and $scopedArchObj.status -eq "fail" -and $scopedArchObj.error_count -eq 1) "lint-clean-architecture.ps1 catches non-word-prefixed forbidden_imports (@prisma/client)" "lint-clean-architecture.ps1 missed @prisma/client violation ($scopedArchRaw)"
} finally {
    if (Test-Path $tempHardeningDir) { Remove-Item -LiteralPath $tempHardeningDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$prepShRaw = Get-Content -Path (Join-Path $repoRoot "scripts\prepare-commit.sh") -Raw -Encoding UTF8
Assert-Condition ($prepShRaw -match 'is_text_file\(\)' -and $prepShRaw -match 'is_text_file "\$full_fmt"' -and $prepShRaw -match 'application/\(json\|xml\|javascript\|x-sh\|x-shellscript\)') "prepare-commit.sh guards binary files during --format and detects .json/.xml/.js text files cleanly" "prepare-commit.sh missing is_text_file guard or MIME allowlist parity"

$detectShRaw = Get-Content -Path (Join-Path $repoRoot "scripts\detect-models.sh") -Raw -Encoding UTF8
Assert-Condition ($detectShRaw -match '\.gemini/antigravity-cli') "detect-models.sh detects ~/.gemini/antigravity-cli (matching detect-models.ps1)" "detect-models.sh missing .gemini/antigravity-cli detection"

$reqShRaw = Get-Content -Path (Join-Path $repoRoot "scripts\lint-requirements.sh") -Raw -Encoding UTF8
Assert-Condition ($reqShRaw -match '(?m)^\s*--scope\)') "lint-requirements.sh supports space-separated --scope flag" "lint-requirements.sh missing space-separated --scope support"

# 51. Validate FEAT-TOOL-002 Android & Kotlin Toolchain Guardrails (AC-1 through AC-7)
Write-Host "`n51. Validating FEAT-TOOL-002 Android & Kotlin Toolchain Guardrails..." -ForegroundColor Yellow
$tempAndroidDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    New-Item -ItemType Directory -Path (Join-Path $tempAndroidDir "domain") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempAndroidDir "app\src\main\kotlin") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempAndroidDir "app\src\test\kotlin") -Force | Out-Null

    # AC-1: Android Gradle Plugin detection
    [System.IO.File]::WriteAllText((Join-Path $tempAndroidDir "build.gradle.kts"), "plugins { id(`"com.android.library`") }`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $agpStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $tempAndroidDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($agpStack.stack -eq "android-gradle" -and $agpStack.test_cmd -match 'testDebugUnitTest') "FEAT-TOOL-002 AC-1: detect-tech-stack.ps1 detects Android Gradle Plugin and testDebugUnitTest" "FEAT-TOOL-002 AC-1 failed: $($agpStack | ConvertTo-Json -Compress)"

    # AC-2: Kotlin Clean Architecture violation
    [System.IO.File]::WriteAllText((Join-Path $tempAndroidDir "domain\StyleRepo.kt"), "import android.database.Cursor`r`nclass StyleRepo`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $ktArchRaw = $null
    try { $ktArchRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -TargetPath $tempAndroidDir -JsonOutput 2>$null } catch {}
    $ktArchObj = if ($ktArchRaw) { $ktArchRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $ktArchObj -and $ktArchObj.status -eq "fail" -and $ktArchObj.error_count -ge 1) "FEAT-TOOL-002 AC-2: lint-clean-architecture.ps1 blocks android.database.Cursor in domain/" "FEAT-TOOL-002 AC-2 failed ($ktArchRaw)"

    # AC-3: Kotlin AST code outline
    [System.IO.File]::WriteAllText((Join-Path $tempAndroidDir "app\src\main\kotlin\StyleUi.kt"), "@Composable`r`nfun StyleBadge(modifier: Modifier = Modifier) {`r`n}`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $ktOutline = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\get-code-outline.ps1") -Path (Join-Path $tempAndroidDir "app\src\main\kotlin\StyleUi.kt") -RepoRoot $tempAndroidDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($ktOutline.files.Count -eq 1 -and $ktOutline.files[0].signatures.Count -ge 1) "FEAT-TOOL-002 AC-3: get-code-outline.ps1 extracts Kotlin/@Composable signatures" "FEAT-TOOL-002 AC-3 failed"

    # AC-6: lint-android-contracts detects CursorLeak and MissingNotifyChange
    [System.IO.File]::WriteAllText((Join-Path $tempAndroidDir "app\src\main\kotlin\BadProvider.kt"), "class BadProvider : ContentProvider() {`r`n  override fun insert(uri: Uri, v: ContentValues?) {`r`n    val c = contentResolver.query(uri, null, null, null, null)`r`n  }`r`n}`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $androidLintRaw = $null
    try { $androidLintRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-android-contracts.ps1") -ProjectRoot $tempAndroidDir -JsonOutput 2>$null } catch {}
    $androidLintObj = if ($androidLintRaw) { $androidLintRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $androidLintObj -and $androidLintObj.status -eq "fail" -and $androidLintObj.errors.Count -ge 2) "FEAT-TOOL-002 AC-6: lint-android-contracts.ps1 flags CursorLeak and MissingNotifyChange" "FEAT-TOOL-002 AC-6 failed ($androidLintRaw)"

    # AC-4 & AC-5: Manifest code-gate regex & Gradle JUnit XML discovery
    $fgRaw = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -Raw -Encoding UTF8
    Assert-Condition ($fgRaw -match 'AndroidManifest\\\.xml' -and $fgRaw -match 'androidTest') "FEAT-TOOL-002 AC-4: run-fast-gate.ps1 includes AndroidManifest.xml and androidTest discovery" "FEAT-TOOL-002 AC-4 failed"
    $ctfRaw = Get-Content -Path (Join-Path $repoRoot "scripts\collect-test-failures.ps1") -Raw -Encoding UTF8
    $covRaw = Get-Content -Path (Join-Path $repoRoot "scripts\check-test-coverage.ps1") -Raw -Encoding UTF8
    Assert-Condition ($ctfRaw -match 'build/test-results' -and $covRaw -match 'jacoco') "FEAT-TOOL-002 AC-5: Gradle JUnit XML and JaCoCo XML auto-discovery enabled" "FEAT-TOOL-002 AC-5 failed"

    # AC-7: .ps1 / .sh parity for lint-android-contracts
    Assert-Condition (Test-Path (Join-Path $repoRoot "scripts\lint-android-contracts.sh")) "FEAT-TOOL-002 AC-7: lint-android-contracts.sh parity script exists" "FEAT-TOOL-002 AC-7 failed"
} finally {
    if (Test-Path $tempAndroidDir) { Remove-Item -LiteralPath $tempAndroidDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 52. Validate FEAT-TOOL-003 C++ (MinGW/MSVC) & Qt / QtQuick (QML) Toolchain Guardrails (AC-1 through AC-7)
Write-Host "`n52. Validating FEAT-TOOL-003 C++/Qt/QML Toolchain Guardrails..." -ForegroundColor Yellow
$tempCppDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    New-Item -ItemType Directory -Path (Join-Path $tempCppDir "domain") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempCppDir "src") -Force | Out-Null

    # AC-1: CMake MinGW detection
    [System.IO.File]::WriteAllText((Join-Path $tempCppDir "CMakeLists.txt"), "cmake_minimum_required(VERSION 3.20)`n# MinGW toolchain`nproject(QtApp)`n", (New-Object System.Text.UTF8Encoding($false)))
    $cmakeStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $tempCppDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($cmakeStack.stack -eq "cmake-mingw" -and $cmakeStack.language -eq "cpp" -and $cmakeStack.test_cmd -match 'ctest') "FEAT-TOOL-003 AC-1: detect-tech-stack.ps1 detects CMake MinGW and ctest" "FEAT-TOOL-003 AC-1 failed: $($cmakeStack | ConvertTo-Json -Compress)"

    # AC-2: C++/QML Clean Architecture violation
    [System.IO.File]::WriteAllText((Join-Path $tempCppDir "domain\Engine.hpp"), "#include <QtQuick/QQuickItem>`nclass Engine {};`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $cppArchRaw = $null
    try { $cppArchRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -TargetPath $tempCppDir -JsonOutput 2>$null } catch {}
    $cppArchObj = if ($cppArchRaw) { $cppArchRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $cppArchObj -and $cppArchObj.status -eq "fail" -and $cppArchObj.error_count -ge 1) "FEAT-TOOL-003 AC-2: lint-clean-architecture.ps1 blocks QtQuick in domain/" "FEAT-TOOL-003 AC-2 failed ($cppArchRaw)"

    # AC-3: C++/QML AST code outline
    [System.IO.File]::WriteAllText((Join-Path $tempCppDir "src\MainView.qml"), "import QtQuick`r`nItem {`r`n  property string title: ''`r`n  function refresh() {}`r`n}`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $qmlOutline = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\get-code-outline.ps1") -Path (Join-Path $tempCppDir "src\MainView.qml") -RepoRoot $tempCppDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($qmlOutline.files.Count -eq 1 -and $qmlOutline.files[0].signatures.Count -ge 2) "FEAT-TOOL-003 AC-3: get-code-outline.ps1 extracts QML component, property, and function signatures" "FEAT-TOOL-003 AC-3 failed"

    # AC-6: lint-cpp-qt-contracts detects MissingQObjectMacro and Qt6ConnectionsSyntax
    [System.IO.File]::WriteAllText((Join-Path $tempCppDir "src\BadVm.hpp"), "class BadVm : public QObject {`r`n  Q_PROPERTY(int count READ count)`r`n};`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $tempCppDir "src\BadConn.qml"), "Connections {`r`n  onClicked: console.log('hi')`r`n}`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $cppQtRaw = $null
    try { $cppQtRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.ps1") -ProjectRoot $tempCppDir -JsonOutput 2>$null } catch {}
    $cppQtObj = if ($cppQtRaw) { $cppQtRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $cppQtObj -and $cppQtObj.status -eq "fail" -and $cppQtObj.errors.Count -ge 3) "FEAT-TOOL-003 AC-6: lint-cpp-qt-contracts.ps1 flags MissingQObjectMacro, MissingNotifySignal, and Qt6ConnectionsSyntax" "FEAT-TOOL-003 AC-6 failed ($cppQtRaw)"

    # AC-4, AC-5, AC-7 checks
    $fgRaw = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -Raw -Encoding UTF8
    Assert-Condition ($fgRaw -match '\|qml\|' -and $fgRaw -match 'tst_\.') "FEAT-TOOL-003 AC-4: run-fast-gate.ps1 supports .qml and C++/QML test discovery" "FEAT-TOOL-003 AC-4 failed"
    $ctfRaw = Get-Content -Path (Join-Path $repoRoot "scripts\collect-test-failures.ps1") -Raw -Encoding UTF8
    $covRaw = Get-Content -Path (Join-Path $repoRoot "scripts\check-test-coverage.ps1") -Raw -Encoding UTF8
    Assert-Condition ($ctfRaw -match 'Testing' -and $covRaw -match 'coverage') "FEAT-TOOL-003 AC-5: CTest/QTest XML and coverage.info discovery enabled" "FEAT-TOOL-003 AC-5 failed"
    Assert-Condition (Test-Path (Join-Path $repoRoot "scripts\lint-cpp-qt-contracts.sh")) "FEAT-TOOL-003 AC-7: lint-cpp-qt-contracts.sh parity script exists" "FEAT-TOOL-003 AC-7 failed"
} finally {
    if (Test-Path $tempCppDir) { Remove-Item -LiteralPath $tempCppDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 53. Validate FEAT-TOOL-004 Deterministic Toolchain Gap Detection (AC-1 through AC-5)
Write-Host "`n53. Validating FEAT-TOOL-004 Toolchain Gap Detection..." -ForegroundColor Yellow
$tempGapDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    New-Item -ItemType Directory -Path (Join-Path $tempGapDir "lib") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tempGapDir "lib\main.dart"), "void main() {}`r`n", (New-Object System.Text.UTF8Encoding($false)))

    # AC-1: Unsupported stack emits support_level = unsupported
    $dartStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $tempGapDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($dartStack.stack -eq "unknown" -and $dartStack.language -eq "dart" -and $dartStack.support_level -eq "unsupported") "FEAT-TOOL-004 AC-1: detect-tech-stack.ps1 flags unsupported dart stack" "FEAT-TOOL-004 AC-1 failed: $($dartStack | ConvertTo-Json -Compress)"

    # AC-2: run-fast-gate emits [ToolchainGap] warning on unsupported stack
    $gapGate = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -ProjectRoot $tempGapDir -JsonOutput | ConvertFrom-Json
    Assert-Condition (($gapGate.warnings -join "`n") -match '\[ToolchainGap\]') "FEAT-TOOL-004 AC-2: run-fast-gate.ps1 emits [ToolchainGap] warning for unsupported stack" "FEAT-TOOL-004 AC-2 failed"

    # AC-3: Docs-only repo has support_level = full and zero [ToolchainGap] warnings
    $docsOnlyDir = Join-Path $tempGapDir "docs-only"
    New-Item -ItemType Directory -Path $docsOnlyDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $docsOnlyDir "README.md"), "# Docs`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $docsStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $docsOnlyDir -JsonOutput | ConvertFrom-Json
    $docsGate = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run-fast-gate.ps1") -ProjectRoot $docsOnlyDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($docsStack.support_level -eq "full" -and (($docsGate.warnings -join "`n") -notmatch '\[ToolchainGap\]')) "FEAT-TOOL-004 AC-3: Docs-only repo produces zero [ToolchainGap] warnings" "FEAT-TOOL-004 AC-3 failed"

    # AC-4 & AC-5: Reactive rule & .sh parity
    $ctrlRaw = Get-Content -Path (Join-Path $repoRoot "skills\ask-control\SKILL.md") -Raw -Encoding UTF8
    $fgShRaw = Get-Content -Path (Join-Path $repoRoot "scripts\run-fast-gate.sh") -Raw -Encoding UTF8
    Assert-Condition ($ctrlRaw -match '\[ToolchainGap\]' -and $fgShRaw -match '\[ToolchainGap\]') "FEAT-TOOL-004 AC-4/AC-5: Reactive rule and Bash parity verified" "FEAT-TOOL-004 AC-4/AC-5 failed"
} finally {
    if (Test-Path $tempGapDir) { Remove-Item -LiteralPath $tempGapDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 54. Validate Kotlin Multiplatform (KMP) & Kotlin Desktop Toolchain Support
Write-Host "`n54. Validating Kotlin Multiplatform (KMP) & Kotlin Desktop Toolchain Support..." -ForegroundColor Yellow
$tempKmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    # 54a. KMP with jvm("desktop") (Compose Multiplatform Desktop) must NOT use 'classes' task
    $kmpDesktopDir = Join-Path $tempKmpDir "kmp-desktop"
    New-Item -ItemType Directory -Path (Join-Path $kmpDesktopDir "composeApp\src\commonMain\kotlin\domain") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $kmpDesktopDir "composeApp\src\desktopTest\kotlin") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $kmpDesktopDir "composeApp\build\generated\domain") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $kmpDesktopDir "composeApp\build\reports\kover") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "settings.gradle.kts"), "rootProject.name = `"DesktopApp`"`r`ninclude(`":composeApp`")`r`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "composeApp\build.gradle.kts"), "plugins {`r`n  kotlin(`"multiplatform`")`r`n  id(`"org.jetbrains.compose`")`r`n  id(`"com.diffplug.spotless`")`r`n}`r`nkotlin {`r`n  jvm(`"desktop`")`r`n}`r`n", $utf8NoBom)
    $kmpDesktopStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $kmpDesktopDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpDesktopStack.stack -eq "kmp-gradle" -and $kmpDesktopStack.language -eq "kotlin" -and $kmpDesktopStack.build_cmd -match 'desktopMainClasses desktopTestClasses' -and $kmpDesktopStack.build_cmd -notmatch '\bclasses\b' -and $kmpDesktopStack.test_cmd -match 'desktopTest' -and $kmpDesktopStack.test_filter_syntax -match 'desktopTest --tests \{filter\}') "KMP Desktop (jvm('desktop')) uses desktopMainClasses/desktopTestClasses/desktopTest without nonexistent 'classes' task" "KMP Desktop detection failed: $($kmpDesktopStack | ConvertTo-Json -Compress)"

    # 54b. KMP with default jvm() target
    $kmpJvmDir = Join-Path $tempKmpDir "kmp-jvm"
    New-Item -ItemType Directory -Path $kmpJvmDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $kmpJvmDir "build.gradle.kts"), "plugins {`r`n  id(`"org.jetbrains.kotlin.multiplatform`")`r`n}`r`nkotlin {`r`n  jvm()`r`n}`r`n", $utf8NoBom)
    $kmpJvmStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $kmpJvmDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpJvmStack.stack -eq "kmp-gradle" -and $kmpJvmStack.language -eq "kotlin" -and $kmpJvmStack.build_cmd -match 'jvmMainClasses jvmTestClasses' -and $kmpJvmStack.build_cmd -notmatch '\bclasses\b' -and $kmpJvmStack.test_cmd -match 'jvmTest') "KMP JVM (jvm()) uses jvmMainClasses/jvmTestClasses/jvmTest without nonexistent 'classes' task" "KMP JVM detection failed: $($kmpJvmStack | ConvertTo-Json -Compress)"

    # 54c. KMP with Android + Desktop prefers desktop JVM target without failing on 'classes'
    $kmpHybridDir = Join-Path $tempKmpDir "kmp-hybrid"
    New-Item -ItemType Directory -Path $kmpHybridDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $kmpHybridDir "build.gradle.kts"), "plugins {`r`n  kotlin(`"multiplatform`")`r`n  id(`"com.android.application`")`r`n}`r`nkotlin {`r`n  androidTarget()`r`n  jvm(`"desktop`")`r`n}`r`n", $utf8NoBom)
    $kmpHybridStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $kmpHybridDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpHybridStack.stack -eq "kmp-gradle" -and $kmpHybridStack.build_cmd -match 'desktopMainClasses desktopTestClasses' -and $kmpHybridStack.test_cmd -match 'desktopTest') "KMP Android+Desktop detects kmp-gradle and desktop target tasks" "KMP Android+Desktop detection failed: $($kmpHybridStack | ConvertTo-Json -Compress)"

    # 54d. KMP Native/iOS-only (no JVM/Android) falls back to assemble / allTests (never 'classes')
    $kmpNativeDir = Join-Path $tempKmpDir "kmp-native"
    New-Item -ItemType Directory -Path $kmpNativeDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $kmpNativeDir "build.gradle.kts"), "plugins {`r`n  kotlin(`"multiplatform`")`r`n}`r`nkotlin {`r`n  iosArm64()`r`n}`r`n", $utf8NoBom)
    $kmpNativeStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $kmpNativeDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpNativeStack.stack -eq "kmp-gradle" -and $kmpNativeStack.build_cmd -match '\bassemble\b' -and $kmpNativeStack.build_cmd -notmatch '\bclasses\b' -and $kmpNativeStack.test_cmd -match '\ballTests\b') "KMP Native-only uses assemble and allTests without 'classes'" "KMP Native detection failed: $($kmpNativeStack | ConvertTo-Json -Compress)"

    # 54e. Single-platform Kotlin Desktop (kotlin('jvm') + Compose) retains standard Gradle tasks
    $ktDesktopJvmDir = Join-Path $tempKmpDir "kotlin-desktop-jvm"
    New-Item -ItemType Directory -Path $ktDesktopJvmDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $ktDesktopJvmDir "build.gradle.kts"), "plugins {`r`n  kotlin(`"jvm`")`r`n  id(`"org.jetbrains.compose`")`r`n}`r`n", $utf8NoBom)
    $ktDesktopJvmStack = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\detect-tech-stack.ps1") -ProjectRoot $ktDesktopJvmDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($ktDesktopJvmStack.stack -eq "gradle" -and $ktDesktopJvmStack.language -eq "kotlin" -and $ktDesktopJvmStack.build_cmd -match 'classes testClasses' -and $ktDesktopJvmStack.test_cmd -match '\btest\b') "Single-platform Kotlin Desktop (kotlin('jvm') + Compose) keeps standard classes/testClasses/test tasks" "Single-platform Kotlin Desktop detection failed: $($ktDesktopJvmStack | ConvertTo-Json -Compress)"

    # 54f. Kotlin Multiplatform expect/actual code outline, Clean Arch desktop rules & build/ exclusion, KMP test skip, and Kover XML coverage
    $expectFile = Join-Path $kmpDesktopDir "composeApp\src\commonMain\kotlin\Platform.kt"
    [System.IO.File]::WriteAllText($expectFile, "expect class PlatformDriver`r`nexpect suspend fun loadPlatformName(): String`r`n", $utf8NoBom)
    $kmpOutline = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\get-code-outline.ps1") -Path $expectFile -RepoRoot $kmpDesktopDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpOutline.files.Count -eq 1 -and $kmpOutline.files[0].signatures.Count -ge 2) "get-code-outline.ps1 extracts Kotlin Multiplatform expect/actual declarations" "get-code-outline.ps1 missed expect/actual declarations"

    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "composeApp\build\generated\domain\Gen.kt"), "import javax.swing.JFrame`r`nclass Gen`r`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "composeApp\src\commonMain\kotlin\domain\Model.kt"), "import org.jetbrains.compose.resources.DrawableResource`r`nclass Model`r`n", $utf8NoBom)
    $kmpArchRaw = $null
    try { $kmpArchRaw = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-clean-architecture.ps1") -TargetPath $kmpDesktopDir -JsonOutput 2>$null } catch {}
    $kmpArchObj = if ($kmpArchRaw) { $kmpArchRaw | ConvertFrom-Json } else { $null }
    Assert-Condition ($null -ne $kmpArchObj -and $kmpArchObj.status -eq "fail" -and $kmpArchObj.error_count -eq 1) "lint-clean-architecture.ps1 blocks org.jetbrains.compose in domain/ and ignores generated build/ files" "lint-clean-architecture.ps1 KMP check failed ($kmpArchRaw)"

    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "composeApp\src\desktopTest\kotlin\UiHarness.kt"), "@Composable`r`nfun TestHarness() {}`r`n", $utf8NoBom)
    $kmpContract = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\lint-android-contracts.ps1") -ProjectRoot $kmpDesktopDir -JsonOutput | ConvertFrom-Json
    Assert-Condition ($kmpContract.status -eq "pass" -and $kmpContract.warnings.Count -eq 0) "lint-android-contracts.ps1 skips KMP desktopTest/commonTest source sets" "lint-android-contracts.ps1 did not skip KMP desktopTest ($($kmpContract | ConvertTo-Json -Compress))"

    [System.IO.File]::WriteAllText((Join-Path $kmpDesktopDir "composeApp\build\reports\kover\report.xml"), "<report name=`"kover`"><counter type=`"LINE`" missed=`"10`" covered=`"90`"/></report>`r`n", $utf8NoBom)
    $koverCov = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\check-test-coverage.ps1") -RepoRoot $kmpDesktopDir -Threshold 80 -JsonOutput | ConvertFrom-Json
    Assert-Condition ($koverCov.status -eq "pass" -and $koverCov.format -eq "kover" -and $koverCov.line_coverage_pct -eq 90) "check-test-coverage.ps1 discovers and parses Kover XML reports" "check-test-coverage.ps1 Kover check failed ($($koverCov | ConvertTo-Json -Compress))"
} finally {
    if (Test-Path $tempKmpDir) { Remove-Item -LiteralPath $tempKmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 55. Validating FEAT-CLI-001 Dual-Client CLI Evolution, Current AGY Models, PreToolUse Hooks & Audit Ratchet
Write-Host "`n55. Validating FEAT-CLI-001 Dual-Client CLI Evolution, PreToolUse Hooks & Audit Ratchet..." -ForegroundColor Yellow

# 55a. Audit Ratchet: every scripts/*.ps1 must appear in README.md and match ARCHITECTURE.md count
$allPs1Scripts = @(Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter "*.ps1" -File | ForEach-Object { $_.BaseName })
$readmeText55 = Get-Content -Path (Join-Path $repoRoot "README.md") -Raw -Encoding UTF8
$missingReadmeScripts = @($allPs1Scripts | Where-Object { $readmeText55 -notmatch [regex]::Escape("$_.ps1") })
Assert-Condition ($missingReadmeScripts.Count -eq 0) "README.md documents all $($allPs1Scripts.Count) script pairs" "README.md missing script entries: $($missingReadmeScripts -join ', ')"

$archText55 = Get-Content -Path (Join-Path $repoRoot "ARCHITECTURE.md") -Raw -Encoding UTF8
Assert-Condition ($archText55 -match "\b$($allPs1Scripts.Count)\s+dual-platform script pairs") "ARCHITECTURE.md script count matches actual ($($allPs1Scripts.Count) pairs)" "ARCHITECTURE.md script pair count is out of sync (expected $($allPs1Scripts.Count))"

$ragPs1 = Get-Content -Path (Join-Path $repoRoot "scripts\run-all-gates.ps1") -Raw -Encoding UTF8
$ragSh = Get-Content -Path (Join-Path $repoRoot "scripts\run-all-gates.sh") -Raw -Encoding UTF8
Assert-Condition ($ragPs1 -match 'Requirements Scoped IDs & Non-Duplication' -and $ragSh -match 'Requirements Scoped IDs & Non-Duplication' -and $ragSh -notmatch 'Requirements Scoped IDs & Integrity') "run-all-gates.ps1 and run-all-gates.sh share identical gate names" "run-all-gates gate name drift detected"

# 55b. AC-1: Current AGY 1.5.18 model lineup & Copilot multi-agent parity in model-tiers.json
$mtRaw55 = Get-Content -Path $modelTiersFile -Raw -Encoding UTF8
$mtObj55 = $mtRaw55 | ConvertFrom-Json
$hasCurrentAgyModels = ($mtRaw55 -match 'gemini-4-neon-high' -and $mtRaw55 -match 'gemini-4-carbon-medium' -and $mtRaw55 -match 'gemini-pro-orchestrator-neon' -and $mtRaw55 -notmatch 'gemini-4-pro-high' -and $mtRaw55 -notmatch 'gemini-4-flash-low')
Assert-Condition $hasCurrentAgyModels "model-tiers.json maps live AGY lineup (Neon, Carbon, Orchestrators) without obsolete IDs" "model-tiers.json has outdated AGY model entries"
Assert-Condition ($mtObj55.execution_modes.multi_agent.client_support -contains 'copilot') "model-tiers.json recognizes Copilot CLI subagent/fleet capability" "model-tiers.json missing 'copilot' in multi_agent.client_support"

# 55c. AC-2: Shared PreToolUse Guardrail Hook (Copilot CLI & AGY formats)
$hookPs1Path = Join-Path $repoRoot "scripts\hook-pre-tool-guard.ps1"
$hookShPath = Join-Path $repoRoot "scripts\hook-pre-tool-guard.sh"
$copHookTpl = Join-Path $repoRoot "hooks\copilot-guard.json"
$agyHookTpl = Join-Path $repoRoot "hooks\agy-guard.json"
Assert-Condition ((Test-Path $hookPs1Path) -and (Test-Path $hookShPath) -and (Test-Path $copHookTpl) -and (Test-Path $agyHookTpl)) "PreToolUse hook scripts and JSON templates exist for Copilot CLI and AGY" "Missing hook scripts or templates"

$tempCliDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
try {
    New-Item -ItemType Directory -Path $tempCliDir -Force | Out-Null
    $utf8NoBom55 = New-Object System.Text.UTF8Encoding($false)

    $pForce = Join-Path $tempCliDir "cop-force.json"
    [System.IO.File]::WriteAllText($pForce, '{"toolName":"bash","toolArgs":{"command":"git push --force origin main"}}', $utf8NoBom55)
    $rForce = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPs1Path -PayloadFile $pForce | ConvertFrom-Json
    Assert-Condition ($rForce.permissionDecision -eq 'deny') "hook-pre-tool-guard.ps1 denies Copilot 'git push --force'" "Expected deny for Copilot git push --force"

    $pLease = Join-Path $tempCliDir "cop-lease.json"
    [System.IO.File]::WriteAllText($pLease, '{"toolName":"bash","toolArgs":{"command":"git push --force-with-lease origin feat/test"}}', $utf8NoBom55)
    $rLease = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPs1Path -PayloadFile $pLease | ConvertFrom-Json
    Assert-Condition ($null -eq $rLease.permissionDecision) "hook-pre-tool-guard.ps1 allows Copilot 'git push --force-with-lease'" "Incorrectly blocked --force-with-lease"

    $pSub = Join-Path $tempCliDir "agy-sub.json"
    [System.IO.File]::WriteAllText($pSub, '{"hookEventName":"PreToolUse","toolCall":{"name":"run_command","args":{"CommandLine":"git add _agents/AGENTS.md"}}}', $utf8NoBom55)
    $rSub = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPs1Path -PayloadFile $pSub | ConvertFrom-Json
    Assert-Condition ($rSub.decision -eq 'deny') "hook-pre-tool-guard.ps1 denies AGY submodule staging ('_agents')" "Expected deny for AGY _agents staging"

    $pRust = Join-Path $tempCliDir "agy-rust.json"
    [System.IO.File]::WriteAllText($pRust, '{"hookEventName":"PreToolUse","toolCall":{"name":"edit_file","args":{"Path":"src/lib.rs","Replacement":"unsafe { ptr::read(p) }"}}}', $utf8NoBom55)
    $rRust = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPs1Path -PayloadFile $pRust | ConvertFrom-Json
    Assert-Condition ($rRust.decision -eq 'deny') "hook-pre-tool-guard.ps1 denies Rust 'unsafe' block edits" "Expected deny for Rust unsafe edit"

    $pSafe = Join-Path $tempCliDir "agy-safe.json"
    [System.IO.File]::WriteAllText($pSafe, '{"hookEventName":"PreToolUse","toolCall":{"name":"edit_file","args":{"Path":"src/lib.rs","Replacement":"pub fn add(a: i32, b: i32) -> i32 { a + b }"}}}', $utf8NoBom55)
    $rSafe = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPs1Path -PayloadFile $pSafe | ConvertFrom-Json
    Assert-Condition ($rSafe.decision -eq 'allow') "hook-pre-tool-guard.ps1 allows safe Rust edits" "Expected allow for safe Rust edit"

    # 55d. AC-3: setup-agent-skills -WithHooks, .github/instructions/, and Double-Injection Warning
    $fakeHome55 = Join-Path $tempCliDir "home"
    $fakeProj55 = Join-Path $tempCliDir "proj"
    New-Item -ItemType Directory -Path $fakeHome55, $fakeProj55 -Force | Out-Null

    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\setup-agent-skills.ps1") -Global -WithHooks -UserHome $fakeHome55 -Force | Out-Null
    Assert-Condition ((Test-Path (Join-Path $fakeHome55 ".copilot\hooks\agent-skills-guard.json")) -and (Test-Path (Join-Path $fakeHome55 ".gemini\config\hooks.json"))) "setup-agent-skills.ps1 -Global -WithHooks provisions global Copilot & AGY hooks" "Global -WithHooks failed to create hook files"

    $projOut55 = (& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\setup-agent-skills.ps1") -TargetProject $fakeProj55 -WithHooks -UserHome $fakeHome55 -Force 2>&1) -join "`n"
    Assert-Condition ((Test-Path (Join-Path $fakeProj55 ".github\hooks\agent-skills-guard.json")) -and (Test-Path (Join-Path $fakeProj55 ".agent\hooks.json")) -and (Test-Path (Join-Path $fakeProj55 ".github\instructions\concepts.instructions.md"))) "setup-agent-skills.ps1 -WithHooks provisions project Copilot/AGY hooks and path-specific instructions" "Project -WithHooks missing expected files"
    Assert-Condition ($projOut55 -match 'Double-Injection Notice') "setup-agent-skills.ps1 emits Double-Injection Notice when global Copilot instructions already exist" "Missing Double-Injection Notice on dual global+project Copilot setup"
} finally {
    if (Test-Path $tempCliDir) { Remove-Item -LiteralPath $tempCliDir -Recurse -Force -ErrorAction SilentlyContinue }
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
