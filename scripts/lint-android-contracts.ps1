<#
.SYNOPSIS
    Deterministic Android & Kotlin contract and resource-safety linter.
.DESCRIPTION
    Scans Kotlin (.kt) files in the host project or working tree for common Android silent bugs:
    - CursorLeak: contentResolver.query() / rawQuery() without .use {} or try/finally close()
    - MissingNotifyChange: ContentProvider insert/update/delete overrides missing notifyChange()
    - UriContractSync: UriMatcher.addURI() without corresponding test coverage in *Test.kt
    - ComposeModifier: Public @Composable functions missing a Modifier parameter
.PARAMETER ProjectRoot
    Optional path to the project repository root. Defaults to current directory.
.PARAMETER WorkingTree
    Switch to scan only modified/untracked .kt files in git working tree.
.PARAMETER JsonOutput
    Switch to output results as structured JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-android-contracts.ps1 -WorkingTree -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $false)]
    [switch]$WorkingTree,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path.TrimEnd('\', '/')

$filesToScan = [System.Collections.Generic.List[string]]::new()
if ($WorkingTree) {
    $isGit = git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null
    if ($isGit -eq "true") {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $candidates = @()
        $candidates += (git -C $ProjectRoot diff --name-only --cached 2>$null) -split "`r?`n"
        $candidates += (git -C $ProjectRoot diff --name-only 2>$null) -split "`r?`n"
        $candidates += (git -C $ProjectRoot ls-files --others --exclude-standard 2>$null) -split "`r?`n"
        foreach ($f in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($f) -and $f -notmatch '^((\.agents|_agents)[\\/])' -and $f -match '\.kt$') {
                $full = Join-Path $ProjectRoot $f
                if ((Test-Path $full -PathType Leaf) -and $seen.Add($full)) {
                    $filesToScan.Add($full)
                }
            }
        }
    }
}

if (-not $WorkingTree -or ($filesToScan.Count -eq 0 -and -not $WorkingTree)) {
    $allKt = Get-ChildItem -Path $ProjectRoot -Filter "*.kt" -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|build|node_modules)[\\/]'
    }
    foreach ($f in $allKt) { $filesToScan.Add($f.FullName) }
}

$errors = [System.Collections.Generic.List[PSCustomObject]]::new()
$warnings = [System.Collections.Generic.List[PSCustomObject]]::new()

# Collect test corpus if any UriMatcher checks are needed
$testCorpus = $null
function Get-KtTestCorpus {
    if ($null -ne $script:testCorpus) { return $script:testCorpus }
    $sb = [System.Text.StringBuilder]::new()
    $tFiles = Get-ChildItem -Path $ProjectRoot -Filter "*Test.kt" -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|build|node_modules)[\\/]'
    }
    foreach ($tf in $tFiles) {
        $c = Get-Content -Path $tf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($c) { [void]$sb.AppendLine($c) }
    }
    $script:testCorpus = $sb.ToString()
    return $script:testCorpus
}

foreach ($filePath in $filesToScan) {
    $relPath = $filePath.Replace($ProjectRoot + "\", "").Replace($ProjectRoot + "/", "").Replace('\', '/')
    if ($relPath -match '(?i)(^|/)(test|androidTest)/|Test\.kt$') { continue }

    $lines = @(Get-Content -Path $filePath -Encoding UTF8)
    $rawContent = $lines -join "`n"

    # 1. CursorLeak Check
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match '(contentResolver\.query\s*\(|\.rawQuery\s*\()') {
            $windowEnd = [Math]::Min($lines.Length - 1, $i + 15)
            $window = ($lines[$i..$windowEnd]) -join "`n"
            if ($window -notmatch '\.use\s*\{' -and $window -notmatch '\.close\s*\(' -and $window -notmatch '\bfinally\s*\{') {
                $errors.Add([PSCustomObject]@{
                    Rule = "CursorLeak"
                    File = $relPath
                    Line = $i + 1
                    Message = "Cursor query without '.use { ... }' or explicit close()/finally block."
                })
            }
        }
    }

    # 2. ContentProvider notifyChange() Check
    if ($rawContent -match 'class\s+\w+.*:\s*ContentProvider\s*\(' -or $relPath -match 'Provider\.kt$') {
        if ($rawContent -match 'override\s+fun\s+(insert|update|delete)\s*\(') {
            if ($rawContent -notmatch 'notifyChange\s*\(') {
                $errors.Add([PSCustomObject]@{
                    Rule = "MissingNotifyChange"
                    File = $relPath
                    Line = 1
                    Message = "ContentProvider implements insert/update/delete without calling notifyChange()."
                })
            }
        }
    }

    # 3. UriMatcher / UriContract Test Coverage Check
    $uriMatches = [regex]::Matches($rawContent, 'addURI\s*\([^,]+,\s*([A-Za-z0-9_."]+)\s*,')
    if ($uriMatches.Count -gt 0) {
        $corpus = Get-KtTestCorpus
        if (-not [string]::IsNullOrWhiteSpace($corpus)) {
            foreach ($um in $uriMatches) {
                $token = $um.Groups[1].Value.Trim('"')
                if ($token.Length -ge 3 -and $corpus -notmatch [regex]::Escape($token)) {
                    $warnings.Add([PSCustomObject]@{
                        Rule = "UriContractSync"
                        File = $relPath
                        Line = 1
                        Message = "UriMatcher entry '$token' is not referenced in any *Test.kt file."
                    })
                }
            }
        }
    }

    # 4. Public @Composable Modifier Check
    for ($i = 0; $i -lt $lines.Length - 1; $i++) {
        if ($lines[$i] -match '^\s*@Composable\b') {
            $prevLine = if ($i -gt 0) { $lines[$i - 1] } else { "" }
            if ($prevLine -match '@Preview') { continue }
            $sigWindow = ($lines[$i..([Math]::Min($lines.Length - 1, $i + 6))]) -join " "
            if ($sigWindow -match '@Composable\s+(private|internal)\s+fun\b') { continue }
            if ($sigWindow -match '@Composable\s+(?:public\s+)?fun\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)') {
                $fnName = $Matches[1]
                $params = $Matches[2]
                if ($params -notmatch '\bModifier\b') {
                    $warnings.Add([PSCustomObject]@{
                        Rule = "ComposeModifier"
                        File = $relPath
                        Line = $i + 2
                        Message = "Public @Composable '$fnName' should accept a 'modifier: Modifier = Modifier' parameter."
                    })
                }
            }
        }
    }
}

$status = if ($errors.Count -gt 0) { "fail" } else { "pass" }
$result = [ordered]@{
    status = $status
    scanned_files = $filesToScan.Count
    errors = $errors.ToArray()
    warnings = $warnings.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 4 -Compress
} else {
    if ($status -eq "pass") {
        Write-Host "Android Contract Linter: PASS ($($filesToScan.Count) files, 0 errors, $($warnings.Count) warnings)" -ForegroundColor Green
    } else {
        Write-Host "Android Contract Linter: FAIL ($($errors.Count) errors, $($warnings.Count) warnings)" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "  [ERROR:$($e.Rule)] $($e.File):$($e.Line) - $($e.Message)" -ForegroundColor Red }
    }
    foreach ($w in $warnings) { Write-Host "  [WARN:$($w.Rule)] $($w.File):$($w.Line) - $($w.Message)" -ForegroundColor Yellow }
}

if ($status -eq "fail") { exit 1 }
