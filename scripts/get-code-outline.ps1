#Requires -Version 5.1
<#
.SYNOPSIS
    Deterministic code outline and AST signature extractor.
.DESCRIPTION
    Extracts structural declarations (classes, interfaces, structs, traits, enums, functions,
    and method signatures) from source files with zero token overhead.
    Filters out method bodies and internal implementation noise, allowing agents to inspect
    code architecture, interfaces, and contracts without loading large source files into LLM context.
.PARAMETER Path
    Path to a source file or directory. Defaults to current directory.
.PARAMETER Recurse
    Recursively inspect subdirectories. Defaults to true.
.PARAMETER JsonOutput
    Output results as structured JSON.
.PARAMETER RepoRoot
    Project repository root for relative path rendering.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/get-code-outline.ps1 -Path ./src
    pwsh -NoProfile -File ./scripts/get-code-outline.ps1 -Path ./src/Domain/IOrderRepository.cs
    pwsh -NoProfile -File ./scripts/get-code-outline.ps1 -Path ./src -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Path = ".",

    [Parameter(Mandatory = $false)]
    [switch]$Recurse = $true,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Determine Repository Root
if (-not $RepoRoot) {
    $superproject = git rev-parse --show-superproject-working-tree 2>$null
    if ($superproject) { $RepoRoot = $superproject.Trim() }
    else {
        $toplevel = git rev-parse --show-toplevel 2>$null
        if ($toplevel) {
            $root = $toplevel.Trim()
            if ($root -match '[\\/](_agents|\.agents)$') { $root = Split-Path -Parent $root }
            $RepoRoot = $root
        } else {
            $RepoRoot = (Get-Location).Path
        }
    }
}

$targetPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }
if (-not (Test-Path $targetPath)) {
    if ($JsonOutput) {
        [PSCustomObject]@{ status = "error"; message = "Path not found: $Path"; files = @() } | ConvertTo-Json -Depth 3 -Compress
    } else {
        Write-Error "Path not found: $Path"
    }
    exit 1
}

# 2. Collect Candidate Files
$supportedExts = @('.cs', '.rs', '.ts', '.tsx', '.js', '.py', '.go')
$filesToScan = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

if ((Get-Item $targetPath) -is [System.IO.FileInfo]) {
    $filesToScan.Add((Get-Item $targetPath))
} else {
    $searchOpt = if ($Recurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
    $items = [System.IO.Directory]::GetFiles($targetPath, "*.*", $searchOpt)
    foreach ($item in $items) {
        $ext = [System.IO.Path]::GetExtension($item).ToLowerInvariant()
        if ($ext -notin $supportedExts) { continue }
        # Exclude vendor, build, and agent directories
        if ($item -match '[\\/](\.git|_agents|\.agents|node_modules|bin|obj|target|\.vs|\.pytest_cache)[\\/]') { continue }
        $filesToScan.Add((New-Object System.IO.FileInfo($item)))
    }
}

# 3. Parse Signatures by Language
function Parse-Signatures {
    param([System.IO.FileInfo]$File)
    
    $ext = $File.Extension.ToLowerInvariant()
    $lang = switch ($ext) {
        '.cs'   { 'csharp' }
        '.rs'   { 'rust' }
        '.ts'   { 'typescript' }
        '.tsx'  { 'typescript' }
        '.js'   { 'javascript' }
        '.py'   { 'python' }
        '.go'   { 'go' }
        default { 'unknown' }
    }

    $lines = [System.IO.File]::ReadAllLines($File.FullName, [System.Text.Encoding]::UTF8)
    $signatures = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNum = $i + 1
        $rawLine = $lines[$i]
        $trimmed = $rawLine.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith("//") -or $trimmed.StartsWith("#") -or $trimmed.StartsWith("/*") -or $trimmed.StartsWith("*")) { continue }

        $kind = $null
        $sig = $null
        $vis = "internal"

        switch ($lang) {
            'csharp' {
                if ($trimmed -match '^(public|internal|protected|private)?\s*(static|abstract|sealed|virtual|override)?\s*(interface|class|record|struct|enum)\s+([A-Za-z0-9_<>]+)') {
                    $kind = $matches[3]
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { $matches[1] } else { "internal" }
                } elseif ($trimmed -match '^(public|protected|internal)\s+.*?\s+([A-Za-z0-9_<>]+)\s*\(' -and $trimmed -notmatch '\b(if|while|for|switch|catch)\b') {
                    $kind = "method"
                    $sig = $trimmed.TrimEnd('{', ';').Trim()
                    $vis = $matches[1]
                }
            }
            'rust' {
                if ($trimmed -match '^(pub(\([a-z\s_]+\))?)?\s*(struct|enum|trait|type|union)\s+([A-Za-z0-9_]+)') {
                    $kind = $matches[3]
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { $matches[1] } else { "private" }
                } elseif ($trimmed -match '^(pub(\([a-z\s_]+\))?)?\s*(async\s+)?(const\s+)?fn\s+([A-Za-z0-9_]+)') {
                    $kind = "fn"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { $matches[1] } else { "private" }
                } elseif ($trimmed -match '^impl(<.*?>)?\s+([A-Za-z0-9_<>]+)') {
                    $kind = "impl"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = "pub"
                }
            }
            'typescript' {
                if ($trimmed -match '^(export\s+)?(default\s+)?(interface|type|class|enum)\s+([A-Za-z0-9_<>]+)') {
                    $kind = $matches[3]
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { "export" } else { "local" }
                } elseif ($trimmed -match '^(export\s+)?(async\s+)?function\s+([A-Za-z0-9_<>]+)') {
                    $kind = "function"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { "export" } else { "local" }
                }
            }
            'javascript' {
                if ($trimmed -match '^(export\s+)?(class)\s+([A-Za-z0-9_]+)') {
                    $kind = "class"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { "export" } else { "local" }
                } elseif ($trimmed -match '^(export\s+)?(async\s+)?function\s+([A-Za-z0-9_]+)') {
                    $kind = "function"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1]) { "export" } else { "local" }
                }
            }
            'python' {
                if ($trimmed -match '^(class)\s+([A-Za-z0-9_]+)') {
                    $kind = "class"
                    $sig = $trimmed.TrimEnd(':').Trim()
                    $vis = if ($matches[2].StartsWith("_")) { "private" } else { "public" }
                } elseif ($trimmed -match '^(async\s+)?def\s+([A-Za-z0-9_]+)\s*\(') {
                    $kind = "def"
                    $sig = $trimmed.TrimEnd(':').Trim()
                    $vis = if ($matches[2].StartsWith("_")) { "private" } else { "public" }
                }
            }
            'go' {
                if ($trimmed -match '^type\s+([A-Za-z0-9_]+)\s+(struct|interface)') {
                    $kind = $matches[2]
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $vis = if ($matches[1] -cmatch '^[A-Z]') { "exported" } else { "package" }
                } elseif ($trimmed -match '^func\s+(\([A-Za-z0-9_\*\s]+\)\s+)?([A-Za-z0-9_]+)\s*\(') {
                    $kind = "func"
                    $sig = $trimmed.TrimEnd('{').Trim()
                    $funcName = if ($matches[2]) { $matches[2] } else { $matches[1] }
                    $vis = if ($funcName -cmatch '^[A-Z]') { "exported" } else { "package" }
                }
            }
        }

        if ($kind -and $sig) {
            $signatures.Add([PSCustomObject]@{
                line = $lineNum
                kind = $kind
                visibility = $vis
                signature = $sig
            })
        }
    }

    $relPath = $File.FullName
    if ($relPath.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relPath = $relPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    }
    $relPath = $relPath.Replace('\', '/')

    return [PSCustomObject]@{
        file = $relPath
        language = $lang
        signatures_count = $signatures.Count
        signatures = $signatures.ToArray()
    }
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($file in $filesToScan) {
    $parsed = Parse-Signatures -File $file
    if ($parsed.signatures.Count -gt 0) {
        $results.Add($parsed)
    }
}

# 4. Output Formatter
if ($JsonOutput) {
    [PSCustomObject]@{
        status = "pass"
        total_files = $results.Count
        files = $results.ToArray()
    } | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Code Outline & Structural AST Inspector" -ForegroundColor Cyan
    Write-Host "Files: $($results.Count) scanned under $Path" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan

    if ($results.Count -eq 0) {
        Write-Host "No public types or method signatures discovered." -ForegroundColor Yellow
    } else {
        foreach ($r in $results) {
            Write-Host "`n[$($r.language)] $($r.file)" -ForegroundColor Green
            foreach ($s in $r.signatures) {
                $kindTag = "[$($s.kind)]".PadRight(11)
                Write-Host "  L$($s.line.ToString().PadRight(4)) $kindTag $($s.signature)" -ForegroundColor White
            }
        }
    }
    Write-Host "`n=============================================" -ForegroundColor Cyan
}

exit 0
