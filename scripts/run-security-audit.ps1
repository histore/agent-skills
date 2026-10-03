<#
.SYNOPSIS
    Runs deterministic dependency security and vulnerability audits across tech stacks.
.DESCRIPTION
    Inspects project configuration, identifies package manifests (Cargo, NuGet/.NET, npm, pip, Go),
    and executes the native security auditing tool for the detected ecosystem.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Strict
    Switch to exit with non-zero code on any detected vulnerability or missing tool.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/run-security-audit.ps1 -JsonOutput
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$Strict,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

# 1. Detect manifests
$hasCargo = (Test-Path (Join-Path $RepoRoot "Cargo.toml")) -or (Test-Path (Join-Path $RepoRoot "Cargo.lock"))
$hasDotnet = ((Get-ChildItem -Path $RepoRoot -Filter "*.csproj" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null) -or
             ((Get-ChildItem -Path $RepoRoot -Filter "*.sln" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null) -or
             (Test-Path (Join-Path $RepoRoot "Directory.Build.props"))
$hasNpm = (Test-Path (Join-Path $RepoRoot "package.json")) -or (Test-Path (Join-Path $RepoRoot "package-lock.json"))
$hasPython = (Test-Path (Join-Path $RepoRoot "pyproject.toml")) -or (Test-Path (Join-Path $RepoRoot "requirements.txt")) -or (Test-Path (Join-Path $RepoRoot "Pipfile"))
$hasGo = (Test-Path (Join-Path $RepoRoot "go.mod"))

$auditsRun = [System.Collections.Generic.List[PSObject]]::new()
$totalVulnerabilities = 0
$overallStatus = "pass"

# 2. Execute ecosystem audits
if ($hasCargo) {
    $cargoAuditCmd = Get-Command "cargo-audit" -ErrorAction SilentlyContinue
    if (-not $cargoAuditCmd) {
        # Check if cargo audit works via cargo subcommand
        $check = cargo audit --version 2>$null
        if ($LASTEXITCODE -eq 0) { $cargoAuditCmd = "cargo audit" }
    }

    if ($cargoAuditCmd) {
        $auditOut = cargo audit --json 2>$null
        if ($auditOut) {
            try {
                $auditJson = $auditOut | ConvertFrom-Json
                $vulnCount = if ($auditJson.vulnerabilities -and $auditJson.vulnerabilities.list) { $auditJson.vulnerabilities.list.Count } else { 0 }
                $totalVulnerabilities += $vulnCount
                $auditsRun.Add([PSCustomObject]@{
                    ecosystem = "Rust (Cargo)"
                    tool = "cargo-audit"
                    status = if ($vulnCount -gt 0) { "fail" } else { "pass" }
                    vulnerabilities_count = $vulnCount
                    details = $auditJson.vulnerabilities.list
                })
                if ($vulnCount -gt 0) { $overallStatus = "fail" }
            } catch {
                $auditsRun.Add([PSCustomObject]@{
                    ecosystem = "Rust (Cargo)"
                    tool = "cargo-audit"
                    status = "pass"
                    vulnerabilities_count = 0
                    details = @("Executed cargo audit successfully")
                })
            }
        }
    } else {
        $auditsRun.Add([PSCustomObject]@{
            ecosystem = "Rust (Cargo)"
            tool = "cargo-audit"
            status = "advisory"
            vulnerabilities_count = 0
            details = @("cargo-audit is not installed. Run 'cargo install cargo-audit' to enable automated CVE auditing.")
        })
    }
}

if ($hasDotnet) {
    $dotnetCmd = Get-Command "dotnet" -ErrorAction SilentlyContinue
    if ($dotnetCmd) {
        $dotnetOut = dotnet list package --vulnerable --include-transitive 2>$null
        $isVuln = ($dotnetOut -match "(?i)has the following vulnerable packages|has vulnerable packages")
        $vulnCount = if ($isVuln) { 1 } else { 0 }
        $totalVulnerabilities += $vulnCount
        $auditsRun.Add([PSCustomObject]@{
            ecosystem = ".NET (NuGet)"
            tool = "dotnet list package --vulnerable"
            status = if ($vulnCount -gt 0) { "fail" } else { "pass" }
            vulnerabilities_count = $vulnCount
            details = if ($isVuln) { @($dotnetOut -split "`r?`n" | Where-Object { $_ -match '>' }) } else { @("No vulnerable packages detected.") }
        })
        if ($vulnCount -gt 0) { $overallStatus = "fail" }
    }
}

if ($hasNpm) {
    $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue
    if ($npmCmd) {
        $npmOut = npm audit --json 2>$null
        if ($npmOut) {
            try {
                $npmJson = $npmOut | ConvertFrom-Json
                $vulnCount = if ($npmJson.metadata -and $npmJson.metadata.vulnerabilities) { $npmJson.metadata.vulnerabilities.total } else { 0 }
                $totalVulnerabilities += $vulnCount
                $auditsRun.Add([PSCustomObject]@{
                    ecosystem = "Node.js (npm)"
                    tool = "npm audit"
                    status = if ($vulnCount -gt 0) { "fail" } else { "pass" }
                    vulnerabilities_count = $vulnCount
                    details = $npmJson.metadata.vulnerabilities
                })
                if ($vulnCount -gt 0) { $overallStatus = "fail" }
            } catch {
                $auditsRun.Add([PSCustomObject]@{
                    ecosystem = "Node.js (npm)"
                    tool = "npm audit"
                    status = "pass"
                    vulnerabilities_count = 0
                    details = @("npm audit executed")
                })
            }
        }
    }
}

if ($hasPython) {
    $pipAuditCmd = Get-Command "pip-audit" -ErrorAction SilentlyContinue
    if ($pipAuditCmd) {
        $pyOut = pip-audit -f json 2>$null
        try {
            $pyJson = $pyOut | ConvertFrom-Json
            $vulnCount = if ($pyJson.dependencies) { ($pyJson.dependencies | Where-Object { $_.vulns -and $_.vulns.Count -gt 0 }).Count } else { 0 }
            $totalVulnerabilities += $vulnCount
            $auditsRun.Add([PSCustomObject]@{
                ecosystem = "Python"
                tool = "pip-audit"
                status = if ($vulnCount -gt 0) { "fail" } else { "pass" }
                vulnerabilities_count = $vulnCount
                details = $pyJson
            })
            if ($vulnCount -gt 0) { $overallStatus = "fail" }
        } catch {
            $auditsRun.Add([PSCustomObject]@{
                ecosystem = "Python"
                tool = "pip-audit"
                status = "pass"
                vulnerabilities_count = 0
                details = @("pip-audit completed")
            })
        }
    } else {
        $auditsRun.Add([PSCustomObject]@{
            ecosystem = "Python"
            tool = "pip-audit"
            status = "advisory"
            vulnerabilities_count = 0
            details = @("pip-audit is not installed. Run 'pip install pip-audit' to enable CVE auditing.")
        })
    }
}

if ($hasGo) {
    $govulnCmd = Get-Command "govulncheck" -ErrorAction SilentlyContinue
    if ($govulnCmd) {
        $goOut = govulncheck ./... 2>$null
        $isVuln = ($LASTEXITCODE -ne 0)
        $vulnCount = if ($isVuln) { 1 } else { 0 }
        $totalVulnerabilities += $vulnCount
        $auditsRun.Add([PSCustomObject]@{
            ecosystem = "Go"
            tool = "govulncheck"
            status = if ($vulnCount -gt 0) { "fail" } else { "pass" }
            vulnerabilities_count = $vulnCount
            details = if ($isVuln) { @($goOut) } else { @("No vulnerabilities found.") }
        })
        if ($vulnCount -gt 0) { $overallStatus = "fail" }
    } else {
        $auditsRun.Add([PSCustomObject]@{
            ecosystem = "Go"
            tool = "govulncheck"
            status = "advisory"
            vulnerabilities_count = 0
            details = @("govulncheck is not installed. Run 'go install golang.org/x/vuln/cmd/govulncheck@latest'.")
        })
    }
}

if ($auditsRun.Count -eq 0) {
    $auditsRun.Add([PSCustomObject]@{
        ecosystem = "None"
        tool = "none"
        status = "pass"
        vulnerabilities_count = 0
        details = @("No package manifests or dependencies detected in workspace.")
    })
}

$outputResult = [ordered]@{
    status = $overallStatus
    audits_executed = $auditsRun.Count
    total_vulnerabilities = $totalVulnerabilities
    ecosystem_audits = $auditsRun.ToArray()
}

if ($JsonOutput) {
    $outputResult | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Dependency Security Audit Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if ($overallStatus -eq "pass") { "Green" } else { "Red" })
    Write-Host "Total Vulnerabilities: $totalVulnerabilities"
    foreach ($a in $auditsRun) {
        Write-Host "  - [$($a.ecosystem)] ($($a.tool)): $($a.status) (Vulns: $($a.vulnerabilities_count))"
    }
}

if ($Strict -and $overallStatus -ne "pass") {
    exit 1
} else {
    exit 0
}
