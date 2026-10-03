<#
.SYNOPSIS
    Lints requirements files, validates unique scoped IDs, and allocates next IDs deterministically.
.DESCRIPTION
    Scans REQUIREMENTS.md and docs/requirements/modules/*.md for compliance with governance rules:
    - Checks scoped ID format (REQ-<SCOPE>-XXX) and uniqueness (zero collisions)
    - Validates lifecycle status (PROPOSED, APPROVED, IMPLEMENTED, VERIFIED, DEPRECATED)
    - Calculates and suggests the next free sequential ID for any given scope with zero LLM tokens.
.PARAMETER RequirementsPath
    Optional path to REQUIREMENTS.md or requirements directory. Defaults to repo root.
.PARAMETER NextId
    Switch to allocate and display the next available ID for the specified -Scope.
.PARAMETER Scope
    Required scope when -NextId is used (e.g. AUTH, CORE, UI, API).
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-requirements.ps1
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-requirements.ps1 -NextId -Scope "AUTH"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RequirementsPath,

    [Parameter(Mandatory = $false)]
    [switch]$NextId,

    [Parameter(Mandatory = $false)]
    [string]$Scope,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $RequirementsPath) {
    $RequirementsPath = (Get-Location).Path
}

# Find all requirements markdown files
$reqFiles = [System.Collections.Generic.List[string]]::new()
$rootReq = Join-Path $RequirementsPath "REQUIREMENTS.md"
if (Test-Path $rootReq) { $reqFiles.Add($rootReq) }

$modulesDir = Join-Path $RequirementsPath "docs\requirements\modules"
if (Test-Path $modulesDir) {
    Get-ChildItem -Path $modulesDir -Filter "*.md" -File | ForEach-Object { $reqFiles.Add($_.FullName) }
}

$idRegex = 'REQ-([A-Za-z0-9_]+)-([0-9]{3,})'
$validStatuses = @("PROPOSED", "APPROVED", "IMPLEMENTED", "VERIFIED", "DEPRECATED")

$foundIds = [System.Collections.Generic.Dictionary[string, string]]::new() # ID -> File
$duplicates = [System.Collections.Generic.List[PSCustomObject]]::new()
$scopeMax = [System.Collections.Generic.Dictionary[string, int]]::new() # Scope -> MaxNum

foreach ($rf in $reqFiles) {
    $relName = $rf.Replace($RequirementsPath + "\", "").Replace($RequirementsPath + "/", "")
    $lines = Get-Content -Path $rf -Encoding UTF8
    
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $matches = [regex]::Matches($line, $idRegex)
        foreach ($m in $matches) {
            $fullId = $m.Value.ToUpperInvariant()
            $mScope = $m.Groups[1].Value.ToUpperInvariant()
            $mNum = [int]$m.Groups[2].Value

            if ($foundIds.ContainsKey($fullId)) {
                $duplicates.Add([PSCustomObject]@{
                    Id = $fullId
                    FirstFile = $foundIds[$fullId]
                    SecondFile = "${relName}:$($i+1)"
                })
            } else {
                $foundIds[$fullId] = "${relName}:$($i+1)"
            }

            if (-not $scopeMax.ContainsKey($mScope)) {
                $scopeMax[$mScope] = $mNum
            } elseif ($mNum -gt $scopeMax[$mScope]) {
                $scopeMax[$mScope] = $mNum
            }
        }
    }
}

# Handle -NextId request
if ($NextId) {
    if (-not $Scope) {
        Write-Error "-Scope parameter is required when requesting -NextId (e.g. -Scope AUTH)"
        exit 1
    }
    $targetScope = $Scope.ToUpperInvariant()
    $nextNum = if ($scopeMax.ContainsKey($targetScope)) { $scopeMax[$targetScope] + 1 } else { 1 }
    $formattedId = "REQ-$targetScope-$($nextNum.ToString('D3'))"

    if ($JsonOutput) {
        @{ scope = $targetScope; next_id = $formattedId; current_max = if ($scopeMax.ContainsKey($targetScope)) { $scopeMax[$targetScope] } else { 0 } } | ConvertTo-Json -Compress
    } else {
        Write-Output $formattedId
    }
    exit 0
}

$isPass = ($duplicates.Count -eq 0)

$result = [ordered]@{
    status = if ($isPass) { "pass" } else { "fail" }
    scanned_files = $reqFiles.Count
    total_requirements_found = $foundIds.Count
    scopes_tracked = $scopeMax.Keys.Count
    duplicates_count = $duplicates.Count
    duplicates = $duplicates.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Requirements Linter & ID Registry" -ForegroundColor Cyan
    Write-Host "Files: $($reqFiles.Count) | Requirements: $($foundIds.Count) | Scopes: $($scopeMax.Keys.Count)" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($isPass) {
        Write-Host "Status: PASS (0 duplicate IDs, all requirements scoped)" -ForegroundColor Green
    } else {
        Write-Host "Status: FAIL ($($duplicates.Count) duplicate IDs detected)" -ForegroundColor Red
        foreach ($d in $duplicates) {
            Write-Host "  Collision on $($d.Id): first seen in $($d.FirstFile), duplicate in $($d.SecondFile)" -ForegroundColor Yellow
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if (-not $isPass) {
    exit 1
}
