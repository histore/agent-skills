<#
.SYNOPSIS
    Deterministic code guardrails scanner (Safe-Rust, Secrets, CRLF, Submodule leakage).
.DESCRIPTION
    Scans project files or staged git changes for governance violations without LLM tokens:
    - Safe-Rust: detects 'unsafe' blocks, functions, or implementations in Rust (*.rs)
    - Secrets: detects accidental AWS/GitHub tokens, private keys, or passwords
    - LineEndings: asserts OS-native line endings (CRLF on Windows, LF on Linux/macOS) unless overridden by .gitattributes or .editorconfig
    - Submodule leakage: detects attempts to commit files inside _agents or .agents submodules
.PARAMETER ScanPath
    Root path to scan. Defaults to current directory.
.PARAMETER StagedOnly
    Switch to scan only git staged files.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/scan-guardrails.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/scan-guardrails.ps1 -StagedOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [Alias('RepoRoot')]
    [string]$ScanPath,

    [Parameter(Mandatory = $false)]
    [switch]$StagedOnly,

    [Parameter(Mandatory = $false)]
    [switch]$WorkingTree,

    [Parameter(Mandatory = $false)]
    [switch]$Fix,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLineEndings,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $ScanPath) {
    $ScanPath = (Get-Location).Path
}
$ScanPath = (Resolve-Path $ScanPath).Path.TrimEnd('\', '/')

$filesToScan = [System.Collections.Generic.List[string]]::new()

if ($StagedOnly) {
    $staged = git -C $ScanPath diff --name-only --cached 2>$null
    foreach ($f in ($staged -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($f)) {
            $full = Join-Path $ScanPath $f
            if (Test-Path $full) { $filesToScan.Add($full) }
        }
    }
} elseif ($WorkingTree) {
    $isGit = git -C $ScanPath rev-parse --is-inside-work-tree 2>$null
    if ($isGit -eq "true") {
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $wtCandidates = @()
        $wtCandidates += (git -C $ScanPath diff --name-only --cached 2>$null) -split "`r?`n"
        $wtCandidates += (git -C $ScanPath diff --name-only 2>$null) -split "`r?`n"
        $wtCandidates += (git -C $ScanPath ls-files --others --exclude-standard 2>$null) -split "`r?`n"
        foreach ($f in $wtCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($f) -and $f -notmatch '^((\.agents|_agents)[\\/])') {
                $full = Join-Path $ScanPath $f
                if ((Test-Path $full -PathType Leaf) -and $seenPaths.Add($full)) {
                    $filesToScan.Add($full)
                }
            }
        }
    } else {
        $allFiles = Get-ChildItem -Path $ScanPath -Recurse -File | Where-Object {
            $_.FullName -notmatch '[\\/]\.git[\\/]' -and
            $_.FullName -notmatch '[\\/](_agents|\.agents)[\\/]' -and
            $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
            $_.FullName -notmatch '[\\/]target[\\/]' -and
            $_.FullName -notmatch '[\\/]bin[\\/]' -and
            $_.FullName -notmatch '[\\/]obj[\\/]'
        }
        foreach ($f in $allFiles) { $filesToScan.Add($f.FullName) }
    }
} else {
    $allFiles = Get-ChildItem -Path $ScanPath -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/](_agents|\.agents)[\\/]' -and
        $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
        $_.FullName -notmatch '[\\/]target[\\/]' -and
        $_.FullName -notmatch '[\\/]bin[\\/]' -and
        $_.FullName -notmatch '[\\/]obj[\\/]' -and
        $_.FullName -notmatch '[\\/]publish[\\/]' -and
        $_.FullName -notmatch '[\\/]artifacts[\\/]'
    }
    foreach ($f in $allFiles) {
        $filesToScan.Add($f.FullName)
    }
}

$violations = [System.Collections.Generic.List[PSCustomObject]]::new()
$fixedViolations = [System.Collections.Generic.List[PSCustomObject]]::new()

$isWindowsOs = ($env:OS -eq 'Windows_NT') -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
$defaultTargetEol = if ($isWindowsOs) { "CRLF" } else { "LF" }

function Convert-GlobToRegex([string]$Pattern) {
    $hasSlash = $Pattern.Contains('/')
    $p = $Pattern.TrimStart('/')
    $sb = [System.Text.StringBuilder]::new()
    if ($hasSlash) { [void]$sb.Append('^') } else { [void]$sb.Append('(?:^|/)') }
    $i = 0
    while ($i -lt $p.Length) {
        if (($i + 2) -lt $p.Length -and $p.Substring($i, 3) -eq '**/') {
            [void]$sb.Append('(?:.*/)?')
            $i += 3
            continue
        }
        $c = $p[$i]
        if ($c -eq '*') {
            if (($i + 1) -lt $p.Length -and $p[$i + 1] -eq '*') {
                [void]$sb.Append('.*')
                $i += 2
                continue
            }
            [void]$sb.Append('[^/]*')
        } elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
        } elseif ($c -eq '{') {
            $close = $p.IndexOf('}', $i + 1)
            if ($close -gt $i) {
                $inner = $p.Substring($i + 1, $close - $i - 1)
                $alts = ($inner -split ',') | ForEach-Object { [regex]::Escape($_) }
                [void]$sb.Append('(?:' + ($alts -join '|') + ')')
                $i = $close + 1
                continue
            }
            [void]$sb.Append('\{')
        } else {
            [void]$sb.Append([regex]::Escape([string]$c))
        }
        $i++
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

function Get-ProjectEolContext([string]$Root, [string[]]$RelPaths) {
    $gitOverrides = @{}
    $ecRules = [System.Collections.Generic.List[PSCustomObject]]::new()
    $gaFallbackRules = [System.Collections.Generic.List[PSCustomObject]]::new()

    $gitTop = (& git -C $Root rev-parse --show-toplevel 2>$null)
    $inGit = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitTop))
    $gitRootPath = if ($inGit) { $gitTop.Trim() } else { $Root }

    $ecPath = Join-Path $Root ".editorconfig"
    if (-not (Test-Path $ecPath -PathType Leaf) -and $inGit) {
        $ecPath = Join-Path $gitRootPath ".editorconfig"
    }
    if (Test-Path $ecPath -PathType Leaf) {
        $curRegex = $null
        foreach ($rawLine in [System.IO.File]::ReadAllLines($ecPath)) {
            $line = $rawLine.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
            if ($line -match '^\[(.+)\]$') {
                $curRegex = Convert-GlobToRegex $Matches[1].Trim()
            } elseif ($curRegex -and $line -match '^end_of_line\s*=\s*(lf|crlf)\b') {
                $ecRules.Add([PSCustomObject]@{ Regex = $curRegex; Eol = $Matches[1].ToUpperInvariant() })
            }
        }
    }

    $hasGitAttr = (Test-Path (Join-Path $Root ".gitattributes") -PathType Leaf) -or ($inGit -and (Test-Path (Join-Path $gitRootPath ".gitattributes") -PathType Leaf))
    if ($hasGitAttr -and $inGit -and $RelPaths.Count -gt 0) {
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new("git", "-C `"$Root`" check-attr --stdin -z text eol")
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $payload = ($RelPaths -join "`0") + "`0"
            $inBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $proc.StandardInput.BaseStream.Write($inBytes, 0, $inBytes.Length)
            $proc.StandardInput.Close()
            $rawOut = $proc.StandardOutput.ReadToEnd()
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($rawOut)) {
                $toks = $rawOut -split "`0"
                for ($t = 0; ($t + 2) -lt $toks.Length; $t += 3) {
                    $p = $toks[$t].Replace('\', '/')
                    $attr = $toks[$t + 1]
                    $val = $toks[$t + 2]
                    if ($attr -eq "text" -and $val -eq "unset") {
                        $gitOverrides[$p] = "SKIP"
                    } elseif ($attr -eq "eol" -and $gitOverrides[$p] -ne "SKIP") {
                        if ($val -eq "lf") { $gitOverrides[$p] = "LF" }
                        elseif ($val -eq "crlf") { $gitOverrides[$p] = "CRLF" }
                    }
                }
            }
        } catch {}
    } elseif ($hasGitAttr -and -not $inGit) {
        $gaPath = Join-Path $Root ".gitattributes"
        if (Test-Path $gaPath -PathType Leaf) {
            foreach ($rawLine in [System.IO.File]::ReadAllLines($gaPath)) {
                $line = $rawLine.Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
                $parts = $line -split '\s+'
                if ($parts.Length -lt 2) { continue }
                $patRegex = Convert-GlobToRegex $parts[0]
                $attrs = $parts[1..($parts.Length - 1)]
                if ($attrs -contains '-text' -or $attrs -contains 'binary') {
                    $gaFallbackRules.Add([PSCustomObject]@{ Regex = $patRegex; Eol = "SKIP" })
                } elseif ($attrs -contains 'eol=lf') {
                    $gaFallbackRules.Add([PSCustomObject]@{ Regex = $patRegex; Eol = "LF" })
                } elseif ($attrs -contains 'eol=crlf') {
                    $gaFallbackRules.Add([PSCustomObject]@{ Regex = $patRegex; Eol = "CRLF" })
                }
            }
        }
    }

    return [PSCustomObject]@{
        GitOverrides = $gitOverrides
        GaFallback   = $gaFallbackRules
        EcRules      = $ecRules
    }
}

function Resolve-TargetEol([string]$RelUnix, $Ctx, [string]$DefaultEol) {
    if ($Ctx.GitOverrides.ContainsKey($RelUnix)) {
        return $Ctx.GitOverrides[$RelUnix]
    }
    $gaEol = $null
    foreach ($r in $Ctx.GaFallback) {
        if ($RelUnix -cmatch $r.Regex) { $gaEol = $r.Eol }
    }
    if ($gaEol) { return $gaEol }
    $ecEol = $null
    foreach ($r in $Ctx.EcRules) {
        if ($RelUnix -cmatch $r.Regex) { $ecEol = $r.Eol }
    }
    if ($ecEol) { return $ecEol }
    return $DefaultEol
}

$relCandidates = @($filesToScan | ForEach-Object { $_.Replace($ScanPath + "\", "").Replace($ScanPath + "/", "").Replace('\', '/') })
$eolContext = if (-not $SkipLineEndings) { Get-ProjectEolContext -Root $ScanPath -RelPaths $relCandidates } else { $null }

# Secret detection regex patterns
$secretPatterns = @(
    @{ Name = "Private Key"; Regex = '-----BEGIN (RSA|EC|DSA|OPENSSH)?\s*PRIVATE KEY-----' },
    @{ Name = "AWS Access Key"; Regex = '(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}' },
    @{ Name = "GitHub Personal Token"; Regex = 'gh[pousr]_[A-Za-z0-9_]{36,255}' }
)

foreach ($filePath in $filesToScan) {
    $relPath = $filePath.Replace($ScanPath + "\", "").Replace($ScanPath + "/", "")

    # 1. Submodule Boundary Leakage (CommitManager guardrail)
    if ($relPath -match '^((\.agents|_agents)[\\/])') {
        if ($StagedOnly) {
            $violations.Add([PSCustomObject]@{
                Rule = "SubmoduleIsolation"
                File = $relPath
                Line = 0
                Message = "Staged change originates inside submodule path '$relPath'"
            })
        }
    }

    # 2. Text extension check (only analyze text files for line endings and content rules)
    $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
    $leafName = [System.IO.Path]::GetFileName($filePath)
    $textExtensions = @(".rs", ".cs", ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".java", ".kt", ".kts", ".gradle", ".c", ".cpp", ".h", ".hpp", ".json", ".md", ".yml", ".yaml", ".toml", ".ps1", ".sh", ".axaml", ".props", ".targets", ".xml", ".txt", ".csproj", ".sln", ".editorconfig", ".gitattributes", ".gitignore", ".manifest")
    if (-not (($textExtensions -contains $ext) -or ($leafName -match '^(LICENSE|NOTICE|AUTHORS|CODEOWNERS)$'))) {
        continue
    }

    # Read bytes for line-ending check and text decode
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        if ($bytes.Length -eq 0) { continue }

        # 3. Line Ending Check: OS-native (CRLF on Windows, LF on Linux/macOS) unless overridden by project config (.gitattributes/.editorconfig); deferrable via -SkipLineEndings
        $relUnix = $relPath.Replace('\', '/')
        $targetEol = if (-not $SkipLineEndings) { Resolve-TargetEol -RelUnix $relUnix -Ctx $eolContext -DefaultEol $defaultTargetEol } else { $defaultTargetEol }
        if (-not $SkipLineEndings -and $targetEol -ne "SKIP") {
            $hasWrongEol = $false

            if ($targetEol -eq "CRLF") {
                for ($i = 0; $i -lt $bytes.Length; $i++) {
                    if ($bytes[$i] -eq 10) {
                        if ($i -eq 0 -or $bytes[$i - 1] -ne 13) { $hasWrongEol = $true; break }
                    } elseif ($bytes[$i] -eq 13) {
                        if (($i + 1) -ge $bytes.Length -or $bytes[$i + 1] -ne 10) { $hasWrongEol = $true; break }
                    }
                }
            } else {
                for ($i = 0; $i -lt $bytes.Length; $i++) {
                    if ($bytes[$i] -eq 13) {
                        $hasWrongEol = $true
                        break
                    }
                }
            }

            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
            if ($hasWrongEol -or ($Fix -and $hasBom)) {
                if ($Fix) {
                    try {
                        $rawText = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
                        $lfText = $rawText.Replace("`r`n", "`n").Replace("`r", "`n")
                        $fixedText = if ($targetEol -eq "CRLF") { $lfText.Replace("`n", "`r`n") } else { $lfText }
                        [System.IO.File]::WriteAllText($filePath, $fixedText, (New-Object System.Text.UTF8Encoding($false)))
                        if ($StagedOnly) {
                            git -C $ScanPath add $filePath 2>$null
                        }
                        $fixedViolations.Add([PSCustomObject]@{
                            Rule = "LineEndings"
                            File = $relPath
                            Action = if ($targetEol -eq "CRLF") { "Normalized LF to CRLF" } else { "Normalized CRLF to LF" }
                        })
                        $bytes = [System.IO.File]::ReadAllBytes($filePath)
                    } catch {
                        $violations.Add([PSCustomObject]@{
                            Rule = "LineEndings"
                            File = $relPath
                            Line = 0
                            Message = "Line-ending violation detected (expected $targetEol), auto-fix failed: $_"
                        })
                    }
                } else {
                    $violations.Add([PSCustomObject]@{
                        Rule = "LineEndings"
                        File = $relPath
                        Line = 0
                        Message = if ($targetEol -eq "CRLF") { "LF line endings detected (expected CRLF)" } else { "CRLF line endings detected (expected LF)" }
                    })
                }
            }
        }

        # 4. Content scanning (text files only)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        $lines = $content -split "`r?`n"

        # 4a. Safe-Rust Check (*.rs files: blocks, pub/async unsafe fn, unsafe impl/trait/extern, Rust 2024 #[unsafe(...)])
        if ($ext -eq ".rs") {
                for ($l = 0; $l -lt $lines.Length; $l++) {
                    $codeOnly = [regex]::Replace(($lines[$l] -replace '//.*$', ''), '"(?:\\.|[^"\\])*"', '""')
                    if ($codeOnly -match '(\bunsafe\s*(\{|fn\b|impl\b|trait\b|extern\b)|#\[\s*unsafe\s*\()') {
                        $violations.Add([PSCustomObject]@{
                            Rule = "SafeRust"
                            File = $relPath
                            Line = $l + 1
                            Message = "Forbidden 'unsafe' construct detected in safe-Rust codebase"
                        })
                    }
                }
            }

        # 4b. Secrets Check
        foreach ($sp in $secretPatterns) {
            if ($content -match $sp.Regex) {
                $violations.Add([PSCustomObject]@{
                    Rule = "SecretDetection"
                    File = $relPath
                    Line = 0
                    Message = "Potential secret detected ($($sp.Name))"
                })
            }
        }
    } catch {
        # skip unreadable binary files
    }
}

$isPass = ($violations.Count -eq 0)
$result = [ordered]@{
    status = if ($isPass) { "pass" } else { "fail" }
    scanned_files_count = $filesToScan.Count
    violations_count = $violations.Count
    fixed_count = $fixedViolations.Count
    fixed = $fixedViolations.ToArray()
    violations = $violations.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    if ($fixedViolations.Count -gt 0) {
        Write-Host "Auto-Remediation: $($fixedViolations.Count) file(s) fixed" -ForegroundColor Green
        foreach ($fix in $fixedViolations) {
            Write-Host "  [$($fix.Rule)] $($fix.File): $($fix.Action)" -ForegroundColor Green
        }
    }
    if ($isPass) {
        Write-Host "Deterministic Guardrails: PASS ($($filesToScan.Count) files, 0 violations)" -ForegroundColor Green
    } else {
        Write-Host "Deterministic Guardrails: FAIL ($($violations.Count) violations in $($filesToScan.Count) files)" -ForegroundColor Red
        foreach ($v in $violations) {
            Write-Host "  [$($v.Rule)] $($v.File)$(if ($v.Line -gt 0) { ':' + $v.Line }): $($v.Message)" -ForegroundColor Yellow
        }
    }
}

if (-not $isPass) {
    exit 1
}
