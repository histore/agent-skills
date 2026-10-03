<#
.SYNOPSIS
    Lints API contract specifications (OpenAPI/Swagger, Protobuf, GraphQL) for syntax and broken references.
.DESCRIPTION
    Scans repository for OpenAPI specifications (.json, .yaml), Protocol Buffers (.proto), and GraphQL schemas (.graphql).
    Validates mandatory schema structures, verifies internal $ref pointers, and checks for duplicate Protobuf field tags.
.PARAMETER RepoRoot
    Optional path to the git repository. Defaults to current directory.
.PARAMETER Strict
    Switch to exit with non-zero exit code if errors are found.
.PARAMETER JsonOutput
    Switch to output results as raw JSON.
.EXAMPLE
    pwsh -NoProfile -File ./scripts/lint-api-contracts.ps1 -JsonOutput
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

$contractFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$allFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '[\\/](\.git|_agents|\.agents|bin|obj|node_modules|target)[\\/]' -and
                ($_.Name -match '(?i)openapi\.(json|yaml|yml)$|swagger\.(json|yaml|yml)$' -or
                 $_.Extension -in @(".proto", ".graphql", ".gql"))
            }

foreach ($f in $allFiles) {
    $contractFiles.Add($f)
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($file in $contractFiles) {
    $fileName = $file.Name
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # 1. OpenAPI JSON
    if ($fileName -match '(?i)(openapi|swagger).*\.json$') {
        try {
            $json = $content | ConvertFrom-Json
            if (-not ($json.openapi -or $json.swagger)) {
                $errors.Add("OpenAPI file '$fileName' missing root 'openapi' or 'swagger' version specification.")
            }
            if (-not $json.info) {
                $warnings.Add("OpenAPI file '$fileName' missing 'info' section.")
            }
            if (-not $json.paths) {
                $warnings.Add("OpenAPI file '$fileName' missing 'paths' section.")
            }

            # Check internal $ref pointers
            $refMatches = [regex]::Matches($content, '"\$ref"\s*:\s*"#\/([^"]+)"')
            foreach ($m in $refMatches) {
                $refPath = $m.Groups[1].Value.Split('/')
                $curr = $json
                $valid = $true
                foreach ($seg in $refPath) {
                    if ($null -ne $curr -and $curr.PSObject.Properties[$seg]) {
                        $curr = $curr.$seg
                    } else {
                        $valid = $false
                        break
                    }
                }
                if (-not $valid) {
                    $errors.Add("Broken `$ref '#/$($m.Groups[1].Value)' in '$fileName'")
                }
            }
        } catch {
            $errors.Add("Invalid JSON in OpenAPI contract '$fileName': $_")
        }
    }
    # 2. Protobuf (.proto)
    elseif ($file.Extension -eq ".proto") {
        if ($content -notmatch 'syntax\s*=\s*"proto[23]";') {
            $warnings.Add("Protobuf file '$fileName' missing explicit 'syntax = ""proto3"";' declaration.")
        }

        # Check duplicate field numbers in messages
        $messageMatches = [regex]::Matches($content, 'message\s+(\w+)\s*\{([^}]+)\}')
        foreach ($m in $messageMatches) {
            $msgName = $m.Groups[1].Value
            $body = $m.Groups[2].Value
            $seenTags = [System.Collections.Generic.HashSet[int]]::new()
            $fieldMatches = [regex]::Matches($body, '=\s*(\d+)\s*;')
            foreach ($fm in $fieldMatches) {
                $tag = [int]$fm.Groups[1].Value
                if ($seenTags.Contains($tag)) {
                    $errors.Add("Duplicate field tag '$tag' in Protobuf message '$msgName' in '$fileName'")
                } else {
                    [void]$seenTags.Add($tag)
                }
            }
        }
    }
    # 3. GraphQL (.graphql, .gql)
    elseif ($file.Extension -in @(".graphql", ".gql")) {
        if ($content -notmatch '\b(type|schema|query|mutation|input|interface|enum)\b') {
            $warnings.Add("GraphQL file '$fileName' contains no standard GraphQL type declarations.")
        }
    }
}

$status = if ($errors.Count -gt 0) { "fail" } elseif ($warnings.Count -gt 0) { "warning" } else { "pass" }

$result = [ordered]@{
    status          = $status
    contracts_count = $contractFiles.Count
    errors_count    = $errors.Count
    warnings_count  = $warnings.Count
    errors          = $errors.ToArray()
    warnings        = $warnings.ToArray()
    message         = if ($contractFiles.Count -eq 0) { "No API contract files detected in workspace." } else { "Linted $($contractFiles.Count) contract files with $($errors.Count) errors and $($warnings.Count) warnings." }
}

if ($JsonOutput) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "API Contract Lint Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq "pass") { "Green" } elseif ($status -eq "warning") { "Yellow" } else { "Red" })
    Write-Host "Contracts Scanned: $($contractFiles.Count)"
    Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
    foreach ($err in $errors) { Write-Host "  [ERROR] $err" -ForegroundColor Red }
    foreach ($warn in $warnings) { Write-Host "  [WARN] $warn" -ForegroundColor Yellow }
}

if ($Strict -and ($status -ne "pass")) {
    exit 1
} else {
    exit 0
}
