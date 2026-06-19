<#
.SYNOPSIS
  Benchmark de 3 métodos de file I/O × 3 runs
.DESCRIPTION
  Compara rendimiento de Get-Content, .NET StreamReader y C# Stopwatch en
  múltiples runs. Opcional: target específico o directorio con -Dir.
.PARAMETER Path
  Ruta al archivo target para benchmark.
.PARAMETER Dir
  Directorio con scripts a benchmarkear (default: gentleman-agent-gh).
.PARAMETER Runs
  Cantidad de runs (1-10, default: 3).
#>
#requires -Version 5.1

param(
  [string]$Path = "",
  [string]$Dir = "D:\gentleman-agent-gh",
  [ValidateRange(1,10)]
  [int]$Runs = 3
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Path -and $Dir) {
  # Find the largest PS1 file in the project
  $files = Get-ChildItem $Dir -Recurse -Filter "*.ps1" -File | Sort-Object Length -Descending
  if ($files.Count -eq 0) {
    Write-Host "No .ps1 files found" -ForegroundColor Red
    exit 1
  }
  $Path = $files[0].FullName
  Write-Host "Auto-selected: $Path ($($files[0].Length) bytes)"
}

if (-not (Test-Path $Path)) {
  Write-Host "File not found: $Path" -ForegroundColor Red
  exit 1
}

Write-Host "=== FILE I/O BENCHMARK ===" -ForegroundColor Cyan
Write-Host "Target: $Path ($((Get-Item $Path).Length) bytes)"
Write-Host "Runs: $Runs"
Write-Host "Methods: Get-Content | Read raw | StreamReader"
Write-Host ""

$methods = @(
  @{name="Get-Content (cmdlet)"; script={
    param($f) Get-Content -Path $f -Raw -Encoding utf8
  }}
  @{name="Read raw bytes + UTF8"; script={
    param($f) [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
  }}
  @{name="StreamReader"; script={
    param($f)
    $sr = New-Object System.IO.StreamReader($f, [System.Text.Encoding]::UTF8)
    try {
      $content = $sr.ReadToEnd()
    } finally {
      $sr.Close()
    }
    $content
  }}
)

$allResults = @()

foreach ($method in $methods) {
  Write-Host "--- $($method.name) ---" -ForegroundColor Yellow
  $times = @()
  $sizes = @()

  1..$Runs | ForEach-Object {
    # Warm-up: 1 run
    & $method.script $Path > $null

    $content = $null
    $ms = Measure-Command {
      $value = & $method.script $Path
      Set-Variable -Name content -Value $value -Scope 1
    }
    $elapsed = $ms.TotalMilliseconds
    $times += $elapsed
    $sizes += $content.Length
    Write-Host "  Run $_ : ${elapsed}ms | ${($content.Length/1KB).ToString('F1')} KB"
  }

  $avg = ($times | Measure-Object -Average).Average
  $min = ($times | Measure-Object -Minimum).Minimum
  $max = ($times | Measure-Object -Maximum).Maximum

  $allResults += [PSCustomObject]@{
    Method = $method.name
    AvgMs = [math]::Round($avg, 1)
    MinMs = [math]::Round($min, 1)
    MaxMs = [math]::Round($max, 1)
    AvgKB = [math]::Round(($sizes | Measure-Object -Average).Average / 1KB, 1)
  }

  Write-Host "  >> AVG: ${avg}ms (min ${min} / max ${max})" -ForegroundColor Green
  Write-Host ""
}

Write-Host "=== I/O BENCHMARK SUMMARY ===" -ForegroundColor Cyan
$allResults | Format-Table Method, AvgMs, MinMs, MaxMs, AvgKB -AutoSize

# Identify fastest
if ($allResults.Count -gt 0) {
  $fastest = $allResults | Sort-Object AvgMs | Select-Object -First 1
  Write-Host "Fastest: $($fastest.Method) @ $($fastest.AvgMs)ms" -ForegroundColor Green
}
