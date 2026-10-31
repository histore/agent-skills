<#
.SYNOPSIS
    Sets up agent-skills in a target project or globally in the user configuration.
.DESCRIPTION
    Integrates agent-skills with strict client directory conventions:
    - Google Antigravity (AGY): '_agents' (User Level: ~/_agents + ~/.gemini/config; Project Level: <project>/_agents)
    - GitHub Copilot (CLI & VS Code): '.agents' (User Level: ~/.agents + inlined ~/.copilot/instructions/; Project Level: <project>/.agents + .github/copilot-instructions.md)
.PARAMETER TargetProject
    Path to the target project directory. Defaults to current directory if not in agent-skills repo.
.PARAMETER Client
    Target AI assistant to configure: 'all' (default: both AGY and Copilot), 'agy' (_agents only), or 'copilot' (.agents only).
.PARAMETER FolderType
    Explicit override for project directory link name: '_agents', '.agents', or 'both'. When omitted, derived automatically from -Client / -SkipCopilot.
.PARAMETER Global
    Configures agent-skills globally in the user's home directory (~/_agents for AGY, ~/.agents for Copilot).
.PARAMETER SkipCopilot
    Skips Copilot integration (.agents and .github/copilot-instructions.md), configuring AGY (_agents) only.
.PARAMETER InitDocs
    Scaffolds initial living documentation (ARCHITECTURE.md, docs/ROADMAP.md, docs/features/, docs/concepts/drafts/) in the target project if not present.
.PARAMETER Force
    Overwrites existing links or files if they already exist.
.EXAMPLE
    # Integrate both AGY (_agents) and Copilot (.agents) into a target project
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\projekte\my-app" -InitDocs

.EXAMPLE
    # Integrate Copilot only (.agents + .github/copilot-instructions.md)
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\projekte\my-app" -Client copilot

.EXAMPLE
    # Install globally for AGY (~/_agents) and Copilot (~/.agents)
    pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetProject,

    [Parameter(Mandatory = $false)]
    [ValidateSet('all', 'agy', 'copilot')]
    [string]$Client = 'all',

    [Parameter(Mandatory = $false)]
    [ValidateSet('_agents', '.agents', 'both')]
    [string]$FolderType,

    [Parameter(Mandatory = $false)]
    [switch]$Global,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCopilot,

    [Parameter(Mandatory = $false)]
    [switch]$InitDocs,

    [Parameter(Mandatory = $false)]
    [string]$UserHome,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$effectiveHome = if ($UserHome) { $UserHome } else { $HOME }

$setupAgy = ($Client -eq 'all' -or $Client -eq 'agy')
$setupCopilot = ($Client -eq 'all' -or $Client -eq 'copilot') -and (-not $SkipCopilot)

if ($PSBoundParameters.ContainsKey('FolderType')) {
    if ($FolderType -eq '_agents') {
        $setupAgy = $true
        if ($SkipCopilot) { $setupCopilot = $false }
    } elseif ($FolderType -eq '.agents') {
        if (-not $PSBoundParameters.ContainsKey('Client')) { $setupAgy = $false }
        $setupCopilot = (-not $SkipCopilot)
    } else {
        $setupAgy = $true
        $setupCopilot = (-not $SkipCopilot)
    }
} else {
    $FolderType = if ($setupAgy -and $setupCopilot) { 'both' } elseif ($setupCopilot) { '.agents' } else { '_agents' }
}

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
    Write-Host "`nConfiguring Global User Mode (Home: $effectiveHome, Client: $Client)" -ForegroundColor Yellow

    if ($setupAgy) {
        # 1. Antigravity (AGY) User Level via ~/_agents + ~/.gemini/config
        $agyUserDir = Join-Path $effectiveHome "_agents"
        Create-DirectoryLink -LinkPath $agyUserDir -TargetPath $repoRoot -Overwrite $Force

        $geminiConfigDir = Join-Path $effectiveHome ".gemini" "config"
        if (-not (Test-Path $geminiConfigDir)) {
            New-Item -ItemType Directory -Path $geminiConfigDir -Force | Out-Null
        }

        $globalSkills = Join-Path $geminiConfigDir "skills"
        $globalRules = Join-Path $geminiConfigDir "rules"
        Create-DirectoryLink -LinkPath $globalSkills -TargetPath (Join-Path $agyUserDir "skills") -Overwrite $Force
        Create-DirectoryLink -LinkPath $globalRules -TargetPath (Join-Path $agyUserDir "rules") -Overwrite $Force

        Write-Host "`nAntigravity / Gemini Setup (~/_agents):" -ForegroundColor Cyan
        Write-Host "  - User Root: $agyUserDir" -ForegroundColor White
        Write-Host "  - Auto-Discovery: ~/.gemini/config/skills & ~/.gemini/config/rules -> ~/_agents" -ForegroundColor White
    }

    if ($setupCopilot) {
        # 2. GitHub Copilot User Level via ~/.agents + inlined ~/.copilot/instructions/
        $copilotAgentsDir = Join-Path $effectiveHome ".agents"
        Create-DirectoryLink -LinkPath $copilotAgentsDir -TargetPath $repoRoot -Overwrite $Force

        $copilotInstructionsDir = Join-Path $effectiveHome ".copilot" "instructions"
        if (-not (Test-Path $copilotInstructionsDir)) {
            New-Item -ItemType Directory -Path $copilotInstructionsDir -Force | Out-Null
        }

        $userInstructionsFile = Join-Path $copilotInstructionsDir "agent-skills.instructions.md"
        $copilotAgentsSlash = $copilotAgentsDir.Replace('\', '/')
        $baseInstructions = Get-Content -LiteralPath $copilotTemplate -Raw -Encoding UTF8
        #Adapt project-relative ./.agents/ and .agents/ paths to also resolve cleanly from user-level ~/.agents/
        $inlinedBody = $baseInstructions.
            Replace('./.agents/scripts/', "$copilotAgentsSlash/scripts/").
            Replace('`.agents/skills/', ('`' + $copilotAgentsSlash + '/skills/')).
            Replace('`.agents/docs/', ('`' + $copilotAgentsSlash + '/docs/'))

        $instructionContent = @"
---
applyTo: "**/*"
description: "Universal Clean Code, Clean Architecture, and Zero-Reload Copilot instructions (.agents)"
---

$inlinedBody
"@

        [System.IO.File]::WriteAllText($userInstructionsFile, ($instructionContent -replace "`r?`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  [OK] Generated Zero-Reload Copilot user instructions (inlined via .agents): $userInstructionsFile" -ForegroundColor Green

        Write-Host "`nGitHub Copilot CLI Setup (~/.agents):" -ForegroundColor Cyan
        Write-Host "  - User Root: $copilotAgentsDir" -ForegroundColor White
        Write-Host "  - Instructions (Zero-Reload inlined): ~/.copilot/instructions/agent-skills.instructions.md" -ForegroundColor White
        Write-Host "  - Skills: Auto-discovered from ~/.agents/skills" -ForegroundColor White
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
    }

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
    Write-Host "`nIntegrating into Project: $targetFullPath (Client: $Client, Links: $FolderType)" -ForegroundColor Yellow

    # 1. Create _agents (AGY) and/or .agents (Copilot) directory links
    $folderNames = @()
    if ($FolderType -eq '_agents' -or $FolderType -eq 'both') { $folderNames += '_agents' }
    if ($FolderType -eq '.agents' -or $FolderType -eq 'both') { $folderNames += '.agents' }

    foreach ($name in $folderNames) {
        $linkPath = Join-Path $targetFullPath $name
        Create-DirectoryLink -LinkPath $linkPath -TargetPath $repoRoot -Overwrite $Force
    }

    # 2. Setup .github/copilot-instructions.md (assumes .agents/)
    if ($setupCopilot) {
        $githubDir = Join-Path $targetFullPath ".github"
        if (-not (Test-Path $githubDir)) {
            New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
        }

        $destCopilot = Join-Path $githubDir "copilot-instructions.md"
        if ((Test-Path $destCopilot) -and (-not $Force)) {
            Write-Host "  [SKIP] .github/copilot-instructions.md already exists (use -Force to overwrite)" -ForegroundColor Yellow
        } else {
            Copy-Item -LiteralPath $copilotTemplate -Destination $destCopilot -Force
            Write-Host "  [OK] Provisioned $destCopilot (configured for .agents/)" -ForegroundColor Green
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
    if ($FolderType -eq '_agents' -or $FolderType -eq 'both') {
        Write-Host "  - Antigravity (AGY): Discovers skills via _agents/skills and rules via _agents/rules" -ForegroundColor White
    }
    if ($FolderType -eq '.agents' -or $FolderType -eq 'both') {
        Write-Host "  - GitHub Copilot: Discovers skills via .agents/skills and instructions via .github/copilot-instructions.md" -ForegroundColor White
    }
}
