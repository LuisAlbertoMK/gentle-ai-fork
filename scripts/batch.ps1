#requires -Version 5.1
<#
.SYNOPSIS
  Create a new auto-incremented batch entry - log to BITACORA.md, increment inter-track.
  Designed for the !batch workflow shortcut.
.DESCRIPTION
  Reads BITACORA.md to find the latest batch number, increments it,
  appends a new entry with today date and description, and increments inter-track.
.PARAMETER Description
  Description of the batch (e.g. "Karpathy compress 4 skills + score update").
.PARAMETER Quiet
  Output JSON only (machine-readable).
.PARAMETER Show
  Show current batch number without creating a new entry.
.EXAMPLE
  .\scripts\batch.ps1 -Description "Karpathy compress 4 skills, score update"
.EXAMPLE
  .\scripts\batch.ps1 -Show
.EXAMPLE
  .\scripts\batch.ps1 -Description "Fix cross-ref errors" -Quiet
#>
param(
    [string]$Description = "",
    [switch]$Quiet,
    [switch]$Show
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$bitacoraPath = Join-Path -Path $repoRoot -ChildPath "BITACORA.md"
$interTrack = Join-Path -Path $repoRoot -ChildPath "scripts/inter-track.ps1"

function Get-LatestBatchNumber {
    if (-not (Test-Path -LiteralPath $bitacoraPath)) { return 0 }
    $content = Get-Content -LiteralPath $bitacoraPath -Raw
    $batchMatches = [regex]::Matches($content, "Batch (\d+)")
    if ($batchMatches.Count -eq 0) { return 0 }
    return ($batchMatches | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum
}

$currentBatch = Get-LatestBatchNumber

if ($Show) {
    $nextBatch = $currentBatch + 1
    if ($Quiet) {
        Write-Output "{""current"":$currentBatch,""next"":$nextBatch}"
    } else {
        Write-Host "Current batch: $currentBatch | Next batch: $nextBatch" -ForegroundColor Cyan
    }
    return
}

if (-not $Description) {
    Write-Error "Description is required. Use -Description 'your batch description'"
    exit 1
}

$nextBatch = $currentBatch + 1
$today = Get-Date -Format "yyyy-MM-dd"

$entry = "$today - Batch $($nextBatch): $Description"
$existingContent = Get-Content -LiteralPath $bitacoraPath -Raw
$newContent = "$entry`r`n$existingContent"
Set-Content -LiteralPath $bitacoraPath -Value $newContent -Encoding UTF8

if (Test-Path -LiteralPath $interTrack) {
    & $interTrack -Increment -Quiet
}

if (-not $Quiet) {
    Write-Host "=== BATCH $nextBatch CREATED ===" -ForegroundColor Green
    Write-Host "$Description" -ForegroundColor Green
}

$result = [PSCustomObject]@{
    batch       = $nextBatch
    date        = $today
    description = $Description
    bitacora    = "BITACORA.md"
}

if ($Quiet) {
    $result | ConvertTo-Json
}
