#requires -Version 5.1

<#
.SYNOPSIS
  Validate internal references in gentleman-agent-gh repo.
  Checks skills, SKILLS-INDEX, global junctions, and shared refs.

.DESCRIPTION
  Post-migration (skills/ → .agents/skills/) validator.
  Returns 0 = clean, 1 = issues found.

.PARAMETER RepoRoot
  Root of the repo. Defaults to script parent dir.

.PARAMETER Json
  Output structured JSON for agent consumption.

.EXAMPLE
  .\scripts\cross-ref-check.ps1
  .\scripts\cross-ref-check.ps1 -Json
#>

param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'
$errors = @()
$warnings = @()

$canonicalDir = Join-Path -Path $RepoRoot -ChildPath ".agents\skills"
$globalDir = "$env:USERPROFILE\.config\opencode\skills"

if (-not (Test-Path $canonicalDir)) {
    Write-Host "FATAL: Skills directory not found: $canonicalDir" -ForegroundColor Red
    exit 1
}

Write-Host "=== Cross-Ref Check: $RepoRoot ===" -ForegroundColor Cyan

# --- [1/6] ANTI-PATTERN-CATALOG ---
Write-Host "`n[1/6] ANTI-PATTERN-CATALOG..." -NoNewline
$apc = Test-Path (Join-Path -Path $RepoRoot -ChildPath "ANTI-PATTERN-CATALOG.md")
if ($apc) { Write-Host " OK" } else { $errors += "ANTI-PATTERN-CATALOG.md not found at repo root"; Write-Host " FAIL" }

# --- [2/6] All skills have SKILL.md ---
Write-Host "[2/6] SKILL.md files..." -NoNewline
$missingSkillMd = @()
try {
    $skillDirs = Get-ChildItem (Join-Path -Path $canonicalDir -ChildPath "*") -Directory
} catch {
    Write-Host " FAIL`nFATAL: Cannot list skill directories: $_" -ForegroundColor Red
    exit 1
}
$skillDirs | ForEach-Object {
    $skillName = $_.Name
    if ($skillName -eq '_shared') { return }
    $mdPath = Join-Path -Path $_.FullName -ChildPath "SKILL.md"
    if (-not (Test-Path $mdPath)) { $missingSkillMd += $skillName }
}
if ($missingSkillMd.Count -eq 0) { Write-Host " OK (all have SKILL.md)" } else { $warnings += "Skills missing SKILL.md: $($missingSkillMd -join ', ')"; Write-Host " WARN" }

# --- [3/6] SKILLS-INDEX count matches canonical ---
Write-Host "[3/6] SKILLS-INDEX count..." -NoNewline
$actualCount = ($skillDirs | Where-Object { $_.Name -ne '_shared' }).Count
$headerLine = Select-String -Path (Join-Path -Path $RepoRoot -ChildPath "SKILLS-INDEX.md") -Pattern "all \d+ skills"
if ($headerLine -match "all (\d+) skills") {
    $declared = [int]$Matches[1]
    if ($declared -eq $actualCount) { Write-Host " OK ($actualCount)" } else { $errors += "SKILLS-INDEX says $declared but canonical has $actualCount"; Write-Host " FAIL (says $declared, actual $actualCount)" }
} else { $warnings += "SKILLS-INDEX header format unexpected"; Write-Host " WARN" }

# --- [4/6] Global junctions exist for each skill ---
Write-Host "[4/6] Global junctions..." -NoNewline
$missingGlobal = @()
if (Test-Path $globalDir) {
    Get-ChildItem $canonicalDir -Directory | Where-Object { $_.Name -ne '_shared' } | ForEach-Object {
        $skillName = $_.Name
        $globalPath = Join-Path -Path $globalDir -ChildPath $skillName
        if (-not (Test-Path $globalPath)) { $missingGlobal += $skillName }
    }
}
if ($missingGlobal.Count -eq 0) { Write-Host " OK (all in global)" } else { $warnings += "Missing global junctions: $($missingGlobal -join ', ')"; Write-Host " WARN" }

# --- [5/5] _shared references resolve ---
Write-Host "[5/6] _shared refs..." -NoNewline
$sharedFiles = @{
    'skill-resolver.md' = Test-Path (Join-Path -Path $canonicalDir -ChildPath "_shared\skill-resolver.md")
    'sdd-phase-common.md' = Test-Path (Join-Path -Path $canonicalDir -ChildPath "_shared\sdd-phase-common.md")
    'persistence-contract.md' = Test-Path (Join-Path -Path $canonicalDir -ChildPath "_shared\persistence-contract.md")
    'engram-convention.md' = Test-Path (Join-Path -Path $canonicalDir -ChildPath "_shared\engram-convention.md")
}
$missingShared = @($sharedFiles.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($missingShared.Count -eq 0) { Write-Host " OK" } else { $errors += "Missing _shared files: $($missingShared -join ', ')"; Write-Host " FAIL" }

# --- [6/6] Cross-Refs in skills point to real skills ---
Write-Host "[6/6] Cross-refs to real skills..." -NoNewline
$brokenRefs = @()
$allSkillNames = ($skillDirs | Where-Object { $_.Name -ne '_shared' } | ForEach-Object { $_.Name.ToLower() })
$refPattern = 'Cross-Refs:\s*(.+)'
$apPattern = 'Anti-Patterns:\s*(.+)'
Get-ChildItem $canonicalDir -Directory | Where-Object { $_.Name -ne '_shared' } | ForEach-Object {
    $skillName = $_.Name
    $mdPath = Join-Path -Path $_.FullName -ChildPath "SKILL.md"
    if (-not (Test-Path $mdPath)) { return }
    $content = Get-Content $mdPath -Raw
    if (-not $content) { return }
    # Check Cross-Refs: line — only match single-word hyphens (skill names)
    if ($content -match $refPattern) {
        $refs = $Matches[1] -split '\s*[\|,]\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -cmatch '^[a-z][a-z0-9_-]+$' }
        foreach ($ref in $refs) {
            $refLower = $ref.ToLower()
            if ($allSkillNames -notcontains $refLower) {
                $brokenRefs += "$skillName cross-refs '$ref' which doesn't exist"
            }
        }
    }
    # Check Anti-Patterns: line — skip multi-word descriptors, only match skill names
    if ($content -match $apPattern) {
        $aps = $Matches[1] -split '\s*[\|,]\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -cmatch '^[a-z][a-z0-9_-]+$' }
        foreach ($ap in $aps) {
            $apLower = $ap.ToLower()
            if ($allSkillNames -notcontains $apLower) {
                $brokenRefs += "$skillName anti-pattern references '$ap' which doesn't exist"
            }
        }
    }
}
if ($brokenRefs.Count -eq 0) { Write-Host " OK" } else { $errors += $brokenRefs; Write-Host " FAIL ($($brokenRefs.Count) broken)" }

# --- Summary ---
$result = @{
    timestamp = (Get-Date -Format "o")
    canonicalSkills = $actualCount
    errors = $errors
    warnings = $warnings
    brokenCrossRefs = $brokenRefs.Count
    allClean = ($errors.Count -eq 0 -and $warnings.Count -eq 0)
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 2)
} elseif ($result.allClean) {
    Write-Host "OK ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    if ($errors.Count -gt 0) { Write-Host "ERRORS ($($errors.Count)):" -ForegroundColor Red; $errors | ForEach-Object { Write-Host "  * $_" -ForegroundColor Red } }
    if ($warnings.Count -gt 0) { Write-Host "WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow; $warnings | ForEach-Object { Write-Host "  * $_" -ForegroundColor Yellow } }
    if ($errors.Count -gt 0) { exit 1 } else { exit 0 }
}
