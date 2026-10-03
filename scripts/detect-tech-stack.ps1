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

$detected = [ordered]@{
    stack              = "unknown"
    language           = "unknown"
    build_cmd          = ""
    test_cmd           = ""
    test_filter_syntax = ""
    lint_cmd           = ""
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
    $detected.manifest_file = "Cargo.toml"
}
# 2. .NET (Directory.Build.props, *.sln, *.csproj)
elseif ((Test-Path (Join-Path $ProjectRoot "Directory.Build.props")) -or (Get-ChildItem -Path $ProjectRoot -Filter "*.sln" -File -Depth 1).Count -gt 0 -or (Get-ChildItem -Path $ProjectRoot -Filter "*.*proj" -File -Depth 2).Count -gt 0) {
    $detected.stack = "dotnet"
    $detected.language = "csharp"
    $detected.build_cmd = "dotnet build -v quiet"
    $detected.test_cmd = "dotnet test --verbosity quiet"
    $detected.test_filter_syntax = "dotnet test --verbosity quiet --filter {filter}"
    $detected.lint_cmd = "dotnet format --verify-no-changes"
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
    $detected.manifest_file = "package.json"
}
# 4. Python (pyproject.toml, requirements.txt, Pipfile)
elseif ((Test-Path (Join-Path $ProjectRoot "pyproject.toml")) -or (Test-Path (Join-Path $ProjectRoot "requirements.txt")) -or (Test-Path (Join-Path $ProjectRoot "Pipfile"))) {
    $detected.stack = "python"
    $detected.language = "python"
    $detected.build_cmd = "python -m compileall -q ."
    $detected.test_cmd = "pytest -q"
    $detected.test_filter_syntax = "pytest -q -k {filter}"
    $detected.lint_cmd = "flake8 -q"
    $detected.manifest_file = if (Test-Path (Join-Path $ProjectRoot "pyproject.toml")) { "pyproject.toml" } else { "requirements.txt" }
}
# 5. Go (go.mod)
elseif (Test-Path (Join-Path $ProjectRoot "go.mod")) {
    $detected.stack = "go"
    $detected.language = "go"
    $detected.build_cmd = "go build ./..."
    $detected.test_cmd = "go test -v ./..."
    $detected.test_filter_syntax = "go test -v -run {filter} ./..."
    $detected.lint_cmd = "golangci-lint run"
    $detected.manifest_file = "go.mod"
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
