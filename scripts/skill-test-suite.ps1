<#
.SYNOPSIS
  Comprehensive skill validation suite
.DESCRIPTION
  Runs syntax checks, frontmatter validation, dependency resolution, and
  content quality checks across all skills in the registry.
.PARAMETER RepoRoot
  Ruta raíz del repositorio (default: parent of scripts/).
#>
#requires -Version 5.1

param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$skillsDir = "$RepoRoot\.agents\skills"
$total = 0; $pass = 0; $fail = 0; $errors = @()

Write-Host "=== Skill Test Suite ===" -ForegroundColor Cyan
Write-Host "Repo: $RepoRoot" -ForegroundColor Gray

# Collect all skill directories (exclude _shared)
try {
    $skillDirs = Get-ChildItem $skillsDir -Directory | Where-Object { $_.Name -ne '_shared' } | Sort-Object Name
} catch {
    Write-Host "FATAL: Cannot access skills directory '$skillsDir': $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nFound $($skillDirs.Count) skills to test`n" -ForegroundColor Yellow

foreach ($dir in $skillDirs) {
    $skillName = $dir.Name
    $mdPath = "$($dir.FullName)\SKILL.md"
    $results = @()

    # Test 1: SKILL.md exists
    $total++
    if (Test-Path $mdPath) {
        $results += "SKILL.md:OK"
        $content = Get-Content $mdPath -Raw
    } else {
        $results += "SKILL.md:MISSING"
        $errors += "$skillName : SKILL.md not found"
        continue
    }

    # Test 2: Frontmatter (starts with ---)
    try {
        $fmStart = $content.IndexOf('---')
        $fmEnd = $content.IndexOf('---', $fmStart + 3)
    } catch {
        $results += "fm:FAIL"; $errors += "$skillName : cannot parse frontmatter"; continue
    }
    if ($fmStart -eq 0 -and $fmEnd -gt 3) {
        $results += "fm:OK"
        $fm = $content.Substring($fmStart + 3, $fmEnd - $fmStart - 3)
        $hasName = $fm -match 'name:\s*"?([^"\n]+)"?'
        $hasDesc = $fm -match 'description:'
        $hasLicense = $fm -match 'license:'
        if ($hasName -and $hasDesc -and $hasLicense) { $results += "fields:OK" } else { $results += "fields:WARN" }
    } else {
        $results += "fm:FAIL"; $errors += "$skillName : missing frontmatter"
    }

    # Test 3: Has content beyond frontmatter
    $closeFm = $content.IndexOf('---', 3) + 3
    $body = $content.Substring($closeFm).Trim()
    if ($body.Length -gt 50) { $results += "body:OK" } else { $results += "body:SMALL" }

    # Test 4: Contains ## headers
    $headers = [regex]::Matches($body, '(?m)^##\s+\S')
    if ($headers.Count -ge 1) { $results += "sects:OK($($headers.Count))" }
    elseif ($skillName -eq 'lean-context') { $results += "sects:INTENTIONAL" }  # ultra-lean: plain text headers
    else { $results += "sects:FAIL" }

    # Test 5: Check for orphaned references to other skills
    $refs = [regex]::Matches($content, '(?<!file:)([a-z][a-z-]+)/SKILL\.md')
    $badRefs = @()
    foreach ($ref in $refs) {
        $target = $ref.Groups[1].Value
        if (-not (Test-Path "$skillsDir\$target\SKILL.md")) { $badRefs += $target }
    }
    if ($badRefs.Count -eq 0) { $results += "refs:OK" } else { $results += "refs:BAD ($($badRefs -join ','))"; $errors += "$skillName : orphan refs to $($badRefs -join ',')" }

    # Test 7: Description is not a placeholder
    if ($fm -match 'description: >  \S+ skill') {
        $results += "desc:PLACEHOLDER"
        $errors += "$skillName : description is placeholder text"
    } else {
        $results += "desc:OK"
    }

    # Test 6: Triggers documented (for root-level skills)
    if ($skillName -notlike 'sdd-*') {
        if ($content -match '[Tt]riggers?:[^"]*"\w') { $results += "trig:OK" } else { $results += "trig:WARN" }
    } else {
        $results += "trig:SDD"
    }

    # Determine pass/fail
    $hasFail = ($results -match 'FAIL').Count -gt 0
    if ($hasFail) { $fail++ } else { $pass++ }

    $icon = if ($hasFail) { 'FAIL' } else { 'PASS' }
    Write-Output "  $icon $skillName"
    Write-Host "       $($results -join ' ')"
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
$score = if ($total -gt 0) { [math]::Round(($pass / $total) * 100, 1) } else { 0 }
$scoreColor = if ($score -ge 90) { 'Green' } elseif ($score -ge 70) { 'Yellow' } else { 'Red' }
Write-Host "Tests: $total | Pass: $pass | Fail: $fail | Score: $score%" -ForegroundColor $scoreColor

if ($score -ge 90) { Write-Host "Verdict: PRODUCTION READY" -ForegroundColor Green }
elseif ($score -ge 70) { Write-Host "Verdict: NEEDS WORK" -ForegroundColor Yellow }
else { Write-Host "Verdict: REJECTED" -ForegroundColor Red }

if ($errors.Count -gt 0) {
    Write-Host "`nIssues:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($fail -gt 0) { exit 1 } else { exit 0 }
