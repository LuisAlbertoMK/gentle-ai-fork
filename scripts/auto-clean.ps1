#requires -Version 5.1

<#
.SYNOPSIS
  Delete opencode temp files older than 24h.
.DESCRIPTION
  Runs at session start per AGENTS.md auto-clean rule. Scans $env:LOCALAPPDATA\Temp\opencode
  and removes files older than -MaxAgeHours. Reports count + size.
.PARAMETER MaxAgeHours
  Age threshold in hours (default: 24).
.PARAMETER TempDir
  Temp directory path (default: $env:LOCALAPPDATA\Temp\opencode).
.EXAMPLE
  powershell -File auto-clean.ps1
  powershell -File auto-clean.ps1 -MaxAgeHours 48
#>

param(
    [int]$MaxAgeHours = 24,
    [string]$TempDir = "$env:LOCALAPPDATA\Temp\opencode"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Verify dir exists
if (-not (Test-Path $TempDir)) {
    Write-Host "[auto-clean] No temp dir: $TempDir" -ForegroundColor Yellow
    exit 0
}

# Find files older than threshold
$cutoff = (Get-Date).AddHours(-$MaxAgeHours)
$oldFiles = Get-ChildItem -Path $TempDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }

if (-not $oldFiles) {
    Write-Host "[auto-clean] 0 files older than $MaxAgeHours h" -ForegroundColor Green
    exit 0
}

# Delete
$count = 0
$size = 0
foreach ($f in $oldFiles) {
    $size += $f.Length
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    $count++
}

$sizeMB = [math]::Round($size / 1MB, 2)
Write-Host "[auto-clean] Deleted $count files ($sizeMB MB) older than $MaxAgeHours h" -ForegroundColor Cyan
