#requires -Version 5.1

<#
.SYNOPSIS
  Trend dashboard — visualize benchmark history from snapshot files.

.DESCRIPTION
  Reads all snapshot JSON files from docs/metricas/snapshots/ and outputs
  a markdown trend report showing how system metrics evolved over time.

.PARAMETER SnapshotsDir
  Custom snapshots directory. Default: docs/metricas/snapshots/

.EXAMPLE
  .\scripts\trend.ps1
  .\scripts\trend.ps1 -SnapshotsDir "custom/metrics"
#>

param(
  [string]$SnapshotsDir = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Resolve paths ---
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
if (-not $SnapshotsDir) {
  $SnapshotsDir = Join-Path $repoRoot "docs\metricas\snapshots"
}

if (-not (Test-Path $SnapshotsDir)) {
  Write-Error ("Snapshots dir not found: {0}" -f $SnapshotsDir)
  exit 1
}

# --- Load snapshots ---
$snapFiles = @(Get-ChildItem -Path $SnapshotsDir -Filter "*.json" | Where-Object { $_.Name -ne "LATEST_benchmark.json" } | Sort-Object LastWriteTime)

if ($snapFiles.Count -eq 0) {
  Write-Output "No snapshots found in $SnapshotsDir"
  exit 0
}

# --- Parse snapshots ---
$snapshots = @()
foreach ($f in $snapFiles) {
  $raw = Get-Content -LiteralPath $f.FullName -Raw
  $data = $raw | ConvertFrom-Json
  $snapshots += [PSCustomObject]@{
    File = $f.Name
    Timestamp = $data.timestamp
    Commit = $data.commit
    AgentsMdBytes = $data.system.AgentsMdBytes
    AgentsMdLines = $data.system.AgentsMdLines
    TotalSkills = $data.system.TotalSkills
    TotalSkillBytes = $data.system.TotalSkillBytes
    TotalSkillLines = $data.system.TotalSkillLines
    SkillsOver3kb = $data.system.SkillsOver3kb
    AvgSkillBytes = $data.system.AvgSkillBytes
    MedianSkillBytes = $data.system.MedianSkillBytes
    MinSkillBytes = $data.system.MinSkillBytes
    MaxSkillBytes = $data.system.MaxSkillBytes
    ScriptsCount = $data.system.ScriptsCount
    GlobalJunctionsOk = $data.system.GlobalJunctionsOk
    FrontmatterPct = $data.system.FrontmatterPct
    WhenToUsePct = $data.system.WhenToUsePct
    RulesPct = $data.system.RulesPct
  }
}

$first = $snapshots[0]
$last = $snapshots[-1]
$spanDays = [math]::Round(((Get-Date $last.Timestamp) - (Get-Date $first.Timestamp)).TotalDays, 1)

# --- Helper: trend arrow (ASCII) ---
function Get-TrendArrow($firstVal, $lastVal, $higherIsBetter = $true) {
  if ($firstVal -eq $lastVal) { return "=" }
  $improving = $lastVal -gt $firstVal
  if ($higherIsBetter) {
    if ($improving) { return "+" } else { return "-" }
  }
  if ($improving) { return "-" } else { return "+" }
}

function Format-Delta($firstVal, $lastVal) {
  $diff = $lastVal - $firstVal
  if ($diff -ge 0) { return "+{0}" -f $diff }
  return "$diff"
}

# --- Helpers: format numbers ---
function Format-Int($val) { return "{0:N0}" -f $val }

function Format-Pct($val) { return ("{0:F1}" -f $val) + "%" }

function Format-Byte($val) {
  if ($val -ge 1000) {
    $kb = [math]::Round($val / 1000, 1)
    return ("{0:N1}" -f $kb) + "KB"
  }
  return "$val" + "B"
}

# --- Build report ---
$report = @()
$nl = "`n"

$report += "# Trend Dashboard"
$report += ""
$report += ("**Snapshots**: {0} | **Period**: {1} -> {2} ({3} days)" -f $snapshots.Count, (Get-Date $first.Timestamp).ToString("yyyy-MM-dd"), (Get-Date $last.Timestamp).ToString("yyyy-MM-dd"), $spanDays)
$report += ("**Latest commit**: {0}" -f $last.Commit)
$report += ""

# Key metrics table
$report += "## Key Metrics"
$report += ""
$report += "| Metric | First | Current | Delta | Trend |"
$report += "|--------|-------|---------|-------|-------|"

# Define metrics as array of hashtables
$metrics = @(
  @{Name="AGENTS.md Size"; FmtFunc={ param($v) Format-Byte $v }; Better=$false; V1={$first.AgentsMdBytes}; V2={$last.AgentsMdBytes}}
  @{Name="AGENTS.md Lines"; FmtFunc={ param($v) Format-Int $v }; Better=$false; V1={$first.AgentsMdLines}; V2={$last.AgentsMdLines}}
  @{Name="Total Skills"; FmtFunc={ param($v) Format-Int $v }; Better=$true; V1={$first.TotalSkills}; V2={$last.TotalSkills}}
  @{Name="Total Skill Size"; FmtFunc={ param($v) Format-Byte $v }; Better=$false; V1={$first.TotalSkillBytes}; V2={$last.TotalSkillBytes}}
  @{Name="Avg Skill Size"; FmtFunc={ param($v) Format-Byte $v }; Better=$false; V1={$first.AvgSkillBytes}; V2={$last.AvgSkillBytes}}
  @{Name="Skills >3KB"; FmtFunc={ param($v) Format-Int $v }; Better=$true; V1={$first.SkillsOver3kb}; V2={$last.SkillsOver3kb}}
  @{Name="Global Junctions"; FmtFunc={ param($v) ("{0}/{1}" -f $v, $last.TotalSkills) }; Better=$true; V1={$first.GlobalJunctionsOk}; V2={$last.GlobalJunctionsOk}}
  @{Name="Frontmatter"; FmtFunc={ param($v) Format-Pct $v }; Better=$true; V1={$first.FrontmatterPct}; V2={$last.FrontmatterPct}}
  @{Name="When-to-Use"; FmtFunc={ param($v) Format-Pct $v }; Better=$true; V1={$first.WhenToUsePct}; V2={$last.WhenToUsePct}}
  @{Name="Rules Section"; FmtFunc={ param($v) Format-Pct $v }; Better=$true; V1={$first.RulesPct}; V2={$last.RulesPct}}
  @{Name="Scripts Count"; FmtFunc={ param($v) Format-Int $v }; Better=$true; V1={$first.ScriptsCount}; V2={$last.ScriptsCount}}
)

foreach ($m in $metrics) {
  $v1 = & $m.V1
  $v2 = & $m.V2
  $f1 = & $m.FmtFunc $v1
  $f2 = & $m.FmtFunc $v2
  $delta = Format-Delta $v1 $v2
  $arrow = Get-TrendArrow -FirstVal $v1 -LastVal $v2 -HigherIsBetter $m.Better
  $report += ("| {0} | {1} | {2} | {3} | {4} |" -f $m.Name, $f1, $f2, $delta, $arrow)
}

$report += ""

# Per-snapshot timeline
$report += "## Timeline"
$report += ""
$report += "| Date | Commit | AGENTS | Skills | Avg | >3KB | Junc | Scripts | Front | W2U | Rules |"
$report += "|------|--------|--------|-------|-----|------|------|---------|-------|-----|-------|"

foreach ($s in $snapshots) {
  $dateStr = (Get-Date $s.Timestamp).ToString("MM-dd HH:mm")
  $report += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f
    $dateStr,
    $s.Commit,
    (Format-Byte $s.AgentsMdBytes),
    $s.TotalSkills,
    (Format-Byte $s.AvgSkillBytes),
    $s.SkillsOver3kb,
    ("{0}/{1}" -f $s.GlobalJunctionsOk, $s.TotalSkills),
    $s.ScriptsCount,
    (Format-Pct $s.FrontmatterPct),
    (Format-Pct $s.WhenToUsePct),
    (Format-Pct $s.RulesPct))
}

# --- Error Trends (from docs/metricas/errors/) ---
$errorDir = Join-Path $repoRoot "docs\metricas\errors"
$errorFiles = @(Get-ChildItem -Path $errorDir -Filter "*_error.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "LATEST_error.json" } | Sort-Object LastWriteTime)

if ($errorFiles.Count -gt 0) {
  $report += ""
  $report += "## Error Trends"
  $report += ""
  $report += "| Date | Commit | Source | Pass | Fail | Errors | Blocked |"
  $report += "|------|--------|--------|------|------|--------|---------|"

  $errorEntries = $errorFiles | ForEach-Object {
    try { Get-Content $_.FullName -Raw | ConvertFrom-Json } catch { $null }
  } | Where-Object { $_ }

  foreach ($e in $errorEntries) {
    $dateStr = (Get-Date $e.timestamp).ToString("MM-dd HH:mm")
    $report += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f
      $dateStr,
      $e.commit,
      $e.source,
      $e.passed,
      $e.failed,
      $e.totalErrors,
      $e.blocked)
  }
}

$report += ""

Write-Output ($report -join $nl)
