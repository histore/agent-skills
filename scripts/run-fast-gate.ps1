<#
.SYNOPSIS
    Executes a Stage-1 deterministic Fast-Gate (build, test, lint) with log compaction.
.DESCRIPTION
    Runs native compilation, targeted/quiet tests, and linter based on auto-detected tech stack.
    On success, outputs a minimal single-line confirmation (zero token noise).
    On failure, compacts raw terminal output to only the relevant error messages.
.PARAMETER ProjectRoot
    Optional root directory of the project. Defaults to current directory.
.PARAMETER TestFilter
    Optional filter targeting only the affected test class or function.
.PARAMETER SkipLint
    Switch to bypass the linter check.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-fast-gate.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-fast-gate.ps1 -TestFilter "UserMapperTests"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $false)]
    [string]$TestFilter,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLint,

    [Parameter(Mandatory = $false)]
    [switch]$SkipGuardrails,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [int]$MaxDiffLines = 400,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failedStep = $null
$failureLogs = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

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

# 1. Detect tech stack in-process (zero subprocess spawn overhead)
$detectScript = Join-Path $scriptDir "detect-tech-stack.ps1"
$stackInfo = [ordered]@{
    stack = "unknown"
    build_cmd = ""
    test_cmd = ""
    lint_cmd = ""
}

if (Test-Path $detectScript) {
    try {
        $rawStack = & $detectScript -ProjectRoot $ProjectRoot -JsonOutput | ConvertFrom-Json
        $stackInfo = $rawStack
    } catch {}
}

# Helper to execute command and collect errors with context lines
function Invoke-GateStep {
    param([string]$StepName, [string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $true }
    
    $stdoutFile = Join-Path ([System.IO.Path]::GetTempPath()) "gate_stdout_${PID}_$([guid]::NewGuid().ToString('N')).log"
    $stderrFile = Join-Path ([System.IO.Path]::GetTempPath()) "gate_stderr_${PID}_$([guid]::NewGuid().ToString('N')).log"
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-Command", "Set-Location '$ProjectRoot'; $CommandLine" -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue

        if ($exitCode -ne 0) {
            $combined = ($stderr + "`n" + $stdout) -split "`r?`n"
            # Compact errors with up to 2 trailing context lines for assertion/location clarity (capped for model context hygiene)
            $matchedIndices = [System.Collections.Generic.HashSet[int]]::new()
            for ($i = 0; $i -lt $combined.Length; $i++) {
                if ($combined[$i] -match '(?i)error|failed|exception|assert|fatal|panicked') {
                    for ($ctx = [Math]::Max(0, $i - 1); $ctx -le [Math]::Min($combined.Length - 1, $i + 2); $ctx++) {
                        if (-not [string]::IsNullOrWhiteSpace($combined[$ctx])) {
                            [void]$matchedIndices.Add($ctx)
                        }
                    }
                    if ($matchedIndices.Count -ge 12) { break }
                }
            }
            if ($matchedIndices.Count -gt 0) {
                foreach ($idx in ($matchedIndices | Sort-Object)) {
                    $script:failureLogs.Add($combined[$idx].Trim())
                }
            } else {
                $tailLines = $combined | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 8
                foreach ($tl in $tailLines) { $script:failureLogs.Add($tl.Trim()) }
            }
            $script:failedStep = $StepName
            return $false
        }
        return $true
    } catch {
        $script:failureLogs.Add("Execution exception in $StepName : $_")
        $script:failedStep = $StepName
        return $false
    }
}

# 2. Run Build, Test, Lint if executable stack is present
$buildSuccess = $true
$testSuccess = $true
$lintSuccess = $true
$bypassedNoCode = $false

if ($stackInfo.stack -ne "unknown") {
    # Change-Detection-Guard: bypass build & test if no executable code was modified in working tree
    if (-not $Force -and -not $env:CI -and -not $env:GITHUB_ACTIONS) {
        try {
            $gitStatus = git -C $ProjectRoot status --porcelain 2>$null
            if ($LASTEXITCODE -eq 0) {
                if ([string]::IsNullOrWhiteSpace($gitStatus)) {
                    $bypassedNoCode = $true
                } else {
                    $statusLines = $gitStatus -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $hasExecutableCode = $false
                    $codeExtRegex = '\.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql)$'
                    $manifestRegex = '^(Cargo\.(toml|lock)|package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|.*\.csproj|.*\.fsproj|.*\.sln|Directory\.Build\.(props|targets)|pyproject\.toml|requirements\.txt|Pipfile|go\.(mod|sum)|pom\.xml|(build|settings)\.gradle(\.kts)?|libs\.versions\.toml|AndroidManifest\.xml|CMakeLists\.txt|Makefile)$'

                    foreach ($line in $statusLines) {
                        $rawPath = $line.Substring(2).Trim()
                        if ($rawPath -match '->') {
                            $rawPath = ($rawPath -split '->')[-1].Trim()
                        }
                        $rawPath = $rawPath.Trim('"')
                        $fileName = [System.IO.Path]::GetFileName($rawPath)
                        if ($fileName -match $codeExtRegex -or $fileName -match $manifestRegex) {
                            $hasExecutableCode = $true
                            break
                        }
                    }
                    if (-not $hasExecutableCode) {
                        $bypassedNoCode = $true
                    }
                }
            }
        } catch {
            $bypassedNoCode = $false
        }
    }

    if (-not $bypassedNoCode) {
        if ($stackInfo.build_cmd) {
            $buildSuccess = Invoke-GateStep -StepName "Build" -CommandLine $stackInfo.build_cmd
        }
        if ($buildSuccess -and $stackInfo.test_cmd) {
            $testCmd = $stackInfo.test_cmd
            if ($TestFilter -and $stackInfo.test_filter_syntax) {
                $testCmd = $stackInfo.test_filter_syntax.Replace("{filter}", $TestFilter)
            }
            $testSuccess = Invoke-GateStep -StepName "Test" -CommandLine $testCmd
        }
        if ($buildSuccess -and $testSuccess -and -not $SkipLint -and $stackInfo.lint_cmd) {
            $lintSuccess = Invoke-GateStep -StepName "Lint" -CommandLine $stackInfo.lint_cmd
        }
    }
}

# 3. Consolidated Guardrails & Clean Architecture Check (in-process across working-tree changes, zero extra tool roundtrips)
$guardrailsSuccess = $true
if ($buildSuccess -and $testSuccess -and $lintSuccess -and -not $SkipGuardrails) {
    $archScript = Join-Path $scriptDir "lint-clean-architecture.ps1"
    if (Test-Path $archScript) {
        try {
            $archRes = & $archScript -TargetPath $ProjectRoot -WorkingTree -JsonOutput | ConvertFrom-Json
            if ($archRes.status -eq "fail") {
                $guardrailsSuccess = $false
                $failedStep = "CleanArchitecture"
                foreach ($v in $archRes.violations | Where-Object { $_.Severity -eq "Error" }) {
                    $failureLogs.Add("[$($v.Type)] $($v.File):$($v.Line) - $($v.Message)")
                }
            }
        } catch {}
    }

    $scanScript = Join-Path $scriptDir "scan-guardrails.ps1"
    if ($guardrailsSuccess -and (Test-Path $scanScript)) {
        try {
            $scanRes = & $scanScript -ScanPath $ProjectRoot -WorkingTree -SkipLineEndings -JsonOutput | ConvertFrom-Json
            if ($scanRes.status -eq "fail") {
                $guardrailsSuccess = $false
                $failedStep = "Guardrails"
                foreach ($v in $scanRes.violations) {
                    $failureLogs.Add("[$($v.Rule)] $($v.File):$($v.Line) - $($v.Message)")
                }
            }
        } catch {}
    }

    $androidScript = Join-Path $scriptDir "lint-android-contracts.ps1"
    if ($guardrailsSuccess -and ($stackInfo.stack -eq "android-gradle" -or $stackInfo.language -eq "kotlin") -and (Test-Path $androidScript)) {
        try {
            $androidRes = & $androidScript -ProjectRoot $ProjectRoot -WorkingTree -JsonOutput | ConvertFrom-Json
            foreach ($w in $androidRes.warnings) {
                $warnings.Add("[$($w.Rule)] $($w.File):$($w.Line) - $($w.Message)")
            }
            if ($androidRes.status -eq "fail") {
                $guardrailsSuccess = $false
                $failedStep = "AndroidContracts"
                foreach ($v in $androidRes.errors) {
                    $failureLogs.Add("[$($v.Rule)] $($v.File):$($v.Line) - $($v.Message)")
                }
            }
        } catch {}
    }

    # 3b. Diff-Size-Guardrail (FEAT-GOV-002 AC-3: Warning only when executable code diff exceeds MaxDiffLines)
    if (-not $bypassedNoCode -and $MaxDiffLines -gt 0) {
        try {
            $numstatLines = git -C $ProjectRoot diff --numstat HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $numstatLines) {
                $totalDiffLines = 0
                $codeExtPattern = '\.(rs|cs|fs|ts|tsx|js|jsx|mjs|cjs|py|go|java|kt|kts|gradle|c|cpp|cc|cxx|h|hpp|hxx|swift|rb|php|scala|dart|zig|sql|ps1|sh)$'
                foreach ($nline in ($numstatLines -split "`r?`n")) {
                    if ($nline -match '^(\d+)\s+(\d+)\s+(.+)$') {
                        $added = [int]$Matches[1]
                        $deleted = [int]$Matches[2]
                        $diffFile = $Matches[3].Trim()
                        if ($diffFile -match $codeExtPattern) {
                            $totalDiffLines += ($added + $deleted)
                        }
                    }
                }
                if ($totalDiffLines -gt $MaxDiffLines) {
                    $warnings.Add("[DiffSize] $totalDiffLines executable code lines changed in working tree (threshold: $MaxDiffLines). Consider splitting into smaller atomic commits.")
                }
            }
        } catch {}
    }

    # 3c. AC-* Traceability Check (FEAT-GOV-002 AC-1/AC-2: Stage-1 Fail when active APPROVED/IN_PROGRESS FEAT-*.md has uncovered AC-* IDs)
    if ($guardrailsSuccess -and -not $bypassedNoCode) {
        $featuresDir = Join-Path $ProjectRoot "docs\features"
        if (Test-Path $featuresDir) {
            $activeSpecs = Get-ChildItem -Path $featuresDir -Filter "FEAT-*.md" -File -ErrorAction SilentlyContinue | Where-Object {
                $rawSpec = Get-Content -Path $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $rawSpec -match '(?m)^status:\s*(APPROVED|IN_PROGRESS)\b'
            }
            if ($activeSpecs) {
                $testFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                    $_.FullName -notmatch '[\\/](node_modules|target|bin|obj|\.git|_agents|\.agents|dist|build)[\\/]' -and
                    ($_.FullName -match '(?i)([\\/](tests?|androidTest|specs?|__tests__|evals)[\\/]|(test|spec)\.[a-z0-9]+$|Test\.(kt|java)$|_test\.[a-z0-9]+$|eval-cases\.json$|test-skills\.(ps1|sh)$)')
                }
                $testCorpus = ""
                if ($testFiles) {
                    $sb = [System.Text.StringBuilder]::new()
                    foreach ($tf in $testFiles) {
                        $tContent = Get-Content -Path $tf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($tContent) { [void]$sb.AppendLine($tContent) }
                    }
                    $testCorpus = $sb.ToString()
                }
                foreach ($specFile in $activeSpecs) {
                    $specContent = Get-Content -Path $specFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    $acMatches = [regex]::Matches($specContent, '(?m)^\s*-\s*\[[ xX]\]\s*\*\*(AC-\d+)\*\*')
                    $relSpec = $specFile.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
                    foreach ($m in $acMatches) {
                        $acId = $m.Groups[1].Value
                        if ($testCorpus -notmatch "\b$([regex]::Escape($acId))\b") {
                            $guardrailsSuccess = $false
                            $failedStep = "ACTraceability"
                            $failureLogs.Add("[ACTraceability] ${relSpec}: Missing test reference for $acId (reference $acId in a test name or comment)")
                        }
                    }
                }
            }
        }
    }
}

$sw.Stop()
$overallPass = ($buildSuccess -and $testSuccess -and $lintSuccess -and $guardrailsSuccess)

$result = [ordered]@{
    status = if ($overallPass) { "pass" } else { "fail" }
    failed_step = $failedStep
    duration_ms = $sw.ElapsedMilliseconds
    bypassed_code_gate = $bypassedNoCode
    errors = if (-not $overallPass) { $failureLogs.ToArray() } else { @() }
    warnings = $warnings.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 4 -Compress
} else {
    if ($overallPass) {
        if ($bypassedNoCode) {
            Write-Host "Stage-1 Fast-Gate: PASS ($($sw.ElapsedMilliseconds)ms) - Bypassed (no executable code modified in working tree; use -Force to override)" -ForegroundColor Green
        } else {
            Write-Host "Stage-1 Fast-Gate: PASS ($($sw.ElapsedMilliseconds)ms) - Zero errors" -ForegroundColor Green
        }
        foreach ($warn in $warnings) {
            Write-Host "  [WARN] $warn" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Stage-1 Fast-Gate: FAIL at step '$failedStep' ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Red
        foreach ($err in $failureLogs) {
            Write-Host "  - $err" -ForegroundColor Yellow
        }
        foreach ($warn in $warnings) {
            Write-Host "  [WARN] $warn" -ForegroundColor DarkYellow
        }
    }
}

if (-not $overallPass) {
    exit 1
}
