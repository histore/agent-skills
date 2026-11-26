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
    support_level      = "full"
    support_gaps       = @()
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
# 2. .NET (Directory.Build.props, *.sln, *.csproj, *.fsproj)
elseif ((Test-Path (Join-Path $ProjectRoot "Directory.Build.props")) -or (@(Get-ChildItem -Path $ProjectRoot -Filter "*.sln" -File -Depth 1).Count -gt 0 -and @(Get-ChildItem -Path $ProjectRoot -Filter "*.vcxproj" -File -Depth 2).Count -eq 0) -or @(Get-ChildItem -Path $ProjectRoot -Include "*.csproj", "*.fsproj" -File -Depth 2).Count -gt 0) {
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
    $gradleBuildRaw = ""
    $gradleCatalogRaw = ""
    $gradleFiles = Get-ChildItem -Path $ProjectRoot -Include "*.gradle", "*.gradle.kts", "libs.versions.toml" -File -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.gradle|build|_agents|\.agents)[\\/]' }
    foreach ($gf in $gradleFiles) {
        try {
            $content = Get-Content -Path $gf.FullName -Raw -Encoding UTF8
            if ($gf.Name -ieq "libs.versions.toml") {
                $gradleCatalogRaw += "`n" + $content
            } else {
                $gradleBuildRaw += "`n" + $content
            }
        } catch {}
    }
    $gradleRaw = $gradleBuildRaw + "`n" + $gradleCatalogRaw
    $hasSpotless = ($gradleRaw -match '(?i)spotless')
    $hasDetekt = ($gradleRaw -match '(?i)detekt')
    $hasKtlint = ($gradleRaw -match '(?i)ktlint')
    $isAndroid = ($gradleRaw -match '(?i)com\.android\.(application|library)')
    $hasKmpSourceDir = (@(Get-ChildItem -Path $ProjectRoot -Directory -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.gradle|build|_agents|\.agents)[\\/]' -and $_.Name -in @("commonMain", "desktopMain", "jvmMain") }).Count -gt 0)
    $isKmp = ($gradleBuildRaw -match '(?i)(kotlin\s*\(\s*["'']multiplatform["'']\s*\)|org\.jetbrains\.kotlin\.multiplatform|alias\s*\([^)]*kotlin[._-]?multiplatform)') -or
             ($gradleCatalogRaw -match '(?i)org\.jetbrains\.kotlin\.multiplatform') -or
             $hasKmpSourceDir
    $isKotlinLang = $isKmp -or ($gradleRaw -match '(?i)kotlin') -or (@(Get-ChildItem -Path $ProjectRoot -Filter "*.kt" -File -Depth 3 -ErrorAction SilentlyContinue).Count -gt 0)
    $detected.language = if ($isKotlinLang) { "kotlin" } else { "java" }
    $spotlessExcl = if ($hasSpotless) { " -x spotlessCheck" } else { "" }

    if ($isKmp) {
        $detected.stack = "kmp-gradle"
        $jvmTargets = [System.Collections.Generic.List[string]]::new()
        $namedMatches = [regex]::Matches($gradleBuildRaw, '(?i)\bjvm\s*\(\s*(?:name\s*=\s*)?["'']([A-Za-z][A-Za-z0-9_-]*)["'']\s*\)')
        foreach ($nm in $namedMatches) {
            $tName = $nm.Groups[1].Value
            if ($jvmTargets -notcontains $tName) { $jvmTargets.Add($tName) }
        }
        if ($gradleBuildRaw -match '(?i)(?<![A-Za-z0-9_.])jvm\s*(?:\(\s*\)|\{)') {
            if ($jvmTargets -notcontains "jvm") { $jvmTargets.Add("jvm") }
        }
        if ($jvmTargets.Count -eq 0) {
            $hasDesktopSrc = ($gradleBuildRaw -match '(?i)\bdesktopMain\b') -or (@(Get-ChildItem -Path $ProjectRoot -Directory -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/](\.git|\.gradle|build|_agents|\.agents)[\\/]' -and $_.Name -eq "desktopMain" }).Count -gt 0)
            $hasJvmSrc = ($gradleBuildRaw -match '(?i)\bjvmMain\b') -or (@(Get-ChildItem -Path $ProjectRoot -Directory -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/](\.git|\.gradle|build|_agents|\.agents)[\\/]' -and $_.Name -eq "jvmMain" }).Count -gt 0)
            if ($hasDesktopSrc) { $jvmTargets.Add("desktop") }
            if ($hasJvmSrc) { $jvmTargets.Add("jvm") }
        }

        if ($jvmTargets.Count -gt 0) {
            $buildTasks = ($jvmTargets | ForEach-Object { "${_}MainClasses ${_}TestClasses" }) -join " "
            $testTasks = ($jvmTargets | ForEach-Object { "${_}Test" }) -join " "
            $primaryTarget = $jvmTargets[0]
            $detected.build_cmd = "$gradleCmd $buildTasks$spotlessExcl -q"
            $detected.test_cmd = "$gradleCmd $testTasks$spotlessExcl -q"
            $detected.test_filter_syntax = "$gradleCmd ${primaryTarget}Test --tests {filter}$spotlessExcl -q"
            $detected.lint_cmd = if ($hasDetekt) { "$gradleCmd detekt -q" } else { "" }
        } elseif ($isAndroid) {
            $detected.build_cmd = "$gradleCmd testDebugUnitTestClasses$spotlessExcl -q"
            $detected.test_cmd = "$gradleCmd testDebugUnitTest$spotlessExcl -q"
            $detected.test_filter_syntax = "$gradleCmd testDebugUnitTest --tests {filter}$spotlessExcl -q"
            $detected.lint_cmd = "$gradleCmd lintDebug -q"
        } else {
            $detected.build_cmd = "$gradleCmd assemble$spotlessExcl -q"
            $detected.test_cmd = "$gradleCmd allTests$spotlessExcl -q"
            $detected.test_filter_syntax = "$gradleCmd allTests$spotlessExcl -q"
            $detected.lint_cmd = if ($hasDetekt) { "$gradleCmd detekt -q" } else { "" }
        }
    } elseif ($isAndroid) {
        $detected.stack = "android-gradle"
        $detected.build_cmd = "$gradleCmd testDebugUnitTestClasses$spotlessExcl -q"
        $detected.test_cmd = "$gradleCmd testDebugUnitTest$spotlessExcl -q"
        $detected.test_filter_syntax = "$gradleCmd testDebugUnitTest --tests {filter}$spotlessExcl -q"
        $detected.lint_cmd = "$gradleCmd lintDebug -q"
    } else {
        $detected.stack = "gradle"
        $detected.build_cmd = "$gradleCmd classes testClasses$spotlessExcl -q"
        $detected.test_cmd = "$gradleCmd test$spotlessExcl -q"
        $detected.test_filter_syntax = "$gradleCmd test --tests {filter}$spotlessExcl -q"
        $detected.lint_cmd = if ($hasDetekt) { "$gradleCmd detekt -q" } else { "" }
    }
    if ($hasSpotless) {
        $detected.format_check_cmd = "$gradleCmd spotlessCheck -q"
        $detected.format_fix_cmd = "$gradleCmd spotlessApply -q"
    } elseif ($hasKtlint) {
        $detected.format_check_cmd = "$gradleCmd ktlintCheck -q"
        $detected.format_fix_cmd = "$gradleCmd ktlintFormat -q"
    }
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
# 8. C++ / CMake / MinGW / MSVC / Qt (CMakeLists.txt, CMakePresets.json, *.vcxproj)
elseif ((Test-Path (Join-Path $ProjectRoot "CMakeLists.txt")) -or (Test-Path (Join-Path $ProjectRoot "CMakePresets.json")) -or @(Get-ChildItem -Path $ProjectRoot -Filter "*.vcxproj" -File -Depth 2).Count -gt 0) {
    $hasCMake = (Test-Path (Join-Path $ProjectRoot "CMakeLists.txt")) -or (Test-Path (Join-Path $ProjectRoot "CMakePresets.json"))
    $hasClangTidy = ($null -ne (Get-Command clang-tidy -ErrorAction SilentlyContinue))
    $hasCppcheck = ($null -ne (Get-Command cppcheck -ErrorAction SilentlyContinue))
    $hasClangFormat = ($null -ne (Get-Command clang-format -ErrorAction SilentlyContinue))
    $detected.language = "cpp"
    if ($hasCMake) {
        $cmakeRaw = ""
        if (Test-Path (Join-Path $ProjectRoot "CMakeLists.txt")) { $cmakeRaw += (Get-Content -Path (Join-Path $ProjectRoot "CMakeLists.txt") -Raw -Encoding UTF8) }
        if (Test-Path (Join-Path $ProjectRoot "CMakePresets.json")) { $cmakeRaw += "`n" + (Get-Content -Path (Join-Path $ProjectRoot "CMakePresets.json") -Raw -Encoding UTF8) }
        $isMingw = ($cmakeRaw -match '(?i)mingw|g\+\+|gcc') -or (($null -ne (Get-Command g++ -ErrorAction SilentlyContinue)) -and ($null -eq (Get-Command cl -ErrorAction SilentlyContinue)))
        $detected.stack = if ($isMingw) { "cmake-mingw" } else { "cmake-msvc" }
        $detected.build_cmd = "cmake --build build"
        $detected.test_cmd = "ctest --test-dir build --output-on-failure"
        $detected.test_filter_syntax = "ctest --test-dir build --output-on-failure -R {filter}"
        $detected.manifest_file = if (Test-Path (Join-Path $ProjectRoot "CMakePresets.json")) { "CMakePresets.json" } else { "CMakeLists.txt" }
    } else {
        $detected.stack = "msbuild"
        $detected.build_cmd = "msbuild -v:quiet"
        $detected.test_cmd = "ctest --output-on-failure"
        $detected.test_filter_syntax = "ctest --output-on-failure -R {filter}"
        $detected.manifest_file = "*.vcxproj"
    }
    $detected.lint_cmd = if ($hasClangTidy) { "clang-tidy" } elseif ($hasCppcheck) { "cppcheck --quiet ." } else { "" }
    if ($hasClangFormat) {
        $detected.format_check_cmd = "clang-format --dry-run --Werror"
        $detected.format_fix_cmd = "clang-format -i"
    }
}

# Compute deterministic support_level & support_gaps (FEAT-TOOL-004)
$gaps = [System.Collections.Generic.List[string]]::new()
$archSupportedLangs = @("rust", "csharp", "typescript", "javascript", "python", "go", "kotlin", "java", "cpp")
if ($detected.stack -eq "unknown") {
    $codeSample = Get-ChildItem -Path $ProjectRoot -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|node_modules|build|target)[\\/]' -and $_.Extension -match '^\.(dart|swift|php|rb|zig|scala|ex|exs|rs|cs|ts|js|py|go|kt|java|cpp|c|qml)$' } |
        Select-Object -First 1
    if ($codeSample) {
        $extLangMap = @{ ".dart" = "dart"; ".swift" = "swift"; ".php" = "php"; ".rb" = "ruby"; ".zig" = "zig"; ".scala" = "scala"; ".ex" = "elixir"; ".exs" = "elixir" }
        $extKey = $codeSample.Extension.ToLowerInvariant()
        if ($extLangMap.ContainsKey($extKey)) { $detected.language = $extLangMap[$extKey] }
        $gaps.Add("no_build_or_test_runner")
        if ($archSupportedLangs -notcontains $detected.language) {
            $gaps.Add("unsupported_clean_arch_or_outline:$($detected.language)")
        }
        $detected.support_level = "unsupported"
    } else {
        $detected.support_level = "full"
    }
} else {
    if ([string]::IsNullOrWhiteSpace($detected.lint_cmd) -and $detected.stack -ne "dotnet") {
        $gaps.Add("lint_cmd_missing")
    }
    if ([string]::IsNullOrWhiteSpace($detected.format_check_cmd)) {
        $gaps.Add("format_check_cmd_missing")
    }
    if ($archSupportedLangs -notcontains $detected.language) {
        $gaps.Add("unsupported_clean_arch_or_outline:$($detected.language)")
    }
    $detected.support_level = if ($gaps.Count -gt 0) { "partial" } else { "full" }
}
$detected.support_gaps = $gaps.ToArray()

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
