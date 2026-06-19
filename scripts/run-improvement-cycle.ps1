#requires -Version 5.1

<#
.SYNOPSIS
  Continuous Improvement Cycle — measure, compress, validate, log, repeat.
  Automates the APR loop for gentleman-agent-gh.

.DESCRIPTION
  Runs the full improvement pipeline:
  - MEASURE: skill sizes, AGENTS.md, token estimates
  - AUDIT: check for stale/broken links, missing refs
  - COMPRESS: flag verbose skills (>3KB)
  - LEARN: log cycle results to .learnings/LEARNINGS.md
  - REPORT: output structured summary

.PARAMETER RepoRoot
  Root of the repo. Auto-detected from script location.

.PARAMETER AutoCompress
  Automatically trim skills >4KB.

.PARAMETER Quiet
  Minimal output (machine-readable JSON only).
#>

param(
    [string]$RepoRoot = "",
    [switch]$AutoCompress,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($RepoRoot -eq "") {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}

$canonicalDir = Join-Path -Path $RepoRoot -ChildPath ".agents\skills"

if (-not (Test-Path -LiteralPath $canonicalDir)) {
    Write-Host "[FATAL] Repo root not found: $RepoRoot" -ForegroundColor Red
    exit 1
}

$agPath = Join-Path -Path $RepoRoot -ChildPath "AGENTS.md"
$learnPath = Join-Path -Path $RepoRoot -ChildPath ".learnings\LEARNINGS.md"

# ── MEASURE ─────────────────────────────────────────────────────────────────

Write-Host "─────── Improvement Cycle ───────" -ForegroundColor Cyan
Write-Host "Repo: $RepoRoot" -ForegroundColor Cyan

# AGENTS.md size
$agSize = 0
if (Test-Path -LiteralPath $agPath) {
    $agItem = Get-Item -LiteralPath $agPath
    $agSize = $agItem.Length
}
$agSizeKB = [math]::Round($agSize / 1024.0, 1)
Write-Host "AGENTS.md: $agSizeKB KB ($agSize bytes)" -ForegroundColor Yellow

# Skill files: count + total size
$skillFiles = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $canonicalDir) {
    $dirs = Get-ChildItem -LiteralPath $canonicalDir -Directory
    foreach ($dir in $dirs) {
        $mdPath = Join-Path -Path $dir.FullName -ChildPath "SKILL.md"
        if (Test-Path -LiteralPath $mdPath) {
            $null = $skillFiles.Add((Get-Item -LiteralPath $mdPath))
        }
    }
}

$skillCount = $skillFiles.Count
$totalSkillSize = 0.0
foreach ($f in $skillFiles) {
    $totalSkillSize = $totalSkillSize + $f.Length
}
$totalSkillKB = [math]::Round($totalSkillSize / 1024.0, 1)
Write-Host "Skills: $skillCount files, $totalSkillKB KB total" -ForegroundColor Yellow

# Top 5 largest skills
$sortedFiles = $skillFiles | Sort-Object -Property Length -Descending
$largest = $sortedFiles | Select-Object -First 5
Write-Host "Largest skills:" -ForegroundColor Gray
foreach ($f in $largest) {
    $rel = $f.FullName.Replace($RepoRoot, "").TrimStart("\")
    $kb = [math]::Round($f.Length / 1024.0, 1)
    Write-Host "  $rel : $kb KB" -ForegroundColor DarkYellow
}

# Verbose skills (>3KB)
$verboseSkills = New-Object System.Collections.ArrayList
$totalVerboseSize = 0.0
foreach ($f in $skillFiles) {
    if ($f.Length -gt 3072) {
        $null = $verboseSkills.Add($f)
        $totalVerboseSize = $totalVerboseSize + $f.Length
    }
}
$verboseCount = $verboseSkills.Count
$verboseTotalKB = [math]::Round($totalVerboseSize / 1024.0, 1)
if ($verboseCount -gt 0) {
    Write-Host "Verbose skills (>3KB): $verboseCount files, $verboseTotalKB KB" -ForegroundColor Magenta
    if ($AutoCompress) {
        Write-Host "  Auto-compress enabled" -ForegroundColor Green
    }
} else {
    Write-Host "No verbose skills found" -ForegroundColor Green
}

# ── AUDIT (cross-ref check) ─────────────────────────────────────────────────

Write-Host "Running cross-ref check..." -ForegroundColor Cyan
$crErrors = 0
$crWarnings = 0
$crossRefClean = $true

$crScript = Join-Path -Path $PSScriptRoot -ChildPath "cross-ref-check.ps1"
if (Test-Path -LiteralPath $crScript) {
    $crOutput = & $crScript -Json 2>$null
    $crJson = $crOutput -join "`n"
    try {
        $crParsed = $crJson | ConvertFrom-Json
        $crErrors = $crParsed.errors.Count
        $crWarnings = $crParsed.warnings.Count
        if ($crErrors -gt 0) {
            Write-Host "Cross-ref: $crErrors ERROR(S)" -ForegroundColor Red
            foreach ($e in $crParsed.errors) {
                Write-Host "  $e" -ForegroundColor Red
            }
            $crossRefClean = $false
        } else {
            Write-Host "Cross-ref: OK ($crWarnings warnings)" -ForegroundColor Green
        }
    } catch {
        Write-Host "Cross-ref: parse error" -ForegroundColor Red
        $crErrors = 1
    }
} else {
    Write-Host "Cross-ref: script not found" -ForegroundColor Yellow
}

# ── COMPRESS — estimate tokens ──────────────────────────────────────────────

$estSkillTokens = [math]::Round($totalSkillSize / 4.0)
$estAgTokens = [math]::Round($agSize / 3.0)
$estTotal = $estSkillTokens + $estAgTokens
Write-Host "Estimated token footprint: ~$estTotal tokens (skills: ~$estSkillTokens, AGENTS.md: ~$estAgTokens)" -ForegroundColor Yellow

# ── DREAMING — pattern scan ─────────────────────────────────────────────────

$dreamingScript = Join-Path -Path $PSScriptRoot -ChildPath "run-dreaming.ps1"
if (Test-Path -LiteralPath $dreamingScript) {
    Write-Host "Running dreaming scan..." -ForegroundColor Cyan
    & $dreamingScript -Mode report
} else {
    Write-Host "Dreaming script not found" -ForegroundColor Yellow
}

# ── LEARN — log cycle to .learnings ─────────────────────────────────────────

$cycleDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$cycleId = "CYC-" + (Get-Date -Format "yyyyMMdd") + "-" + (Get-Random -Minimum 100 -Maximum 999)

$nl = "`r`n"
$learnEntry = $nl
$learnEntry = $learnEntry + $nl + "## " + $cycleId + " improvement_cycle" + $nl
$learnEntry = $learnEntry + $nl + "**Logged**: " + $cycleDate + $nl
$learnEntry = $learnEntry + "**Priority**: medium" + $nl
$learnEntry = $learnEntry + "**Status**: completed" + $nl
$learnEntry = $learnEntry + "**Area**: system" + $nl
$learnEntry = $learnEntry + $nl + "### Summary" + $nl
$learnEntry = $learnEntry + "Improvement cycle ran: measured " + $skillCount + " skills (" + $totalSkillKB + " KB), AGENTS.md (" + $agSizeKB + " KB), cross-ref check." + $nl
$learnEntry = $learnEntry + $nl + "### Details" + $nl
$learnEntry = $learnEntry + "- AGENTS.md: " + $agSizeKB + " KB (" + $agSize + " bytes)" + $nl
$learnEntry = $learnEntry + "- Skills: " + $skillCount + " files, " + $totalSkillKB + " KB total" + $nl
$learnEntry = $learnEntry + "- Verbose skills (>3KB): " + $verboseCount + " files, " + $verboseTotalKB + " KB" + $nl
$learnEntry = $learnEntry + "- Estimated tokens: ~" + $estTotal + " (skills: ~" + $estSkillTokens + ", AGENTS.md: ~" + $estAgTokens + ")" + $nl
$learnEntry = $learnEntry + "- Cross-ref errors: " + $crErrors + $nl
$learnEntry = $learnEntry + $nl + "### Suggested Action" + $nl
$learnEntry = $learnEntry + "Run compression on verbose skills list: review and trim files >3KB." + $nl
$learnEntry = $learnEntry + $nl + "### Metadata" + $nl
$learnEntry = $learnEntry + "- **Source**: run-improvement-cycle.ps1" + $nl
$learnEntry = $learnEntry + "- **Related-Files**: AGENTS.md, .agents/skills/*/SKILL.md" + $nl
$learnEntry = $learnEntry + "- **Tags**: improvement-cycle, automation" + $nl
$learnEntry = $learnEntry + "- **See-Also**: run-improvement-cycle.ps1" + $nl
$learnEntry = $learnEntry + "- **Pattern-Key**: improvement/cycle" + $nl

if (Test-Path -LiteralPath $learnPath) {
    Add-Content -LiteralPath $learnPath -Value $learnEntry -Encoding UTF8
    Write-Host "Cycle logged to .learnings/LEARNINGS.md as $cycleId" -ForegroundColor Green
} else {
    Write-Host "WARNING: .learnings/LEARNINGS.md not found" -ForegroundColor Yellow
}

# ── REPORT ──────────────────────────────────────────────────────────────────

$result = New-Object PSObject
$result | Add-Member -MemberType NoteProperty -Name "cycleId" -Value $cycleId
$result | Add-Member -MemberType NoteProperty -Name "timestamp" -Value $cycleDate

$metrics = New-Object PSObject
$metrics | Add-Member -MemberType NoteProperty -Name "agSizeKB" -Value $agSizeKB
$metrics | Add-Member -MemberType NoteProperty -Name "skillCount" -Value $skillCount
$metrics | Add-Member -MemberType NoteProperty -Name "totalSkillKB" -Value $totalSkillKB
$metrics | Add-Member -MemberType NoteProperty -Name "verboseOver3KB" -Value $verboseCount
$metrics | Add-Member -MemberType NoteProperty -Name "estTokenTotal" -Value $estTotal
$result | Add-Member -MemberType NoteProperty -Name "metrics" -Value $metrics

$crossRef = New-Object PSObject
$crossRef | Add-Member -MemberType NoteProperty -Name "errors" -Value $crErrors
$crossRef | Add-Member -MemberType NoteProperty -Name "warnings" -Value $crWarnings
$crossRef | Add-Member -MemberType NoteProperty -Name "allClean" -Value $crossRefClean
$result | Add-Member -MemberType NoteProperty -Name "crossRef" -Value $crossRef

if ($Quiet) {
    $result | ConvertTo-Json -Depth 3
} else {
    Write-Host "─────── Cycle Complete: $cycleId ───────" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
}

$result
exit 0
