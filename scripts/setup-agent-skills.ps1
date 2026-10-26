<#
.SYNOPSIS
    Sets up agent-skills in a target project or globally in the user configuration.
.DESCRIPTION
    Integrates agent-skills for Google Antigravity / Gemini and GitHub Copilot:
    - Project Mode: Creates _agents (or .agents) junction/link and provisions .github/copilot-instructions.md
    - Global Mode: Links skills and rules into ~/.gemini/config and sets up global copilot-instructions.md
.PARAMETER TargetProject
    Path to the target project directory. Defaults to current directory if not in agent-skills repo.
.PARAMETER FolderType
    Name of the directory link: '_agents' (default), '.agents', or 'both'.
.PARAMETER Global
    Configures agent-skills globally in the user's home directory (~/.gemini/config).
.PARAMETER SkipCopilot
    Skips creating or updating .github/copilot-instructions.md in the target project.
.PARAMETER InitDocs
    Scaffolds initial living documentation (ARCHITECTURE.md, docs/ROADMAP.md, docs/features/, docs/concepts/drafts/) in the target project if not present.
.PARAMETER Force
    Overwrites existing links or files if they already exist.
.EXAMPLE
    # Integrate into another project and bootstrap living docs
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\projekte\my-app" -InitDocs

.EXAMPLE
    # Install globally for all projects
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetProject,

    [Parameter(Mandatory = $false)]
    [ValidateSet('_agents', '.agents', 'both')]
    [string]$FolderType = '_agents',

    [Parameter(Mandatory = $false)]
    [switch]$Global,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCopilot,

    [Parameter(Mandatory = $false)]
    [switch]$InitDocs,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$rawRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoItem = Get-Item -LiteralPath $rawRepoRoot -Force
if (($repoItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $repoItem.Target) {
    $targetCandidate = if ($repoItem.Target -is [array]) { $repoItem.Target[0] } else { $repoItem.Target }
    if (Test-Path $targetCandidate) {
        $rawRepoRoot = (Resolve-Path $targetCandidate).Path
    }
}
$repoRoot = $rawRepoRoot.TrimEnd('\', '/')
$copilotTemplate = Join-Path $repoRoot ".github\copilot-instructions.md"

function Create-DirectoryLink {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [bool]$Overwrite
    )

    if ($LinkPath.TrimEnd('\', '/') -ieq $TargetPath.TrimEnd('\', '/')) {
        Write-Host "  [OK] Path is already the source repository: $LinkPath" -ForegroundColor Green
        return
    }

    if (Test-Path $LinkPath) {
        $existingItem = Get-Item -LiteralPath $LinkPath -Force
        if (($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $existingItem.Target) {
            $existingTarget = if ($existingItem.Target -is [array]) { $existingItem.Target[0] } else { $existingItem.Target }
            if ($existingTarget.TrimEnd('\', '/') -ieq $TargetPath.TrimEnd('\', '/')) {
                Write-Host "  [OK] Link already points to target: $LinkPath -> $TargetPath" -ForegroundColor Green
                return
            }
        }
        if (-not $Overwrite) {
            Write-Host "  [SKIP] Link already exists: $LinkPath (use -Force to overwrite)" -ForegroundColor Yellow
            return
        }
        Write-Host "  [REMOVE] Existing link/directory: $LinkPath" -ForegroundColor DarkGray
        if ($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $existingItem.Delete()
        } else {
            Remove-Item -LiteralPath $LinkPath -Recurse -Force
        }
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force | Out-Null
        Write-Host "  [OK] Created Junction: $LinkPath -> $TargetPath" -ForegroundColor Green
    } catch {
        # Fallback to symbolic link if junction fails
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force | Out-Null
        Write-Host "  [OK] Created SymbolicLink: $LinkPath -> $TargetPath" -ForegroundColor Green
    }
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Agent Skills Setup & Integration Helper" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($Global) {
    $geminiConfigDir = Join-Path $HOME ".gemini" "config"
    Write-Host "`nConfiguring Global User Mode in: $geminiConfigDir" -ForegroundColor Yellow

    if (-not (Test-Path $geminiConfigDir)) {
        New-Item -ItemType Directory -Path $geminiConfigDir -Force | Out-Null
    }

    # 1. Link skills and rules
    $skillsTarget = Join-Path $repoRoot "skills"
    $rulesTarget = Join-Path $repoRoot "rules"
    $globalSkills = Join-Path $geminiConfigDir "skills"
    $globalRules = Join-Path $geminiConfigDir "rules"

    Create-DirectoryLink -LinkPath $globalSkills -TargetPath $skillsTarget -Overwrite $Force
    Create-DirectoryLink -LinkPath $globalRules -TargetPath $rulesTarget -Overwrite $Force

    # 2. Setup GitHub Copilot Personal Mode (~/.agents and ~/.copilot/instructions)
    $agentsDir = Join-Path $HOME ".agents"
    Create-DirectoryLink -LinkPath $agentsDir -TargetPath $repoRoot -Overwrite $Force

    $copilotInstructionsDir = Join-Path $HOME ".copilot" "instructions"
    if (-not (Test-Path $copilotInstructionsDir)) {
        New-Item -ItemType Directory -Path $copilotInstructionsDir -Force | Out-Null
    }

    # 3. Generate reference instruction file with YAML frontmatter (applyTo: "**/*")
    $userInstructionsFile = Join-Path $copilotInstructionsDir "agent-skills.instructions.md"
    $templateSlash = $copilotTemplate.Replace('\', '/')
    $skillsSlash = $skillsTarget.Replace('\', '/')

    $instructionContent = @"
---
applyTo: "**/*"
description: "Universal Clean Code, Clean Architecture, and on-demand agent skills"
---

# Personal Agent Skills & Engineering Guidelines

Adhere to the core engineering invariants (Clean Code, Clean Architecture, Safe Rust without unsafe, Inner-Loop TDD, Anti-Ceremony).

## Base Instructions
The baseline rules are defined in:
- $templateSlash

## Central Skills & Tooling Source
All specialist skills and zero-token automation scripts are located in:
- Skills Root Directory: $skillsSlash
- Also accessible via personal skills: ~/.agents/skills/ or ~/.copilot/skills/

When encountering specialized tasks requiring deep domain expertise, consult the corresponding capability pack on demand:
- **Diagnostics, bug RCA, code review, refactoring & profiling**: $skillsSlash/ask-troubleshooter/SKILL.md
- **Git anomalies, merge/rebase conflicts & recovery (Zero Data Loss)**: $skillsSlash/ask-git-troubleshooter/SKILL.md
- **Contracts, living specs, API contracts, DB migrations, UI/UX tokens, a11y & i18n**: $skillsSlash/ask-contract-specialist/SKILL.md
- **Release management, CI/CD, SemVer calculation & security audits**: $skillsSlash/ask-release-manager/SKILL.md
"@

    [System.IO.File]::WriteAllText($userInstructionsFile, ($instructionContent -replace "`r?`n", "`n"), [System.Text.Encoding]::UTF8)
    Write-Host "  [OK] Generated Copilot user instructions: $userInstructionsFile" -ForegroundColor Green

    Write-Host "`nAntigravity / Gemini Setup:" -ForegroundColor Cyan
    Write-Host "  All skills and rules are now automatically active across all projects via ~/.gemini/config." -ForegroundColor White

    Write-Host "`nGitHub Copilot CLI Setup:" -ForegroundColor Cyan
    Write-Host "  - Instructions: Auto-discovered from ~/.copilot/instructions/agent-skills.instructions.md" -ForegroundColor White
    Write-Host "  - Skills: Auto-discovered from ~/.agents/skills and ~/.copilot/skills" -ForegroundColor White
    Write-Host "  - Verification commands: 'copilot instruction list' and 'copilot skill list'" -ForegroundColor White

    Write-Host "`nGitHub Copilot (VS Code User Settings):" -ForegroundColor Cyan
    Write-Host "  Add the following to your VS Code settings.json:" -ForegroundColor White
    Write-Host @"
  "github.copilot.chat.codeGeneration.instructions": [
    {
      "file": "$($userInstructionsFile.Replace('\', '/'))"
    }
  ]
"@ -ForegroundColor Gray

} else {
    if (-not $TargetProject) {
        $currentDir = (Get-Location).Path
        if ($currentDir -eq $repoRoot) {
            Write-Error "Please specify a -TargetProject directory or use -Global to install globally."
            return
        }
        $TargetProject = $currentDir
    }

    $targetFullPath = (Resolve-Path $TargetProject).Path
    Write-Host "`nIntegrating into Project: $targetFullPath" -ForegroundColor Yellow

    # 1. Create _agents / .agents directory link
    $folderNames = @()
    if ($FolderType -eq '_agents' -or $FolderType -eq 'both') { $folderNames += '_agents' }
    if ($FolderType -eq '.agents' -or $FolderType -eq 'both') { $folderNames += '.agents' }

    foreach ($name in $folderNames) {
        $linkPath = Join-Path $targetFullPath $name
        Create-DirectoryLink -LinkPath $linkPath -TargetPath $repoRoot -Overwrite $Force
    }

    # 2. Setup .github/copilot-instructions.md
    if (-not $SkipCopilot) {
        $githubDir = Join-Path $targetFullPath ".github"
        if (-not (Test-Path $githubDir)) {
            New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
        }

        $destCopilot = Join-Path $githubDir "copilot-instructions.md"
        if ((Test-Path $destCopilot) -and (-not $Force)) {
            Write-Host "  [SKIP] .github/copilot-instructions.md already exists (use -Force to overwrite)" -ForegroundColor Yellow
        } else {
            Copy-Item -LiteralPath $copilotTemplate -Destination $destCopilot -Force
            Write-Host "  [OK] Provisioned $destCopilot (Lite Copilot instructions)" -ForegroundColor Green
        }
    }

    # 3. Optional: Bootstrap Living Modular Documentation (-InitDocs)
    if ($InitDocs) {
        Write-Host "`nBootstrapping Living Modular Documentation in Target Project..." -ForegroundColor Yellow
        $projectName = Split-Path -Leaf $targetFullPath
        $dateStr = (Get-Date).ToString("yyyy-MM-dd")
        $detectedStacks = "Auto-detected"
        $detectScript = Join-Path $PSScriptRoot "detect-tech-stack.ps1"
        if (Test-Path $detectScript) {
            try {
                $stackInfo = pwsh -NoProfile -ExecutionPolicy Bypass -File $detectScript -ProjectRoot $targetFullPath -JsonOutput | ConvertFrom-Json
                if ($stackInfo.stack -and $stackInfo.stack -ne "unknown") {
                    $detectedStacks = "$($stackInfo.stack) ($($stackInfo.language))"
                }
            } catch { }
        }

        foreach ($subDir in @("docs\features", "docs\concepts\drafts", "docs\concepts\archive", "docs\architecture\modules")) {
            $fullSubDir = Join-Path $targetFullPath $subDir
            if (-not (Test-Path $fullSubDir)) {
                New-Item -ItemType Directory -Path $fullSubDir -Force | Out-Null
                Write-Host "  [OK] Created directory: $subDir" -ForegroundColor Green
            }
        }

        $archFile = Join-Path $targetFullPath "ARCHITECTURE.md"
        if ((Test-Path $archFile) -and (-not $Force)) {
            Write-Host "  [SKIP] ARCHITECTURE.md already exists" -ForegroundColor Yellow
        } else {
            $archContent = @"
# System Architecture Baseline: $projectName

> **Status**: APPROVED  
> **Last Synchronized**: $dateStr  
> **Detected Tech Stack**: $detectedStacks  

## 1. Clean Architecture & Layer Boundaries

Dependencies point strictly inward:
- **Domain Layer**: Entities, Value Objects, Domain Invariants (zero external framework dependencies).
- **Application Layer**: Use Cases, Service Contracts, DTOs, Port Interfaces.
- **Adapters / Presentation Layer**: Controllers, ViewModels, Presenters, Persistence Mappers.
- **Infrastructure / Drivers Layer**: UI Frameworks, Database Providers, External APIs, CLI/OS Drivers.

## 2. Modular Specifications
- Living Feature Specifications: [docs/ROADMAP.md](docs/ROADMAP.md)
- Module Architecture Specs: ``docs/architecture/modules/``
"@
            [System.IO.File]::WriteAllText($archFile, ($archContent -replace "`r?`n", "`n"), [System.Text.Encoding]::UTF8)
            Write-Host "  [OK] Scaffolded ARCHITECTURE.md (Stack: $detectedStacks)" -ForegroundColor Green
        }

        $roadmapFile = Join-Path $targetFullPath "docs\ROADMAP.md"
        if ((Test-Path $roadmapFile) -and (-not $Force)) {
            Write-Host "  [SKIP] docs/ROADMAP.md already exists" -ForegroundColor Yellow
        } else {
            $roadmapContent = @"
# Project Roadmap & Living Feature Index (``docs/ROADMAP.md``)

> **System Baseline**: $projectName  
> **Architecture Specification**: [ARCHITECTURE.md](../ARCHITECTURE.md)  

---

## 1. Feature Registry & Lifecycle Tracker

| Phase | Feature ID | Title | Status | Scope | Specification File | Target Release |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
"@
            [System.IO.File]::WriteAllText($roadmapFile, ($roadmapContent -replace "`r?`n", "`n"), [System.Text.Encoding]::UTF8)
            Write-Host "  [OK] Scaffolded docs/ROADMAP.md" -ForegroundColor Green
        }
    }

    Write-Host "`nProject Integration Complete!" -ForegroundColor Green
    Write-Host "  - Antigravity: Discovers skills via _agents/skills and rules via _agents/rules" -ForegroundColor White
    Write-Host "  - Copilot: Governed cleanly by .github/copilot-instructions.md (Lite mode)" -ForegroundColor White
}
