<#
.SYNOPSIS
    Determines project technology stack, language, build, and quiet testrunner commands.
.DESCRIPTION
    Inspects project manifests (Cargo.toml, package.json, *.sln/*.csproj, pyproject.toml, go.mod)
    and outputs a structured, zero-token JSON object with optimized quiet CLI commands.
.PARAMETER ProjectRoot
    Optional root directory to scan. Defaults to the current repository directory.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/detect-tech-stack.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

function Get-RelativePathCompat([string]$basePath, [string]$targetPath) {
    if ([System.Type]::GetType('System.IO.Path').GetMethod('GetRelativePath', [type[]]@([string], [string]))) {
        return [System.IO.Path]::GetRelativePath($basePath, $targetPath)
    }
    $baseUri = [Uri](([System.IO.Path]::GetFullPath($basePath)).TrimEnd('\', '/') + '/')
    $targetUri = [Uri]([System.IO.Path]::GetFullPath($targetPath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString().Replace('/', [System.IO.Path]::DirectorySeparatorChar))
}

$detected = [ordered]@{
    stack              = "unknown"
    language           = "unknown"
    build_cmd          = ""
    test_cmd           = ""
    test_filter_syntax = ""
    lint_cmd           = ""
    format_check_cmd   = ""
    format_fix_cmd     = ""
    manifest_file      = ""
}

# 1. Rust (Cargo.toml)
if (Test-Path (Join-Path $ProjectRoot "Cargo.toml")) {
    $detected.stack = "rust"
    $detected.language = "rust"
    $detected.build_cmd = "cargo check -q"
    $detected.test_cmd = "cargo test -q"
    $detected.test_filter_syntax = "cargo test -q {filter}"
    $detected.lint_cmd = "cargo clippy -q"
    $detected.format_check_cmd = "cargo fmt --check"
    $detected.format_fix_cmd = "cargo fmt"
    $detected.manifest_file = "Cargo.toml"
}
# 2. .NET (Directory.Build.props, *.sln, *.csproj)
elseif ((Test-Path (Join-Path $ProjectRoot "Directory.Build.props")) -or (Get-ChildItem -Path $ProjectRoot -Filter "*.sln" -File -Depth 1).Count -gt 0 -or (Get-ChildItem -Path $ProjectRoot -Filter "*.*proj" -File -Depth 2).Count -gt 0) {
    $detected.stack = "dotnet"
    $detected.language = "csharp"
    $detected.build_cmd = "dotnet build -v quiet"
    $detected.test_cmd = "dotnet test --verbosity quiet"
    $detected.test_filter_syntax = "dotnet test --verbosity quiet --filter {filter}"
    $detected.lint_cmd = ""
    $slnFile = (Get-ChildItem -Path $ProjectRoot -Filter "*.sln" -File -Depth 1 | Select-Object -First 1)
    if ($slnFile) {
        $detected.format_check_cmd = "dotnet format `"$($slnFile.Name)`" --verify-no-changes"
        $detected.format_fix_cmd = "dotnet format `"$($slnFile.Name)`""
    } else {
        $projFile = (Get-ChildItem -Path $ProjectRoot -Filter "*.*proj" -File -Depth 2 | Select-Object -First 1)
        if ($projFile) {
            $relProj = (Get-RelativePathCompat $ProjectRoot $projFile.FullName).Replace('\', '/')
            $detected.format_check_cmd = "dotnet format `"$relProj`" --verify-no-changes"
            $detected.format_fix_cmd = "dotnet format `"$relProj`""
        } else {
            $detected.format_check_cmd = "dotnet format --verify-no-changes"
            $detected.format_fix_cmd = "dotnet format"
        }
    }
    $detected.manifest_file = "Directory.Build.props / *.csproj / *.sln"
}
# 3. Node.js / TypeScript (package.json)
elseif (Test-Path (Join-Path $ProjectRoot "package.json")) {
    $isTs = (Test-Path (Join-Path $ProjectRoot "tsconfig.json"))
    $detected.stack = "node"
    $detected.language = if ($isTs) { "typescript" } else { "javascript" }
    $detected.build_cmd = "npm run build --if-present"
    $detected.test_cmd = "npm test --silent"
    $detected.test_filter_syntax = "npm test --silent -- {filter}"
    $detected.lint_cmd = "npm run lint --if-present"
    try {
        $pkgRaw = Get-Content -Path (Join-Path $ProjectRoot "package.json") -Raw -Encoding UTF8
        if ($pkgRaw -match '"format:check"\s*:') { $detected.format_check_cmd = "npm run format:check" }
        if ($pkgRaw -match '"format"\s*:') { $detected.format_fix_cmd = "npm run format" }
    } catch {}
    $detected.manifest_file = "package.json"
}
# 4. Python (pyproject.toml, requirements.txt, Pipfile)
elseif ((Test-Path (Join-Path $ProjectRoot "pyproject.toml")) -or (Test-Path (Join-Path $ProjectRoot "requirements.txt")) -or (Test-Path (Join-Path $ProjectRoot "Pipfile"))) {
    $detected.stack = "python"
    $detected.language = "python"
    $detected.build_cmd = "python -m compileall -q ."
    $detected.test_cmd = "pytest -q"
    $detected.test_filter_syntax = "pytest -q -k {filter}"
    $hasRuff = ($null -ne (Get-Command ruff -ErrorAction SilentlyContinue))
    $detected.lint_cmd = if ($hasRuff) { "ruff check -q" } else { "flake8 -q" }
    if ($hasRuff) {
        $detected.format_check_cmd = "ruff format --check -q"
        $detected.format_fix_cmd = "ruff format -q"
    }
    $detected.manifest_file = if (Test-Path (Join-Path $ProjectRoot "pyproject.toml")) { "pyproject.toml" } else { "requirements.txt" }
}
# 5. Go (go.mod)
elseif (Test-Path (Join-Path $ProjectRoot "go.mod")) {
    $detected.stack = "go"
    $detected.language = "go"
    $detected.build_cmd = "go build ./..."
    $detected.test_cmd = "go test ./..."
    $detected.test_filter_syntax = "go test -run {filter} ./..."
    $detected.lint_cmd = "golangci-lint run"
    $detected.format_check_cmd = "gofmt -l ."
    $detected.format_fix_cmd = "gofmt -w ."
    $detected.manifest_file = "go.mod"
}
# 6. Gradle (build.gradle.kts, build.gradle, settings.gradle.kts, settings.gradle)
elseif ((Test-Path (Join-Path $ProjectRoot "build.gradle.kts")) -or (Test-Path (Join-Path $ProjectRoot "build.gradle")) -or (Test-Path (Join-Path $ProjectRoot "settings.gradle.kts")) -or (Test-Path (Join-Path $ProjectRoot "settings.gradle"))) {
    $isKts = (Test-Path (Join-Path $ProjectRoot "build.gradle.kts")) -or (Test-Path (Join-Path $ProjectRoot "settings.gradle.kts"))
    $isWin = ($env:OS -eq 'Windows_NT') -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
    $gradleCmd = if ($isWin -and (Test-Path (Join-Path $ProjectRoot "gradlew.bat"))) { ".\gradlew.bat" } elseif (Test-Path (Join-Path $ProjectRoot "gradlew")) { "./gradlew" } else { "gradle" }
    $gradleRaw = ""
    $gradleFiles = Get-ChildItem -Path $ProjectRoot -Include "*.gradle", "*.gradle.kts", "libs.versions.toml" -File -Depth 2 -ErrorAction SilentlyContinue
    foreach ($gf in $gradleFiles) {
        try { $gradleRaw += "`n" + (Get-Content -Path $gf.FullName -Raw -Encoding UTF8) } catch {}
    }
    $hasSpotless = ($gradleRaw -match '(?i)spotless')
    $isKotlinLang = ($gradleRaw -match '(?i)kotlin') -or ((Get-ChildItem -Path $ProjectRoot -Filter "*.kt" -File -Depth 3 -ErrorAction SilentlyContinue).Count -gt 0)
    $detected.stack = "gradle"
    $detected.language = if ($isKotlinLang) { "kotlin" } else { "java" }
    if ($hasSpotless) {
        $detected.build_cmd = "$gradleCmd classes testClasses -x spotlessCheck -q"
        $detected.test_cmd = "$gradleCmd test -x spotlessCheck -q"
        $detected.test_filter_syntax = "$gradleCmd test --tests {filter} -x spotlessCheck -q"
        $detected.format_check_cmd = "$gradleCmd spotlessCheck -q"
        $detected.format_fix_cmd = "$gradleCmd spotlessApply -q"
    } else {
        $detected.build_cmd = "$gradleCmd classes testClasses -q"
        $detected.test_cmd = "$gradleCmd test -q"
        $detected.test_filter_syntax = "$gradleCmd test --tests {filter} -q"
    }
    $detected.lint_cmd = ""
    $detected.manifest_file = if (Test-Path (Join-Path $ProjectRoot "build.gradle.kts")) { "build.gradle.kts" } elseif (Test-Path (Join-Path $ProjectRoot "build.gradle")) { "build.gradle" } elseif ($isKts) { "settings.gradle.kts" } else { "settings.gradle" }
}
# 7. Maven (pom.xml)
elseif (Test-Path (Join-Path $ProjectRoot "pom.xml")) {
    $isWin = ($env:OS -eq 'Windows_NT') -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
    $mvnCmd = if ($isWin -and (Test-Path (Join-Path $ProjectRoot "mvnw.cmd"))) { ".\mvnw.cmd" } elseif (Test-Path (Join-Path $ProjectRoot "mvnw")) { "./mvnw" } else { "mvn" }
    $pomRaw = try { Get-Content -Path (Join-Path $ProjectRoot "pom.xml") -Raw -Encoding UTF8 } catch { "" }
    $hasSpotless = ($pomRaw -match '(?i)spotless')
    $detected.stack = "maven"
    $detected.language = "java"
    $detected.build_cmd = "$mvnCmd test-compile -q"
    $detected.test_cmd = "$mvnCmd test -q"
    $detected.test_filter_syntax = "$mvnCmd test -q -Dtest={filter}"
    $detected.lint_cmd = ""
    if ($hasSpotless) {
        $detected.format_check_cmd = "$mvnCmd spotless:check -q"
        $detected.format_fix_cmd = "$mvnCmd spotless:apply -q"
    }
    $detected.manifest_file = "pom.xml"
}

$jsonStr = $detected | ConvertTo-Json -Compress

if ($JsonOutput) {
    Write-Output $jsonStr
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Detected Tech Stack & Testrunner CLI" -ForegroundColor Cyan
    Write-Host "Root: $ProjectRoot" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Stack:          $($detected.stack)" -ForegroundColor Green
    Write-Host "  Language:       $($detected.language)" -ForegroundColor Green
    Write-Host "  Manifest:       $($detected.manifest_file)" -ForegroundColor DarkGray
    Write-Host "  Build Command:  $($detected.build_cmd)" -ForegroundColor Yellow
    Write-Host "  Test Command:   $($detected.test_cmd)" -ForegroundColor Yellow
    Write-Host "  Filter Syntax:  $($detected.test_filter_syntax)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
}
