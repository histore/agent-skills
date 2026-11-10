#Requires -Version 5.1
<#
.SYNOPSIS
    Deterministic zero-token commit preparation: deferred format/CRLF checks, whitespace-only diff cleanup, and commit message drafting.
.DESCRIPTION
    Executes deferred pre-commit hygiene without LLM token overhead:
    1. Detects and optionally reverts whitespace/CRLF-only diffs against HEAD (-RevertWhitespaceOnly).
    2. Distinguishes unambiguous CRLF regressions from legacy CRLF files (ambiguous -> user decision).
    3. Normalizes unambiguous CRLF -> LF deterministically (-FixLineEndings or -Direct).
    4. Runs deferred tech-stack formatter check (format_check_cmd) and optional auto-format (-Format).
    5. Runs final guardrails (Safe-Rust, Secrets, CRLF, Submodule isolation) & Clean Architecture check.
    6. Outputs a suggested Conventional Commit message and clear next-step state.
.PARAMETER RepoRoot
    Path to the host repository root. Defaults to current repository root.
.PARAMETER RevertWhitespaceOnly
    Automatically reverts tracked files whose diff against HEAD contains only whitespace/CRLF changes.
.PARAMETER FixLineEndings
    Normalizes unambiguous CRLF line endings to LF in modified/untracked files.
.PARAMETER Format
    Runs the detected tech-stack formatter fix command if format checks fail.
.PARAMETER ForceNormalize
    Includes ambiguous legacy CRLF files in line-ending normalization (use only after user confirmation).
.PARAMETER Direct
    Direct-commit mode: automatically performs safe whitespace-only reverts and unambiguous LF normalizations
    without pausing for commit-message confirmation, while still enforcing format checks and stopping on ambiguous files.
.PARAMETER JsonOutput
    Outputs structured JSON result.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/prepare-commit.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/prepare-commit.ps1 -RevertWhitespaceOnly -FixLineEndings -JsonOutput
.EXAMPLE
    pwsh -NoProfile -File ./scripts/prepare-commit.ps1 -Direct -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$RevertWhitespaceOnly,

    [Parameter(Mandatory = $false)]
    [switch]$FixLineEndings,

    [Parameter(Mandatory = $false)]
    [switch]$Format,

    [Parameter(Mandatory = $false)]
    [switch]$ForceNormalize,

    [Parameter(Mandatory = $false)]
    [switch]$Direct,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-HostRepoRoot {
    $superproject = git rev-parse --show-superproject-working-tree 2>$null
    if ($superproject) { return $superproject.Trim() }
    $toplevel = git rev-parse --show-toplevel 2>$null
    if ($toplevel) {
        $root = $toplevel.Trim()
        if ($root -match '[\\/](_agents|\.agents)$') {
            $root = Split-Path -Parent $root
        }
        return $root
    }
    return (Get-Location).Path
}

if (-not $RepoRoot) {
    $RepoRoot = Get-HostRepoRoot
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
$scriptDir = $PSScriptRoot

$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $cmd = Get-Command pwsh
    if ($cmd.Source -notmatch 'WindowsApps\\pwsh\.exe' -or ($cmd.Version -and $cmd.Version.Major -gt 0)) {
        $cmd.Source
    } else {
        (Get-Process -Id $PID).Path
    }
} else {
    (Get-Process -Id $PID).Path
}

$doRevertWs = $RevertWhitespaceOnly -or $Direct
$doFixEol = $FixLineEndings -or $Direct

function Restore-FileFromHead {
    param([string]$Root, [string]$RelPath)
    $fullPath = Join-Path $Root $RelPath
    & git -C $Root checkout -- $RelPath 2>$null
    if ($LASTEXITCODE -eq 0) { return $true }

    # Sandbox fallback: write exact raw HEAD blob bytes directly to disk
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new("git")
        $psi.Arguments = "-C `"$Root`" cat-file blob `"HEAD:$($RelPath.Replace('\', '/'))`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $ms = [System.IO.MemoryStream]::new()
        $proc.StandardOutput.BaseStream.CopyTo($ms)
        $proc.WaitForExit()
        if ($proc.ExitCode -eq 0) {
            [System.IO.File]::WriteAllBytes($fullPath, $ms.ToArray())
            return $true
        }
    } catch {}
    return $false
}

function Normalize-FileToLf {
    param([string]$FullPath)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FullPath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $fixed = $text.Replace("`r`n", "`n")
        [System.IO.File]::WriteAllText($FullPath, $fixed, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch {
        return $false
    }
}

function Test-HasCrlfBytes {
    param([string]$FullPath)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FullPath)
        for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
            if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) { return $true }
        }
    } catch {}
    return $false
}

function Get-WorkingTreeFiles {
    param([string]$Root)
    $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $staged = (& git -C $Root diff --name-only --cached 2>$null) -split "`r?`n"
    $unstaged = (& git -C $Root diff --name-only 2>$null) -split "`r?`n"
    $untracked = (& git -C $Root ls-files --others --exclude-standard 2>$null) -split "`r?`n"

    $untrackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($u in $untracked) {
        if (-not [string]::IsNullOrWhiteSpace($u)) { [void]$untrackedSet.Add($u.Trim()) }
    }

    foreach ($raw in ($staged + $unstaged + $untracked)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $rel = $raw.Trim().Replace('\', '/')
        if ($seen.Add($rel)) {
            $candidates.Add([PSCustomObject]@{
                RelPath = $rel
                IsUntracked = $untrackedSet.Contains($rel)
            })
        }
    }
    return $candidates
}

$hasHead = $false
& git -C $RepoRoot rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hasHead = $true }

$candidates = Get-WorkingTreeFiles -Root $RepoRoot
$submoduleFiles = [System.Collections.Generic.List[string]]::new()
$hostFiles = [System.Collections.Generic.List[string]]::new()
$whitespaceOnlyFiles = [System.Collections.Generic.List[string]]::new()
$revertedWhitespaceFiles = [System.Collections.Generic.List[string]]::new()
$crlfFiles = [System.Collections.Generic.List[string]]::new()
$ambiguousFiles = [System.Collections.Generic.List[string]]::new()
$normalizedFiles = [System.Collections.Generic.List[string]]::new()

$textExtensions = @(".rs", ".cs", ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".java", ".kt", ".c", ".cpp", ".h", ".hpp", ".json", ".md", ".yml", ".yaml", ".toml", ".ps1", ".sh", ".axaml", ".props", ".targets", ".xml", ".txt", ".csproj", ".sln", ".editorconfig", ".gitattributes", ".gitignore", ".manifest")
$codeExtRegex = '\.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql)$'

foreach ($entry in $candidates) {
    $rel = $entry.RelPath
    if ($rel -match '^((\.agents|_agents)(/|$))') {
        $submoduleFiles.Add($rel)
        continue
    }

    $fullPath = Join-Path $RepoRoot $rel
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        # Deleted tracked file
        $hostFiles.Add($rel)
        continue
    }

    # 1. Whitespace-only / CRLF-only diff check against HEAD
    if (-not $entry.IsUntracked -and $hasHead) {
        $rawDiff = (& git -C $RepoRoot diff HEAD -- $rel 2>$null) -join "`n"
        $wsIgnoreDiff = (& git -C $RepoRoot diff -w HEAD -- $rel 2>$null) -join "`n"
        if (-not [string]::IsNullOrWhiteSpace($rawDiff) -and [string]::IsNullOrWhiteSpace($wsIgnoreDiff)) {
            if ($doRevertWs -and (Restore-FileFromHead -Root $RepoRoot -RelPath $rel)) {
                $revertedWhitespaceFiles.Add($rel)
                continue
            } else {
                $whitespaceOnlyFiles.Add($rel)
            }
        }
    }

    $hostFiles.Add($rel)

    # 2. CRLF check & ambiguity classification
    $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($textExtensions -contains $ext) {
        if (Test-HasCrlfBytes -FullPath $fullPath) {
            $isAmbiguous = $false
            if (-not $entry.IsUntracked) {
                $eolInfo = (& git -C $RepoRoot ls-files --eol -- $rel 2>$null) -join " "
                if ($eolInfo -match '\bi/crlf\b' -and $eolInfo -notmatch 'eol=lf') {
                    $isAmbiguous = $true
                }
            }

            if ($isAmbiguous -and -not $ForceNormalize) {
                $ambiguousFiles.Add($rel)
            } elseif ($doFixEol -or ($isAmbiguous -and $ForceNormalize)) {
                if (Normalize-FileToLf -FullPath $fullPath) {
                    $normalizedFiles.Add($rel)
                } else {
                    $crlfFiles.Add($rel)
                }
            } else {
                $crlfFiles.Add($rel)
            }
        }
    }
}

# 3. Deferred Format Check (when executable code is in hostFiles)
$formatStatus = "skipped"
$formatCommand = ""
$formatFixCommand = ""
$formatErrors = [System.Collections.Generic.List[string]]::new()

$hasExecutableChanges = ($hostFiles | Where-Object { $_ -match $codeExtRegex }).Count -gt 0
if ($hasExecutableChanges) {
    $detectScript = Join-Path $scriptDir "detect-tech-stack.ps1"
    if (Test-Path $detectScript) {
        try {
            $stackInfo = & $detectScript -ProjectRoot $RepoRoot -JsonOutput | ConvertFrom-Json
            $formatCommand = [string]$stackInfo.format_check_cmd
            $formatFixCommand = [string]$stackInfo.format_fix_cmd
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($formatCommand)) {
        function Invoke-FormatCmd([string]$Cmd) {
            $outFile = Join-Path ([System.IO.Path]::GetTempPath()) "fmt_${PID}_$([guid]::NewGuid().ToString('N')).log"
            $p = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-Command", "Set-Location '$RepoRoot'; $Cmd" -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError "${outFile}.err"
            $p.WaitForExit()
            $out = if (Test-Path $outFile) { (Get-Content $outFile -Raw) } else { "" }
            $err = if (Test-Path "${outFile}.err") { (Get-Content "${outFile}.err" -Raw) } else { "" }
            Remove-Item $outFile, "${outFile}.err" -Force -ErrorAction SilentlyContinue
            $code = $p.ExitCode
            if ($Cmd -match '^gofmt\s+-l' -and -not [string]::IsNullOrWhiteSpace($out)) {
                $code = 1
            }
            return [PSCustomObject]@{ ExitCode = $code; Output = ($err + "`n" + $out).Trim() }
        }

        $fmtRes = Invoke-FormatCmd $formatCommand
        if ($fmtRes.ExitCode -ne 0 -and $Format -and -not [string]::IsNullOrWhiteSpace($formatFixCommand) -and $ambiguousFiles.Count -eq 0) {
            $null = Invoke-FormatCmd $formatFixCommand
            $fmtRes = Invoke-FormatCmd $formatCommand
        }

        if ($fmtRes.ExitCode -eq 0) {
            $formatStatus = "pass"
        } else {
            $formatStatus = "fail"
            if ($fmtRes.Output) {
                $lines = ($fmtRes.Output -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 10
                foreach ($l in $lines) { $formatErrors.Add($l.Trim()) }
            }
        }
    }
}

# 4. Final Guardrails & Clean Architecture check (with CRLF enabled)
$guardrailsStatus = "pass"
$guardrailErrors = [System.Collections.Generic.List[string]]::new()
$scanScript = Join-Path $scriptDir "scan-guardrails.ps1"
if ((Test-Path $scanScript) -and $hostFiles.Count -gt 0) {
    try {
        $scanOut = & $scanScript -ScanPath $RepoRoot -WorkingTree -JsonOutput | ConvertFrom-Json
        if ($scanOut.status -eq "fail") {
            $guardrailsStatus = "fail"
            foreach ($v in $scanOut.violations) {
                $relV = [string]$v.File
                $isHandledEol = ($v.Rule -eq "LineEndings") -and (($ambiguousFiles -contains $relV) -or ($crlfFiles -contains $relV) -or ($whitespaceOnlyFiles -contains $relV))
                if ($isHandledEol) { continue }
                $guardrailErrors.Add("[$($v.Rule)] $($v.File): $($v.Message)")
            }
            if ($guardrailErrors.Count -eq 0) { $guardrailsStatus = "pass" }
        }
    } catch {}
}

$archStatus = "pass"
$archScript = Join-Path $scriptDir "lint-clean-architecture.ps1"
if ((Test-Path $archScript) -and $hostFiles.Count -gt 0) {
    try {
        $archOut = & $archScript -TargetPath $RepoRoot -WorkingTree -JsonOutput | ConvertFrom-Json
        if ($archOut.status -eq "fail") {
            $archStatus = "fail"
            foreach ($v in $archOut.violations | Where-Object { $_.Severity -eq "Error" }) {
                $guardrailErrors.Add("[$($v.Type)] $($v.File):$($v.Line) - $($v.Message)")
            }
        }
    } catch {}
}

# 5. Draft Conventional Commit message deterministically
$suggestedCommit = ""
if ($hostFiles.Count -gt 0) {
    $allDocs = ($hostFiles | Where-Object { $_ -notmatch '\.md$' }).Count -eq 0
    $allScripts = ($hostFiles | Where-Object { $_ -notmatch '^(scripts/|rules/|\.github/)' }).Count -eq 0
    $hasTests = ($hostFiles | Where-Object { $_ -match '(test|spec)' }).Count -gt 0
    $prefix = if ($allDocs) { "docs" } elseif ($allScripts) { "chore" } else { "feat" }
    $scope = if ($allDocs) { "docs" } elseif ($allScripts) { "tooling" } elseif ($hasTests) { "tests" } else { "core" }
    $firstLeaf = [System.IO.Path]::GetFileNameWithoutExtension($hostFiles[0])
    $suggestedCommit = if ($hostFiles.Count -eq 1) {
        "${prefix}(${scope}): update $firstLeaf"
    } else {
        "${prefix}(${scope}): update $firstLeaf and $($hostFiles.Count - 1) additional file(s)"
    }
}

# 6. Determine overall status & next_step
$hasDecisionItems = ($whitespaceOnlyFiles.Count -gt 0) -or ($ambiguousFiles.Count -gt 0) -or ($crlfFiles.Count -gt 0)
$hasHardFailures = ($guardrailsStatus -eq "fail") -or ($archStatus -eq "fail") -or ($formatStatus -eq "fail") -or ($submoduleFiles.Count -gt 0)

$overallStatus = if ($hostFiles.Count -eq 0 -and $revertedWhitespaceFiles.Count -gt 0) {
    "clean"
} elseif ($hostFiles.Count -eq 0) {
    "no_changes"
} elseif ($hasHardFailures) {
    "fail"
} elseif ($hasDecisionItems) {
    "needs_decision"
} else {
    "ready"
}

$nextStep = switch ($overallStatus) {
    "clean"          { "nothing_to_commit_whitespace_reverted" }
    "no_changes"     { "nothing_to_commit" }
    "needs_decision" { "ask_user_normalization" }
    "fail"           { "resolve_format_or_guardrail_errors" }
    "ready"          { if ($Direct) { "execute_commit" } else { "present_commit_message" } }
}

$result = [ordered]@{
    status                    = $overallStatus
    mode                      = if ($Direct) { "direct" } else { "prepare" }
    next_step                 = $nextStep
    host_files                = $hostFiles.ToArray()
    reverted_whitespace_files = $revertedWhitespaceFiles.ToArray()
    normalized_files          = $normalizedFiles.ToArray()
    whitespace_only_files     = $whitespaceOnlyFiles.ToArray()
    crlf_files                = $crlfFiles.ToArray()
    ambiguous_files           = $ambiguousFiles.ToArray()
    submodule_files           = $submoduleFiles.ToArray()
    format_check              = [ordered]@{
        status          = $formatStatus
        command         = $formatCommand
        can_auto_format = (-not [string]::IsNullOrWhiteSpace($formatFixCommand))
        errors          = $formatErrors.ToArray()
    }
    guardrails_status         = $guardrailsStatus
    arch_status               = $archStatus
    errors                    = $guardrailErrors.ToArray()
    suggested_commit_message  = $suggestedCommit
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Commit Preparation ($($result.mode.ToUpper()))" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $overallStatus | Next Step: $nextStep" -ForegroundColor $(if ($overallStatus -in @("ready", "clean")) { "Green" } elseif ($overallStatus -eq "needs_decision") { "Yellow" } else { "Red" })
    if ($revertedWhitespaceFiles.Count -gt 0) { Write-Host "Reverted whitespace-only files: $($revertedWhitespaceFiles -join ', ')" -ForegroundColor DarkGray }
    if ($normalizedFiles.Count -gt 0) { Write-Host "Normalized CRLF -> LF: $($normalizedFiles -join ', ')" -ForegroundColor DarkGray }
    if ($whitespaceOnlyFiles.Count -gt 0) { Write-Host "Whitespace-only diffs awaiting revert (-RevertWhitespaceOnly): $($whitespaceOnlyFiles -join ', ')" -ForegroundColor Yellow }
    if ($crlfFiles.Count -gt 0) { Write-Host "Unambiguous CRLF files (-FixLineEndings): $($crlfFiles -join ', ')" -ForegroundColor Yellow }
    if ($ambiguousFiles.Count -gt 0) { Write-Host "Ambiguous legacy CRLF files (user decision required, -ForceNormalize): $($ambiguousFiles -join ', ')" -ForegroundColor Yellow }
    if ($formatStatus -eq "fail") { Write-Host "Format check failed ($formatCommand): $($formatErrors -join ' | ')" -ForegroundColor Red }
    if ($guardrailErrors.Count -gt 0) { Write-Host "Errors: $($guardrailErrors -join ' | ')" -ForegroundColor Red }
    if ($suggestedCommit) { Write-Host "Suggested Commit: $suggestedCommit" -ForegroundColor White }
}

if ($overallStatus -eq "fail" -or $overallStatus -eq "needs_decision") {
    exit 1
}
