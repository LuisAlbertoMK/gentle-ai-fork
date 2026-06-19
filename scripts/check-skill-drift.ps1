#requires -Version 5.1

<#
.SYNOPSIS
  Check skill drift between canonical source (.agents/skills/) and global config (~/.config/opencode/skills/).
  Detects stale junctions or missing global links.

.DESCRIPTION
  Verifies that all skills in the canonical directory (.agents/skills/) have
  corresponding junctions in the global OpenCode config.
  Returns exit code 0 = all in sync, 1 = drift detected.

.PARAMETER Thorough
  Use content hash comparison (slower but accurate). Default: line count comparison (fast).

.PARAMETER AutoFix
  Create missing global junctions for any skills not linked.

.PARAMETER Json
  Output results as JSON.

.EXAMPLE
  .\scripts\check-skill-drift.ps1
  .\scripts\check-skill-drift.ps1 -Thorough
  .\scripts\check-skill-drift.ps1 -AutoFix
  .\scripts\check-skill-drift.ps1 -Json
#>

param(
  [switch]$Thorough,
  [switch]$AutoFix,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$canonicalDir = Join-Path -Path $PSScriptRoot -ChildPath "..\.agents\skills"
$globalDir = "$env:USERPROFILE\.config\opencode\skills"
$errors = @()
$warnings = @()
$drifted = @()

if (-not (Test-Path $canonicalDir)) { Write-Error "Canonical skills dir not found: $canonicalDir"; exit 2 }
if (-not (Test-Path $globalDir)) { Write-Error "Global skills dir not found: $globalDir"; exit 2 }

$canonicalSkills = @(Get-ChildItem $canonicalDir -Directory | Where-Object { $_.Name -ne '_shared' })

foreach ($skill in $canonicalSkills) {
  $skillName = $skill.Name
  $canonPath = Join-Path -Path $skill.FullName -ChildPath "SKILL.md"
  $globPath = Join-Path -Path $globalDir -ChildPath "$skillName\SKILL.md"

  if (-not (Test-Path $canonPath)) {
    $errors += [PSCustomObject]@{ Skill=$skillName; Status="CANON_MISSING"; Detail="Canonical has no SKILL.md" }
    continue
  }

  $globalItem = Get-Item (Join-Path -Path $globalDir -ChildPath $skillName) -ErrorAction SilentlyContinue

  if (-not $globalItem) {
    $errors += [PSCustomObject]@{ Skill=$skillName; Status="GLOBAL_MISSING"; Detail="No global dir exists" }
    continue
  }

  if ($globalItem.LinkType -ne "Junction") {
    $warnings += [PSCustomObject]@{ Skill=$skillName; Status="GLOBAL_NOT_JUNCTION"; Detail="Global is a real file, not a junction" }
  }

  # Compare content if not a junction (real file copy could drift)
  if ($globalItem.LinkType -ne "Junction") {
    if ($Thorough) {
      $canonHash = (Get-FileHash -LiteralPath $canonPath -Algorithm SHA256).Hash
      $globHash = (Get-FileHash -LiteralPath $globPath -Algorithm SHA256).Hash
      $match = $canonHash -eq $globHash
    } else {
      $canonLines = (Get-Content $canonPath | Measure-Object -Line).Lines
      $globLines = (Get-Content $globPath | Measure-Object -Line).Lines
      $match = $canonLines -eq $globLines
    }
    if (-not $match) {
      $drifted += [PSCustomObject]@{
        Skill = $skillName
        Status = "DRIFT"
        Detail = if ($Thorough) { "Hash mismatch" } else { "Line count: canonical=$canonLines global=$globLines" }
      }
    }
  }
}

# AutoFix: create missing global junctions
if ($AutoFix) {
  $errorsToFix = @($errors) | Where-Object { $_ -and $_.Status -eq "GLOBAL_MISSING" }
  if (@($errorsToFix).Count -gt 0) {
    Write-Output "Creating $($errorsToFix.Count) missing global junctions..."
    foreach ($e in $errorsToFix) {
      $target = Join-Path -Path $canonicalDir -ChildPath $e.Skill
      $link = Join-Path -Path $globalDir -ChildPath $e.Skill
      New-Item -ItemType Junction -Path $link -Target $target -Force | Out-Null
      Write-Output "  Created: $link -> $target"
    }
    $errors = @($errors) | Where-Object { $_ -and $_.Status -ne "GLOBAL_MISSING" }
  }
}

# --- Output ---
$result = @{
  timestamp = (Get-Date -Format "o")
  totalSkills = $canonicalSkills.Count
  junctionSkills = ($canonicalSkills | ForEach-Object { $globalItem = Get-Item (Join-Path -Path $globalDir -ChildPath $_.Name) -ErrorAction SilentlyContinue; if ($globalItem -and $globalItem.LinkType -eq "Junction") { $_ } else { $null } } | Measure-Object).Count
  realFileSkills = ($canonicalSkills | ForEach-Object { $globalItem = Get-Item (Join-Path -Path $globalDir -ChildPath $_.Name) -ErrorAction SilentlyContinue; if ($globalItem -and $globalItem.LinkType -ne "Junction") { $_ } else { $null } } | Measure-Object).Count
  warnings = $warnings
  drifted = $drifted
  errors = $errors
  allSynced = ($drifted.Count -eq 0 -and $errors.Count -eq 0 -and $warnings.Count -eq 0)
}

if ($Json) {
  Write-Output ($result | ConvertTo-Json -Depth 3)
} else {
  $warnCount = @($result.warnings)
  $driftCount = @($drifted)
  $errCount = @($errors)

  if ($warnCount.Count -gt 0) {
    Write-Output "`nWARNINGS: $($warnCount.Count)"
    $result.warnings | Format-Table Skill, Status, Detail -AutoSize -ErrorAction SilentlyContinue
  }
  if ($result.allSynced) {
    Write-Output "`nOK ALL $($result.totalSkills) skills in sync!"
    Write-Output "   ($($result.junctionSkills) junctions OK, $($result.realFileSkills) real files verified)"
  } else {
    if ($driftCount.Count -gt 0) {
      Write-Output "`nDRIFT: $($driftCount.Count) skills out of sync"
      $drifted | Format-Table Skill, Status, Detail -AutoSize -ErrorAction SilentlyContinue
    }
    if ($errCount.Count -gt 0) {
      Write-Output "`nERRORS: $($errCount.Count)"
      $errors | Format-Table Skill, Status, Detail -AutoSize -ErrorAction SilentlyContinue
    }
    exit 1
  }
}
