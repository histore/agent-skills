<#
.SYNOPSIS
    Automated validator and test suite for agent-skills repository.
.DESCRIPTION
    Validates skill integrity, YAML frontmatter, model tier mappings,
    detects ghost/orphan roles, and asserts LF line endings.
.EXAMPLE
    pwsh -File ./scripts/test-skills.ps1
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
        Assert-Condition ($registeredRoles.Count -eq 22) "All 22 roles are registered in model-tiers.json (Found $($registeredRoles.Count))" "Expected 22 roles in model-tiers.json, but found $($registeredRoles.Count)"
    } catch {
        Assert-Condition $false "model-tiers.json parses as valid JSON" "Failed to parse model-tiers.json: $_"
    }
}

# 2. Validate all 22 skills in skills/ directory
Write-Host "`n2. Validating skills directory structure and frontmatter..." -ForegroundColor Yellow
$skillDirs = Get-ChildItem -Path $skillsDir -Directory | Sort-Object Name
Assert-Condition ($skillDirs.Count -eq 22) "Exactly 22 skill directories found in skills/ (Found $($skillDirs.Count))" "Expected 22 skill directories, but found $($skillDirs.Count)"

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
