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
.PARAMETER Force
    Overwrites existing links or files if they already exist.
.EXAMPLE
    # Integrate into another project
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\projekte\my-app"

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
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$copilotTemplate = Join-Path $repoRoot ".github" "copilot-instructions.md"

function Create-DirectoryLink {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [bool]$Overwrite
    )

    if (Test-Path $LinkPath) {
        if (-not $Overwrite) {
            Write-Host "  [SKIP] Link already exists: $LinkPath (use -Force to overwrite)" -ForegroundColor Yellow
            return
        }
        Write-Host "  [REMOVE] Existing link/directory: $LinkPath" -ForegroundColor DarkGray
        $item = Get-Item -LiteralPath $LinkPath -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $item.Delete()
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

When encountering specialized tasks, load and follow the corresponding guide on demand:
- **Git anomalies & conflicts**: $skillsSlash/ask-git-troubleshooter/SKILL.md
- **Root cause analysis & bugs**: $skillsSlash/ask-troubleshooter/SKILL.md
- **Adversarial code review**: $skillsSlash/ask-code-reviewer/SKILL.md
- **Safe Fowler refactoring**: $skillsSlash/ask-refactoring-specialist/SKILL.md
- **Release & SemVer calculation**: $skillsSlash/ask-release-manager/SKILL.md
- **Security & vulnerability audits**: $skillsSlash/ask-security-auditor/SKILL.md
- **API specifications & contracts**: $skillsSlash/ask-api-contract-specialist/SKILL.md
- **Database migrations & ORM**: $skillsSlash/ask-database-specialist/SKILL.md
- **CI/CD & Docker workflows**: $skillsSlash/ask-devops-engineer/SKILL.md
- **Internationalization (i18n)**: $skillsSlash/ask-localization-specialist/SKILL.md
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

    Write-Host "`nProject Integration Complete!" -ForegroundColor Green
    Write-Host "  - Antigravity: Discovers skills via _agents/skills and rules via _agents/rules" -ForegroundColor White
    Write-Host "  - Copilot: Governed cleanly by .github/copilot-instructions.md (Lite mode)" -ForegroundColor White
}
