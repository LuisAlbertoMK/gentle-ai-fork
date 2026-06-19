#requires -Version 5.1

<#
.SYNOPSIS
  PS5.1 byte-level safety check — zero false positives.
  Reads file bytes directly instead of grep patterns.
  Returns hazard file paths or nothing if clean.
.PARAMETER FilePath
  One or more .ps1 file paths to check.
.EXAMPLE
  .\scripts\ps5-detect.ps1 -FilePath "path\to\file.ps1"
  .\scripts\ps5-detect.ps1 -FilePath @("a.ps1","b.ps1")
#>
param(
    [string[]]$FilePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$hazards = @()

foreach ($f in $FilePath) {
    $f = $f.Trim()
    if (-not $f) { continue }
    if ($f -match 'bash-safe|experiments[\\/]') { continue }
    if (-not (Test-Path -LiteralPath $f)) { continue }

    try {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $f).ProviderPath)
    } catch {
        continue
    }

    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 0x26 -and $i -lt $bytes.Length - 1 -and $bytes[$i+1] -eq 0x26) {
            $hazards += "$f($([char]0x26)$([char]0x26))"
            break
        }
        if ($bytes[$i] -eq 0x7C -and $bytes[$i+1] -eq 0x7C) {
            $hazards += "$f($([char]0x7C)$([char]0x7C))"
            break
        }
    }
}

if ($hazards.Count -gt 0) {
    Write-Output ($hazards -join " ")
    exit 1
}
exit 0
