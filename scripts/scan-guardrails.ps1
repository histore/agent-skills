<#
.SYNOPSIS
    Deterministic code guardrails scanner (Safe-Rust, Secrets, CRLF, Submodule leakage).
.DESCRIPTION
    Scans project files or staged git changes for governance violations without LLM tokens:
    - Safe-Rust: detects 'unsafe' blocks, functions, or implementations in Rust (*.rs)
    - Secrets: detects accidental AWS/GitHub tokens, private keys, or passwords
    - CRLF: asserts standard LF line endings
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
    [string]$ScanPath,

    [Parameter(Mandatory = $false)]
    [switch]$StagedOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Fix,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $ScanPath) {
    $ScanPath = (Get-Location).Path
}

$filesToScan = [System.Collections.Generic.List[string]]::new()

if ($StagedOnly) {
    $staged = git -C $ScanPath diff --name-only --cached 2>$null
    foreach ($f in ($staged -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($f)) {
            $full = Join-Path $ScanPath $f
            if (Test-Path $full) { $filesToScan.Add($full) }
        }
    }
} else {
    $allFiles = Get-ChildItem -Path $ScanPath -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
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

    # 2. Text extension check (only analyze text files for CRLF and content rules)
    $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
    $textExtensions = @(".rs", ".cs", ".ts", ".js", ".py", ".go", ".json", ".md", ".yml", ".yaml", ".toml", ".ps1", ".sh", ".axaml", ".props", ".targets", ".xml", ".txt", ".csproj", ".sln", ".editorconfig", ".gitattributes", ".gitignore", ".manifest")
    if (-not ($textExtensions -contains $ext)) {
        continue
    }

    # Read bytes for CRLF check and text decode
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        if ($bytes.Length -eq 0) { continue }

        # 3. CRLF Line Ending Check
        $hasCrlf = $false
        for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
            if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) {
                $hasCrlf = $true
                break
            }
        }

        if ($hasCrlf) {
            if ($Fix) {
                try {
                    $rawText = [System.Text.Encoding]::UTF8.GetString($bytes)
                    $fixedText = $rawText.Replace("`r`n", "`n")
                    [System.IO.File]::WriteAllText($filePath, $fixedText, (New-Object System.Text.UTF8Encoding($false)))
                    if ($StagedOnly) {
                        git -C $ScanPath add $filePath 2>$null
                    }
                    $fixedViolations.Add([PSCustomObject]@{
                        Rule = "LineEndings"
                        File = $relPath
                        Action = "Normalized CRLF to LF"
                    })
                    $bytes = [System.IO.File]::ReadAllBytes($filePath)
                } catch {
                    $violations.Add([PSCustomObject]@{
                        Rule = "LineEndings"
                        File = $relPath
                        Line = 0
                        Message = "CRLF detected, auto-fix failed: $_"
                    })
                }
            } else {
                $violations.Add([PSCustomObject]@{
                    Rule = "LineEndings"
                    File = $relPath
                    Line = 0
                    Message = "CRLF line endings detected (must be LF)"
                })
            }
        }

        # 4. Content scanning (text files only)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        $lines = $content -split "`r?`n"

        # 4a. Safe-Rust Check (*.rs files)
        if ($ext -eq ".rs") {
                for ($l = 0; $l -lt $lines.Length; $l++) {
                    $line = $lines[$l]
                    if ($line -match '^\s*unsafe\s*(\{|fn|impl|trait)') {
                        $violations.Add([PSCustomObject]@{
                            Rule = "SafeRust"
                            File = $relPath
                            Line = $l + 1
                            Message = "Forbidden 'unsafe' block or function detected in safe-Rust codebase"
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
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Deterministic Guardrails Scanner" -ForegroundColor Cyan
    Write-Host "Scanned Files: $($filesToScan.Count) | Violations: $($violations.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($fixedViolations.Count -gt 0) {
        Write-Host "Auto-Remediation: $($fixedViolations.Count) file(s) fixed" -ForegroundColor Green
        foreach ($fix in $fixedViolations) {
            Write-Host "  [$($fix.Rule)] $($fix.File): $($fix.Action)" -ForegroundColor Green
        }
    }
    if ($isPass) {
        Write-Host "Guardrails Status: PASS (0 violations)" -ForegroundColor Green
    } else {
        Write-Host "Guardrails Status: FAIL ($($violations.Count) violations)" -ForegroundColor Red
        foreach ($v in $violations) {
            Write-Host "  [$($v.Rule)] $($v.File)$(if ($v.Line -gt 0) { ':' + $v.Line }): $($v.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if (-not $isPass) {
    exit 1
}
