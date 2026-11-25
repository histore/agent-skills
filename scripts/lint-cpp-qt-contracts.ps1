<#
.SYNOPSIS
    Deterministic C++ (MinGW/MSVC) and Qt / QtQuick (QML) contract linter.
.DESCRIPTION
    Scans C++ (.c, .cpp, .cc, .cxx, .h, .hpp, .hxx) and QML (.qml) files for common Qt/C++ silent bugs:
    - MissingQObjectMacro: QObject-derived class missing Q_OBJECT macro
    - MissingNotifySignal: Non-CONSTANT Q_PROPERTY missing NOTIFY signal
    - LegacySignalSlot: String-based SIGNAL(...) / SLOT(...) macros in connect()
    - Qt6ConnectionsSyntax: Deprecated QML Connections { on<Signal>: ... } without function syntax
    - RawOwningNew: Raw 'new Type' allocation outside smart pointers or parented QObject (Warning)
.PARAMETER ProjectRoot
    Optional path to the project repository root. Defaults to current directory.
.PARAMETER WorkingTree
    Switch to scan only modified/untracked files in git working tree.
.PARAMETER JsonOutput
    Switch to output results as structured JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-cpp-qt-contracts.ps1 -WorkingTree -JsonOutput
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

$targetExts = @('.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hxx', '.qml')
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
            if (-not [string]::IsNullOrWhiteSpace($f) -and $f -notmatch '^((\.agents|_agents)[\\/])') {
                $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
                if ($targetExts -contains $ext) {
                    $full = Join-Path $ProjectRoot $f
                    if ((Test-Path $full -PathType Leaf) -and $seen.Add($full)) {
                        $filesToScan.Add($full)
                    }
                }
            }
        }
    }
}

if (-not $WorkingTree) {
    $allFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|build|out|cmake-build-[^\\/]+|node_modules)[\\/]' -and
        ($targetExts -contains $_.Extension.ToLowerInvariant())
    }
    foreach ($f in $allFiles) { $filesToScan.Add($f.FullName) }
}

$errors = [System.Collections.Generic.List[PSCustomObject]]::new()
$warnings = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($filePath in $filesToScan) {
    $relPath = $filePath.Replace($ProjectRoot + "\", "").Replace($ProjectRoot + "/", "").Replace('\', '/')
    $isTestFile = ($relPath -match '(?i)(^|/)(test|tests)/|tst_|_test\.|Test\.(cpp|cc|cxx|qml)$')
    if ($isTestFile) { continue }

    $lines = @(Get-Content -Path $filePath -Encoding UTF8)
    $rawContent = $lines -join "`n"
    $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()

    if ($ext -eq '.qml') {
        # QML: Qt 6 Connections { onFoo: ... } without function onFoo(...)
        if ($rawContent -match 'Connections\s*\{') {
            for ($i = 0; $i -lt $lines.Length; $i++) {
                if ($lines[$i] -match 'Connections\s*\{') {
                    $windowEnd = [Math]::Min($lines.Length - 1, $i + 15)
                    for ($k = $i + 1; $k -le $windowEnd; $k++) {
                        if ($lines[$k] -match '^\s*\}\s*$') { break }
                        if ($lines[$k] -match '^\s*on[A-Z]\w*\s*:' -and $lines[$k] -notmatch '^\s*function\s+') {
                            $errors.Add([PSCustomObject]@{
                                Rule = "Qt6ConnectionsSyntax"
                                File = $relPath
                                Line = $k + 1
                                Message = "QML Connections uses deprecated 'onSignal:' syntax; use 'function onSignal(...)' for Qt 6 compatibility."
                            })
                        }
                    }
                }
            }
        }
        continue
    }

    # C++ / Qt Checks
    # 1. QObject subclass missing Q_OBJECT
    if ($rawContent -match 'class\s+\w+\s*:\s*public\s+(QObject|QWidget|QQuickItem|QAbstractItemModel|QAbstractListModel)\b') {
        if ($rawContent -notmatch '\bQ_OBJECT\b') {
            $errors.Add([PSCustomObject]@{
                Rule = "MissingQObjectMacro"
                File = $relPath
                Line = 1
                Message = "QObject-derived class is missing the Q_OBJECT macro."
            })
        }
    }

    # 2. Non-CONSTANT Q_PROPERTY missing NOTIFY
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*Q_PROPERTY\s*\(([^)]+)\)') {
            $propBody = $Matches[1]
            if ($propBody -notmatch '\bCONSTANT\b' -and $propBody -notmatch '\bNOTIFY\b') {
                $errors.Add([PSCustomObject]@{
                    Rule = "MissingNotifySignal"
                    File = $relPath
                    Line = $i + 1
                    Message = "Non-CONSTANT Q_PROPERTY is missing a NOTIFY signal for QML binding updates."
                })
            }
        }

        # 3. Legacy string-based SIGNAL()/SLOT() connect
        if ($line -match '\bconnect\s*\(' -and ($line -match '\bSIGNAL\s*\(' -or $line -match '\bSLOT\s*\(')) {
            $errors.Add([PSCustomObject]@{
                Rule = "LegacySignalSlot"
                File = $relPath
                Line = $i + 1
                Message = "Use compile-time pointer-to-member connect(&Sender::sig, ...) instead of legacy SIGNAL()/SLOT() macros."
            })
        }

        # 4. Raw owning 'new' outside smart pointers or parented QObject(this)
        if ($line -match '=\s*new\s+[A-Z]\w*' -and $line -notmatch '\b(make_unique|make_shared|unique_ptr|shared_ptr|QPointer)\b' -and $line -notmatch '\bnew\s+[A-Z]\w*\s*\([^)]*\bthis\b') {
            $warnings.Add([PSCustomObject]@{
                Rule = "RawOwningNew"
                File = $relPath
                Line = $i + 1
                Message = "Raw 'new' allocation detected; prefer std::make_unique/make_shared or parented QObject(..., this)."
            })
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
        Write-Host "C++/Qt/QML Contract Linter: PASS ($($filesToScan.Count) files, 0 errors, $($warnings.Count) warnings)" -ForegroundColor Green
    } else {
        Write-Host "C++/Qt/QML Contract Linter: FAIL ($($errors.Count) errors, $($warnings.Count) warnings)" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "  [ERROR:$($e.Rule)] $($e.File):$($e.Line) - $($e.Message)" -ForegroundColor Red }
    }
    foreach ($w in $warnings) { Write-Host "  [WARN:$($w.Rule)] $($w.File):$($w.Line) - $($w.Message)" -ForegroundColor Yellow }
}

if ($status -eq "fail") { exit 1 }
