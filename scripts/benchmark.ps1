#requires -Version 5.1

<#
.SYNOPSIS
  Benchmark system — score skill fitness, system health, track trends.

.DESCRIPTION
  Runs automated benchmarks on the skill ecosystem and system health.
  Supports snapshot mode (save state) and gate mode (compare vs latest).

.PARAMETER Snapshot
  Save current state as a benchmark snapshot.

.PARAMETER Gate
  Compare current state vs latest snapshot; warn on regressions.

.PARAMETER Json
  Output results as JSON.

.EXAMPLE
  .\scripts\benchmark.ps1                   # Report only
  .\scripts\benchmark.ps1 -Snapshot         # Save snapshot
  .\scripts\benchmark.ps1 -Gate             # Compare vs latest
  .\scripts\benchmark.ps1 -Snapshot -Json   # Save and output JSON
#>

param(
  [switch]$Snapshot,
  [switch]$Gate,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$canonicalDir = Join-Path -Path $repoRoot -ChildPath ".agents\skills"
$agentsMd = Join-Path -Path $repoRoot -ChildPath "AGENTS.md"
$scriptsDir = Join-Path -Path $repoRoot -ChildPath "scripts"
$snapDir = Join-Path -Path $repoRoot -ChildPath "docs\metricas\snapshots"

# --- Helpers ---
function Get-SkillStat($dir) {
  $skills = Get-ChildItem $dir -Directory | Where-Object { $_.Name -ne '_shared' }
  $results = @()
  foreach ($s in $skills) {
    $md = Join-Path $s.FullName "SKILL.md"
    if (-not (Test-Path $md)) { continue }
    $content = Get-Content $md -Raw
    $lines = ($content -split "`n").Count
    $bytes = $content.Length
    $hasFront = $content -match "^---"
    $hasWhen = $content -match "(?m)^## When to Use"
    $hasRules = $content -match "(?m)^## (Rules|Critical Rules)"
    $results += [PSCustomObject]@{
      Name = $s.Name
      Bytes = $bytes
      Lines = $lines
      Frontmatter = $hasFront
      WhenToUse = $hasWhen
      Rules = $hasRules
    }
  }
  return $results
}

function Get-SystemStat($skills) {
  $agentsMdContent = if (Test-Path $agentsMd) { Get-Content $agentsMd -Raw } else { "" }
  $scripts = @(Get-ChildItem $scriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue)
  $globalDir = "$env:USERPROFILE\.config\opencode\skills"
  $junctionsOk = 0
  if (Test-Path $globalDir) {
    foreach ($s in $skills) {
      $item = Get-Item (Join-Path $globalDir $s.Name) -ErrorAction SilentlyContinue
      if ($item -and $item.LinkType -eq "Junction") { $junctionsOk++ }
    }
  }

  $allBytes = ($skills | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum
  $allLines = ($skills | ForEach-Object { $_.Lines } | Measure-Object -Sum).Sum
  $over3kb = @(@($skills | Where-Object { $_.Bytes -gt 3072 })).Count
  $sortedBytes = $skills | ForEach-Object { $_.Bytes } | Sort-Object
  $count = $sortedBytes.Count
  $median = if ($count -gt 0) {
    if ($count % 2 -eq 1) { $sortedBytes[($count-1)/2] }
    else { [math]::Round(($sortedBytes[$count/2-1] + $sortedBytes[$count/2]) / 2) }
  } else { 0 }

  return [PSCustomObject]@{
    AgentsMdBytes = [int]($agentsMdContent.Length)
    AgentsMdLines = ($agentsMdContent -split "`n").Count
    TotalSkills = $skills.Count
    TotalSkillBytes = [int]$allBytes
    TotalSkillLines = [int]$allLines
    SkillsOver3kb = $over3kb
    AvgSkillBytes = if ($count -gt 0) { [math]::Round($allBytes / $count) } else { 0 }
    MedianSkillBytes = $median
    MinSkillBytes = if ($count -gt 0) { $sortedBytes[0] } else { 0 }
    MaxSkillBytes = if ($count -gt 0) { $sortedBytes[-1] } else { 0 }
    ScriptsCount = $scripts.Count
    GlobalJunctionsOk = $junctionsOk
    FrontmatterPct = if ($count -gt 0) { [math]::Round((@($skills | Where-Object { $_.Frontmatter }).Count) / $count * 100, 1) } else { 0 }
    WhenToUsePct = if ($count -gt 0) { [math]::Round((@($skills | Where-Object { $_.WhenToUse }).Count) / $count * 100, 1) } else { 0 }
    RulesPct = if ($count -gt 0) { [math]::Round((@($skills | Where-Object { $_.Rules }).Count) / $count * 100, 1) } else { 0 }
  }
}

# --- Main ---
if (-not (Test-Path $canonicalDir)) { Write-Error "Canonical skills dir not found: $canonicalDir"; exit 2 }

$skills = Get-SkillStat $canonicalDir
$system = Get-SystemStat $skills
$commit = try { $c = (git rev-parse --short HEAD 2>$null); if ($c) { $c.Trim() } else { "unknown" } } catch { "unknown" }

$timestamp = (Get-Date -Format "o")
$snapHash = @{
  version = "1.0"
  timestamp = $timestamp
  commit = "$commit"
  system = $system
}

# --- Snapshot mode ---
if ($Snapshot) {
  if (-not (Test-Path $snapDir)) { New-Item -ItemType Directory -Path $snapDir -Force | Out-Null }
  $filename = "{0:yyyyMMdd-HHmmss}_benchmark.json" -f (Get-Date)
  $filePath = Join-Path $snapDir $filename
  $snapHash | ConvertTo-Json -Depth 3 | Set-Content -Path $filePath -Encoding UTF8
  # Copy as LATEST
  $latestPath = Join-Path $snapDir "LATEST_benchmark.json"
  $snapHash | ConvertTo-Json -Depth 3 | Set-Content -Path $latestPath -Encoding UTF8
  if (-not $Json) { Write-Output "Snapshot saved: $filePath" }
}

# --- Gate mode: compare vs LATEST ---
if ($Gate) {
  $latestPath = Join-Path $snapDir "LATEST_benchmark.json"
  $regressions = @()
  if (Test-Path $latestPath) {
    try {
      $prev = Get-Content $latestPath -Raw | ConvertFrom-Json
      $s = $system
      $p = $prev.system
      # Check regressions
      if ($s.AgentsMdBytes -gt $p.AgentsMdBytes * 1.1) { $regressions += "AGENTS.md grew >10% ($($p.AgentsMdBytes)→$($s.AgentsMdBytes))" }
      if ($s.TotalSkillBytes -gt $p.TotalSkillBytes * 1.05) { $regressions += "Total skill bytes grew >5% ($($p.TotalSkillBytes)→$($s.TotalSkillBytes))" }
      if ($s.SkillsOver3kb -gt $p.SkillsOver3kb) { $regressions += "Skills >3KB increased ($($p.SkillsOver3kb)→$($s.SkillsOver3kb))" }
      if ($s.GlobalJunctionsOk -lt $p.GlobalJunctionsOk) { $regressions += "Global junctions decreased ($($p.GlobalJunctionsOk)→$($s.GlobalJunctionsOk))" }
    } catch {
      Write-Debug "benchmark: no previous snapshot ($($_.Exception.Message))"
    }
  }
  if ($regressions.Count -gt 0) {
    Write-Output "BENCHMARK REGRESSIONS:"
    $regressions | ForEach-Object { Write-Output "  - $_" }
  } else {
    $s = $system
    Write-Output ("  AGENTS.md: {0}B ({1} lines)" -f $s.AgentsMdBytes, $s.AgentsMdLines)
    Write-Output ("  Skills: {0} | Total: {1}B ({2} lines)" -f $s.TotalSkills, $s.TotalSkillBytes, $s.TotalSkillLines)
    Write-Output ("  >3KB: {0} | Junctions: {1}/{2}" -f $s.SkillsOver3kb, $s.GlobalJunctionsOk, $s.TotalSkills)
    Write-Output ("  Avg: {0}B | Median: {1}B | Range: {2}-{3}B" -f $s.AvgSkillBytes, $s.MedianSkillBytes, $s.MinSkillBytes, $s.MaxSkillBytes)
    Write-Output ("  Frontmatter: {0}% | WhenToUse: {1}% | Rules: {2}%" -f $s.FrontmatterPct, $s.WhenToUsePct, $s.RulesPct)
    Write-Output ("  Scripts: {0}" -f $s.ScriptsCount)
  }
  if (-not $Json) {
    Write-Output "   Skills: $($system.TotalSkills) | Total: $($system.TotalSkillBytes)B | >3KB: $($system.SkillsOver3kb) | Junctions: $($system.GlobalJunctionsOk)/$($system.TotalSkills)"
  }
}

# --- Report (default) ---
if (-not $Snapshot -and -not $Gate -or $Json) {
  $output = @{
    timestamp = $timestamp
commit = "$commit"
    system = $system
  }
  if ($Json) { Write-Output ($output | ConvertTo-Json -Depth 3) }
  else {
    Write-Output "=== System Benchmark ==="
    Write-Output "  Commit: $commit"
    Write-Output "  AGENTS.md: $($system.AgentsMdBytes)B ($($system.AgentsMdLines) lines)"
    Write-Output "  Skills: $($system.TotalSkills) | Total: $($system.TotalSkillBytes)B ($($system.TotalSkillLines) lines)"
    Write-Output "  >3KB: $($system.SkillsOver3kb) | Junctions: $($system.GlobalJunctionsOk)/$($system.TotalSkills)"
    Write-Output "  Avg: $($system.AvgSkillBytes)B | Median: $($system.MedianSkillBytes)B | Range: $($system.MinSkillBytes)-$($system.MaxSkillBytes)B"
    Write-Output "  Frontmatter: $($system.FrontmatterPct)% | WhenToUse: $($system.WhenToUsePct)% | Rules: $($system.RulesPct)%"
    Write-Output "  Scripts: $($system.ScriptsCount)"
  }
}
