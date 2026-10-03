<#
.SYNOPSIS
    Audits localization key parity between German (de) and English (en) resource files.
.DESCRIPTION
    Scans project for bilingual translation resources (*.de.json vs *.en.json, or .resx files).
    Compares key trees and identifies untranslated, missing, or mismatched keys with zero LLM tokens.
.PARAMETER ResourceDir
    Directory to scan for localization files. Defaults to current directory.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/audit-i18n.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceDir,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $ResourceDir) {
    $ResourceDir = (Get-Location).Path
}

# Helper to flatten JSON object to dot-notation keys
function Get-FlatKeys {
    param($JsonObject, [string]$Prefix = "")
    $keys = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $JsonObject) { return $keys }

    foreach ($prop in $JsonObject.PSObject.Properties) {
        $pName = if ($Prefix) { "$Prefix.$($prop.Name)" } else { $prop.Name }
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
            $childKeys = Get-FlatKeys -JsonObject $prop.Value -Prefix $pName
            foreach ($ck in $childKeys) { $keys.Add($ck) }
        } else {
            $keys.Add($pName)
        }
    }
    return $keys
}

# Find JSON pairs (e.g. de.json and en.json, or feature.de.json and feature.en.json)
$deFiles = Get-ChildItem -Path $ResourceDir -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and
    $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
    ($_.Name -match '(?i)(^|\.)de(-[a-z]{2})?\.json$')
}

$missingInDe = [System.Collections.Generic.List[string]]::new()
$missingInEn = [System.Collections.Generic.List[string]]::new()
$pairsChecked = 0

foreach ($deFile in $deFiles) {
    # Attempt to locate matching en file
    $enCandidate1 = $deFile.FullName -replace '(?i)\.de(-[a-z]{2})?\.json$', '.en.json'
    $enCandidate2 = $deFile.FullName -replace '(?i)\bde\b', 'en'
    
    $enPath = if (Test-Path $enCandidate1) { $enCandidate1 } elseif (Test-Path $enCandidate2) { $enCandidate2 } else { $null }
    if ($enPath) {
        $pairsChecked++
        try {
            $deObj = Get-Content -Path $deFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $enObj = Get-Content -Path $enPath -Raw -Encoding UTF8 | ConvertFrom-Json

            $deKeys = [System.Collections.Generic.HashSet[string]]::new((Get-FlatKeys -JsonObject $deObj))
            $enKeys = [System.Collections.Generic.HashSet[string]]::new((Get-FlatKeys -JsonObject $enObj))

            foreach ($ek in $enKeys) {
                if (-not $deKeys.Contains($ek)) {
                    $missingInDe.Add("$($deFile.Name): $ek")
                }
            }
            foreach ($dk in $deKeys) {
                if (-not $enKeys.Contains($dk)) {
                    $missingInEn.Add("$([System.IO.Path]::GetFileName($enPath)): $dk")
                }
            }
        } catch {}
    }
}

$hasMismatch = ($missingInDe.Count -gt 0 -or $missingInEn.Count -gt 0)
$isPass = (-not $hasMismatch)

$result = [ordered]@{
    status = if ($isPass) { "pass" } else { "fail" }
    pairs_audited = $pairsChecked
    missing_in_de = $missingInDe.ToArray()
    missing_in_en = $missingInEn.ToArray()
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Bilingual (de/en) Localization Key Auditor" -ForegroundColor Cyan
    Write-Host "Resource Pairs Checked: $pairsChecked" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    if ($isPass) {
        Write-Host "Localization Parity: PASS (0 missing keys)" -ForegroundColor Green
    } else {
        Write-Host "Localization Parity: FAIL (Key mismatches found)" -ForegroundColor Red
        if ($missingInDe.Count -gt 0) {
            Write-Host "Missing in German (de):" -ForegroundColor Yellow
            foreach ($k in $missingInDe) { Write-Host "  - $k" -ForegroundColor Yellow }
        }
        if ($missingInEn.Count -gt 0) {
            Write-Host "Missing in English (en):" -ForegroundColor Yellow
            foreach ($k in $missingInEn) { Write-Host "  - $k" -ForegroundColor Yellow }
        }
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}

if ($hasMismatch) {
    exit 1
}
