<#
.SYNOPSIS
  Cuenta tokens aproximados en archivos (4 chars = 1 token)
.DESCRIPTION
  Estimación rápida de tokens usando heurística chars/4. Soporta múltiples
  archivos, directorios y búsqueda recursiva.
.PARAMETER Path
  Archivo(s) específico(s) a contar.
.PARAMETER Dir
  Directorio a escanear (default: skills/).
.PARAMETER Recurse
  Buscar recursivamente en subdirectorios.
#>
#requires -Version 5.1

param(
  [string[]]$Path = @(),
  [string]$Dir = "",
  [switch]$Recurse
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Rough token counter: ~4 chars per token for code/text
function Get-TokenCount {
  param([string]$Content)
  # Strip whitespace, count ~4 chars/token
  $clean = $Content -replace '\s+', ' '
  return [math]::Max(1, [int]($clean.Length / 4))
}

$targets = @()

if ($Dir) {
  $targets = Get-ChildItem -Path $Dir -File -Recurse:$Recurse
} elseif ($Path.Count -gt 0) {
  $targets = $Path | ForEach-Object {
    if (Test-Path $_ -PathType Container) {
      Get-ChildItem $_ -File -Recurse
    } else {
      Get-Item $_
    }
  }
} else {
  # Default: current dir, non-recursive
  $targets = Get-ChildItem -Path "." -File
}

$grandTotal = 0
$results = @()
$maxNameLen = 0

foreach ($f in $targets) {
  $content = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $content) { continue }
  $tokens = Get-TokenCount $content
  $results += [PSCustomObject]@{
    File = $f.FullName
    Tokens = $tokens
    SizeKB = [math]::Round($f.Length / 1KB, 1)
  }
  $grandTotal += $tokens
  if ($f.FullName.Length -gt $maxNameLen) { $maxNameLen = $f.FullName.Length }
}

# Sort by tokens descending
$results = $results | Sort-Object Tokens -Descending

Write-Host "=== TOKEN COUNT ===" -ForegroundColor Cyan
$results | ForEach-Object {
  Write-Host ("  {0,-$($maxNameLen+2)} {1,7} tokens  ({2,6} KB)") -f $_.File, $_.Tokens, $_.SizeKB
}
Write-Host ("  {0,-$($maxNameLen+2)} {1,7} tokens  TOTAL") -f "---", $grandTotal -ForegroundColor Green

return $grandTotal
