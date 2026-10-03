<#
.SYNOPSIS
    Lints database migration scripts for naming conventions, duplicate versions, and dangerous DDL operations.
.DESCRIPTION
    Scans repository for SQL, EF Core, Diesel/SQLx, Prisma, or Alembic migration files.
    Validates version numbering/ordering, checks for rollback parity, and flags destructive operations without safeguards.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Strict
    Switch to exit with non-zero exit code if warnings or dangerous operations are found.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-db-migrations.ps1 -JsonOutput
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

# 1. Scan for migration directories / files
$migrationFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$dirsToScan = @("migrations", "db/migrations", "sql/migrations", "src", "prisma/migrations")

foreach ($d in $dirsToScan) {
    $fullDir = Join-Path $RepoRoot $d
    if (Test-Path $fullDir) {
        $files = Get-ChildItem -Path $fullDir -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object {
                     $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|bin|obj|node_modules)[\\/]' -and
                     ($_.Extension -in @(".sql", ".cs", ".py") -and ($_.DirectoryName -match '(?i)migration|\bup\b|\bdown\b' -or $_.Name -match '^\d{3,}_|^V\d+__|\.up\.sql$|\.down\.sql$'))
                 }
        foreach ($f in $files) {
            $migrationFiles.Add($f)
        }
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$seenVersions = [System.Collections.Generic.HashSet[string]]::new()

# 2. Check for duplicate versions & dangerous operations
foreach ($file in $migrationFiles) {
    # Extract version prefix (e.g. V001__, 20240101120000_, 0001_)
    if ($file.Name -match '^([Vv]?\d+)[_\-]') {
        $ver = $Matches[1].ToUpper()
        if ($seenVersions.Contains($ver)) {
            $errors.Add("Duplicate migration version detected: '$ver' in file '$($file.Name)'")
        } else {
            [void]$seenVersions.Add($ver)
        }
    }

    # For SQL migrations, check dangerous operations and rollback symmetry
    if ($file.Extension -eq ".sql") {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            # Check for destructive commands
            if ($content -match '(?i)\bDROP\s+TABLE\b') {
                $warnings.Add("Destructive operation 'DROP TABLE' detected in '$($file.Name)' without cascade safeguard.")
            }
            if ($content -match '(?i)\bTRUNCATE(\s+TABLE)?\b') {
                $warnings.Add("Destructive operation 'TRUNCATE' detected in '$($file.Name)'.")
            }
            if ($content -match '(?i)\bALTER\s+TABLE\s+.*\bDROP\s+COLUMN\b') {
                $warnings.Add("Destructive operation 'DROP COLUMN' detected in '$($file.Name)'.")
            }
        }

        # Rollback symmetry check for .up.sql
        if ($file.Name -match '\.up\.sql$') {
            $downName = $file.Name -replace '\.up\.sql$', '.down.sql'
            $downPath = Join-Path $file.DirectoryName $downName
            if (-not (Test-Path $downPath)) {
                $warnings.Add("Reversible migration missing matching down script: '$downName' not found for '$($file.Name)'")
            }
        }
    }
}

$status = if ($errors.Count -gt 0) { "fail" } elseif ($warnings.Count -gt 0) { "warning" } else { "pass" }

$result = [ordered]@{
    status           = $status
    migrations_count = $migrationFiles.Count
    errors_count     = $errors.Count
    warnings_count   = $warnings.Count
    errors           = $errors.ToArray()
    warnings         = $warnings.ToArray()
    message          = if ($migrationFiles.Count -eq 0) { "No database migration files detected in workspace." } else { "Linted $($migrationFiles.Count) migration files with $($errors.Count) errors and $($warnings.Count) warnings." }
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Database Migration Lint Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq "pass") { "Green" } elseif ($status -eq "warning") { "Yellow" } else { "Red" })
    Write-Host "Migrations Scanned: $($migrationFiles.Count)"
    Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
    foreach ($err in $errors) { Write-Host "  [ERROR] $err" -ForegroundColor Red }
    foreach ($warn in $warnings) { Write-Host "  [WARN] $warn" -ForegroundColor Yellow }
}

if ($Strict -and ($status -ne "pass")) {
    exit 1
} else {
    exit 0
}
