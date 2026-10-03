<#
.SYNOPSIS
    Generates or updates CHANGELOG.md deterministically from git commits.
.DESCRIPTION
    Analyzes Conventional Commits between a base tag/commit and HEAD,
    groups changes into Keep-a-Changelog sections, and optionally prepends
    or writes the markdown to CHANGELOG.md.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Version
    Optional version string for the release section (e.g. 'v1.2.0').
    If omitted, attempts to calculate next version or uses '[Unreleased]'.
.PARAMETER ReleaseDate
    Optional date for the release header (defaults to current date YYYY-MM-DD).
.PARAMETER OutputFile
    Optional file path to write or prepend to (e.g. 'CHANGELOG.md').
.PARAMETER Prepend
    If OutputFile exists, prepends the new section rather than overwriting.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/generate-changelog.ps1 -OutputFile CHANGELOG.md -Prepend
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$ReleaseDate,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [switch]$Prepend,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

if (-not $ReleaseDate) {
    $ReleaseDate = (Get-Date).ToString("yyyy-MM-dd")
}

# 1. Determine tag range
$latestTag = (git -C $RepoRoot describe --tags --abbrev=0 2>$null)
if (-not $latestTag) {
    $commits = git -C $RepoRoot log --oneline --no-merges 2>$null
} else {
    $commits = git -C $RepoRoot log "${latestTag}..HEAD" --oneline --no-merges 2>$null
}

$commitLines = if ($commits) { $commits -split "`r?`n" } else { @() }

# 2. Determine version if not provided
if (-not $Version) {
    $semverScript = Join-Path $PSScriptRoot "calculate-semver.ps1"
    if (Test-Path $semverScript) {
        $semverData = pwsh -NoProfile -ExecutionPolicy Bypass -File $semverScript -RepoRoot $RepoRoot -JsonOutput | ConvertFrom-Json
        if ($semverData -and $semverData.next_version) {
            $Version = $semverData.next_version
        }
    }
    if (-not $Version) {
        $Version = "v0.1.0"
    }
}

# 3. Categorize commits
$breaking = [System.Collections.Generic.List[string]]::new()
$features = [System.Collections.Generic.List[string]]::new()
$fixes = [System.Collections.Generic.List[string]]::new()
$performance = [System.Collections.Generic.List[string]]::new()
$refactorings = [System.Collections.Generic.List[string]]::new()
$docs = [System.Collections.Generic.List[string]]::new()
$chores = [System.Collections.Generic.List[string]]::new()

foreach ($c in $commitLines) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    $msg = $c -replace '^[a-f0-9]+\s+', ''

    if ($msg -match '(?i)BREAKING\s+CHANGE|!:') {
        $breaking.Add($msg)
    } elseif ($msg -match '^feat(\([^\)]+\))?:') {
        $clean = $msg -replace '^feat(\([^\)]+\))?:\s*', ''
        $features.Add($clean)
    } elseif ($msg -match '^fix(\([^\)]+\))?:') {
        $clean = $msg -replace '^fix(\([^\)]+\))?:\s*', ''
        $fixes.Add($clean)
    } elseif ($msg -match '^perf(\([^\)]+\))?:') {
        $clean = $msg -replace '^perf(\([^\)]+\))?:\s*', ''
        $performance.Add($clean)
    } elseif ($msg -match '^refactor(\([^\)]+\))?:') {
        $clean = $msg -replace '^refactor(\([^\)]+\))?:\s*', ''
        $refactorings.Add($clean)
    } elseif ($msg -match '^docs(\([^\)]+\))?:') {
        $clean = $msg -replace '^docs(\([^\)]+\))?:\s*', ''
        $docs.Add($clean)
    } else {
        $clean = $msg -replace '^(chore|build|ci|test)(\([^\)]+\))?:\s*', ''
        $chores.Add($clean)
    }
}

# 4. Build Markdown
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("## [$Version] - $ReleaseDate")
[void]$sb.AppendLine()

if ($breaking.Count -gt 0) {
    [void]$sb.AppendLine("### ⚠️ Breaking Changes")
    foreach ($item in $breaking) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($features.Count -gt 0) {
    [void]$sb.AppendLine("### Added")
    foreach ($item in $features) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($fixes.Count -gt 0) {
    [void]$sb.AppendLine("### Fixed")
    foreach ($item in $fixes) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($performance.Count -gt 0) {
    [void]$sb.AppendLine("### Performance")
    foreach ($item in $performance) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($refactorings.Count -gt 0) {
    [void]$sb.AppendLine("### Refactored")
    foreach ($item in $refactorings) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($docs.Count -gt 0) {
    [void]$sb.AppendLine("### Documentation")
    foreach ($item in $docs) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

if ($chores.Count -gt 0) {
    [void]$sb.AppendLine("### Maintenance & Chores")
    foreach ($item in $chores) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine()
}

$sectionMarkdown = $sb.ToString().TrimEnd()

# 5. Handle OutputFile
if ($OutputFile) {
    $outPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $RepoRoot $OutputFile }
    if ((Test-Path $outPath) -and $Prepend) {
        $existingContent = [System.IO.File]::ReadAllText($outPath, [System.Text.Encoding]::UTF8)
        # Check if header exists
        if ($existingContent -match '^#\s+Changelog[^\r\n]*') {
            $header = $Matches[0]
            $rest = $existingContent.Substring($header.Length).TrimStart("`r", "`n")
            $newFull = "$header`n`n$sectionMarkdown`n`n$rest"
        } else {
            $newFull = "$sectionMarkdown`n`n$existingContent"
        }
        [System.IO.File]::WriteAllText($outPath, $newFull.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    } else {
        $fullDoc = "# Changelog`n`nAll notable changes to this project will be documented in this file.`n`n$sectionMarkdown`n"
        [System.IO.File]::WriteAllText($outPath, $fullDoc.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    }
}

if ($JsonOutput) {
    $res = [ordered]@{
        version          = $Version
        release_date     = $ReleaseDate
        commits_analyzed = $commitLines.Count
        breaking_count   = $breaking.Count
        features_count   = $features.Count
        fixes_count      = $fixes.Count
        markdown         = $sectionMarkdown
    }
    $res | ConvertTo-Json -Depth 5
} else {
    Write-Host $sectionMarkdown
}
