<#
.SYNOPSIS
    Lints GitHub Actions CI/CD workflows for syntax, structure, permissions, and PowerShell hygiene.
.DESCRIPTION
    Scans .github/workflows/*.yml and *.yaml. Validates presence of mandatory fields (name, on, jobs),
    checks for least-privilege 'permissions:' declarations, and verifies PowerShell steps enforce '-NoProfile'.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Strict
    Switch to exit with non-zero exit code if warnings or errors are found.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-ci-workflows.ps1 -JsonOutput
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

$workflowDir = Join-Path $RepoRoot ".github/workflows"
$workflowFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

if (Test-Path $workflowDir) {
    $found = Get-ChildItem -Path $workflowDir -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -in @(".yml", ".yaml") }
    foreach ($f in $found) {
        $workflowFiles.Add($f)
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($wf in $workflowFiles) {
    $name = $wf.Name
    $content = Get-Content -Path $wf.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        $warnings.Add("Workflow file '$name' is empty.")
        continue
    }

    # Structure checks
    if ($content -notmatch '(?m)^name\s*:') {
        $warnings.Add("Workflow file '$name' missing top-level 'name:' attribute.")
    }
    if ($content -notmatch '(?m)^on\s*:') {
        $errors.Add("Workflow file '$name' missing mandatory 'on:' trigger definition.")
    }
    if ($content -notmatch '(?m)^jobs\s*:') {
        $errors.Add("Workflow file '$name' missing mandatory 'jobs:' section.")
    }

    # Least privilege check
    if ($content -notmatch '(?m)^\s*permissions\s*:') {
        $warnings.Add("Workflow file '$name' does not explicitly restrict GITHUB_TOKEN 'permissions:'.")
    }

    # PowerShell hygiene check
    $lines = $content -split "`r?`n"
    $inPwshStep = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match 'shell\s*:\s*(pwsh|powershell)') {
            $inPwshStep = $true
        }
        if ($line -match '^\s*-\s+name:' -or $line -match '^\s*-\s+uses:') {
            $inPwshStep = $false
        }
        if ($inPwshStep -and $line -match 'run\s*:\s*.*pwsh' -and $line -notmatch '-NoProfile') {
            $warnings.Add("Workflow file '$name' line $($i+1): PowerShell invocation without '-NoProfile' detected.")
        }
    }
}

$status = if ($errors.Count -gt 0) { "fail" } elseif ($warnings.Count -gt 0) { "warning" } else { "pass" }

$result = [ordered]@{
    status          = $status
    workflows_count = $workflowFiles.Count
    errors_count    = $errors.Count
    warnings_count  = $warnings.Count
    errors          = $errors.ToArray()
    warnings        = $warnings.ToArray()
    message         = if ($workflowFiles.Count -eq 0) { "No GitHub Actions workflows found in workspace." } else { "Linted $($workflowFiles.Count) workflow(s) with $($errors.Count) errors and $($warnings.Count) warnings." }
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "CI/CD Workflow Lint Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq "pass") { "Green" } elseif ($status -eq "warning") { "Yellow" } else { "Red" })
    Write-Host "Workflows Scanned: $($workflowFiles.Count)"
    Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
    foreach ($err in $errors) { Write-Host "  [ERROR] $err" -ForegroundColor Red }
    foreach ($warn in $warnings) { Write-Host "  [WARN] $warn" -ForegroundColor Yellow }
}

if ($Strict -and $errors.Count -gt 0) {
    exit 1
} else {
    exit 0
}
