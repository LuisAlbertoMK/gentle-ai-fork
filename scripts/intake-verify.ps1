#requires -Version 5.1

<#
.SYNOPSIS
  Project Intake Verification — 7 checks + 3-iteration cycle
.DESCRIPTION
  Evalúa un proyecto contra el framework de gap-analysis. Corre 7 checks y
  opcionalmente itera para mejora progresiva. Output en texto o JSON.
.PARAMETER ProjectPath
  Ruta al proyecto a verificar.
.PARAMETER Iterations
  Cantidad de ciclos de mejora (default: 3).
.PARAMETER OutputFormat
  Formato de salida: text (default) o json.

.PARAMETER ProjectType
  Tipo de proyecto para análisis: auto (default), fe, be, db, fullstack, mobile, etc.

.PARAMETER SaveMetrics
  Guardar métricas en docs/metricas/ (default: $true).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath,

    [ValidateRange(1,5)]
    [int]$Iterations = 1,

    [ValidateSet("auto","fe","be","db","fullstack","mobile","desktop","saas","erp","ecom","api","web","cms","infra")]
    [string]$ProjectType = "auto",

    [bool]$SaveMetrics = $true,

    [ValidateSet("text", "json")]
    [string]$OutputFormat = "text"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Explicit script-scope reference for Write-Result function (PSSA false positive suppression)
$Script:OutputFormat = $OutputFormat

$script:startTime = Get-Date
$script:roundResults = @()

# Unicode icons for PS 5.1 (use [char] NOT backtick-u which requires PS6+)
$script:CHK = [char]0x2705
$script:CRS = [char]0x274C
$script:WRN = [char]0x26A0

function Write-Result {
    param([string]$Icon, [string]$Artifact, [string]$Status, [string]$Detail, [string]$Score = "")
    $displayIcon = $Icon
    if ($Icon -eq "PASS") { $displayIcon = $script:CHK }
    if ($Icon -eq "FAIL") { $displayIcon = $script:CRS }
    if ($Icon -eq "WARN") { $displayIcon = $script:WRN }
    $cMap = @{$script:CHK="Green"; $script:CRS="Red"; $script:WRN="Yellow"}
    $c = $cMap[$displayIcon]
    if (-not $c) { $c = "White" }
    $line = "$displayIcon $Artifact : $Status"
    if ($Detail) { $line = $line + " - $Detail" }
    if ($Score) { $line = $line + " [$Score/10]" }
    if ($OutputFormat -eq "json") { return }
    Write-Host $line -ForegroundColor $c
}

function Get-FileSize {
    param([string]$Path)
    if (Test-Path $Path) {
        $len = (Get-Item $Path).Length
        if ($len -gt 1KB) { return "$([math]::Round($len/1KB, 1))KB" }
        return "$len B"
    }
    return ""
}

function Get-Score {
    param([string]$Icon)
    if ($Icon -match $script:CHK) { return 10 }
    if ($Icon -match $script:WRN) { return 5 }
    return 0
}

function Invoke-IntakeCheck {
    param([int]$Round, [string]$ProjectPath, [string]$ProjectType)

    $results = @{}
    $scoreMap = @{}

    $checkMark = $script:CHK
    $crossMark = $script:CRS
    $warnMark = $script:WRN

    Write-Host ""
    Write-Host ("=" * 55) -ForegroundColor Cyan
    Write-Host "  Iteracion $Round - Intake Verification" -ForegroundColor Cyan
    Write-Host "  Proyecto: $ProjectPath" -ForegroundColor Gray
    Write-Host "  Tipo: $ProjectType" -ForegroundColor Gray
    Write-Host ("=" * 55) -ForegroundColor Cyan

    # --- 1. Roadmap ---
    $rPath = $null
    if (Test-Path "$ProjectPath\ROADMAP.md") { $rPath = "ROADMAP.md" }
    elseif (Test-Path "$ProjectPath\docs\roadmap.md") { $rPath = "docs/roadmap.md" }
    elseif (Test-Path "$ProjectPath\roadmap.md") { $rPath = "roadmap.md" }
    elseif (Test-Path "$ProjectPath\roadmap") { $rPath = "roadmap/ (dir)" }

    if ($rPath) {
        $size = Get-FileSize "$ProjectPath\$rPath"
        Write-Result -Icon $checkMark -Artifact "Roadmap" -Status "Found" -Detail "$rPath ($size)"
        $results["roadmap"] = $checkMark; $scoreMap["roadmap"] = 10
    } else {
        Write-Result -Icon $crossMark -Artifact "Roadmap" -Status "Missing" -Detail "No ROADMAP.md, docs/roadmap.md, or roadmap/ dir"
        $results["roadmap"] = $crossMark; $scoreMap["roadmap"] = 0
    }

    # --- 2. PR (Pull Request + Problem Report) ---
    $prScore = 0; $prDetail = @()
    $gitDir = "$ProjectPath\.git"
    if (Test-Path $gitDir) {
        $commitCount = & git -C "$ProjectPath" log --oneline -10 2>$null | Measure-Object | ForEach-Object { $_.Count }
        if ($commitCount -gt 0) {
            $prScore += 5; $prDetail += "$commitCount commits in HEAD"
            $ghPrs = & gh pr list --limit 5 2>$null
            if ($LASTEXITCODE -eq 0 -and $ghPrs) {
                $prCount = ($ghPrs | Measure-Object | ForEach-Object { $_.Count })
                $prDetail += "$prCount open PR(s)"; $prScore += 3
            }
        }
    } else {
        $prDetail += "no .git dir (score limited)"
    }
    $prFiles = Get-ChildItem -Path "$ProjectPath" -Recurse -Include "*PROBLEM*REPORT*","*bug-report*","*incident*" `
        -Exclude "*node_modules*",".git","*vendor*" -ErrorAction SilentlyContinue | Select-Object -First 3
    if ($prFiles) {
        $prDetail += "Problem Report: $($prFiles.Count) file(s) ($($prFiles[0].Name))"
        $prScore = [math]::Max($prScore, 5)
    }
    $prIcon = if ($prScore -ge 8) { $checkMark } elseif ($prScore -ge 3) { $warnMark } else { $crossMark }
    Write-Result -Icon $prIcon -Artifact "PR" -Status "Pull Request + Problem Report" -Detail ($prDetail -join " | ")
    $results["pr"] = $prIcon; $scoreMap["pr"] = $prScore

    # --- 3. PRD / Specs ---
    $prdFound = Get-ChildItem -Path "$ProjectPath" -Recurse -Include "*PRD*","*spec*","*requirements*","*srs*" `
        -Exclude "*node_modules*",".git","*vendor*" -File -ErrorAction SilentlyContinue | Select-Object -First 5
    if ($prdFound) {
        Write-Result -Icon $checkMark -Artifact "PRD" -Status "Found" -Detail "$($prdFound.Count) files (e.g., $($prdFound[0].Name))"
        $results["prd"] = $checkMark; $scoreMap["prd"] = 10
    } else {
        Write-Result -Icon $crossMark -Artifact "PRD" -Status "Missing" -Detail "No PRD, spec, or requirements files"
        $results["prd"] = $crossMark; $scoreMap["prd"] = 0
    }

    # --- 4. README ---
    if (Test-Path "$ProjectPath\README.md") {
        $size = Get-FileSize "$ProjectPath\README.md"
        $content = Get-Content "$ProjectPath\README.md" -Raw -ErrorAction SilentlyContinue
        $quality = 10
        if ($content) {
            if ($content -notmatch '# ') { $quality -= 2 }
            if ($content -notmatch 'setup|install|getting started|usage|empezar|instalacion') { $quality -= 2 }
            if ($content.Length -lt 200) { $quality -= 2 }
            if ($content.Length -lt 100) { $quality -= 3 }
        }
        $quality = [math]::Max(1, $quality)
        $qIcon = if ($quality -ge 8) { $checkMark } elseif ($quality -ge 5) { $warnMark } else { $crossMark }
        Write-Result -Icon $qIcon -Artifact "README" -Status "Found" -Detail "$size (quality score: $quality/10)"
        $results["readme"] = $qIcon; $scoreMap["readme"] = $quality
    } else {
        Write-Result -Icon $crossMark -Artifact "README" -Status "Missing" -Detail "No README.md at project root"
        $results["readme"] = $crossMark; $scoreMap["readme"] = 0
    }

    # --- 5. Tests ---
    $testDirs = Get-ChildItem -Path "$ProjectPath" -Directory -Include "tests","__tests__","spec","test","cypress" -ErrorAction SilentlyContinue
    $testFiles = Get-ChildItem -Path "$ProjectPath" -Recurse -Include "*test*","*spec*","*suite*" -File `
        -Exclude "*node_modules*",".git","*vendor*" -ErrorAction SilentlyContinue | Select-Object -First 10
    if ($testDirs) {
        Write-Result -Icon $checkMark -Artifact "Tests" -Status "Test dirs found" -Detail "$($testDirs.Count) dir(s): $($testDirs.Name -join ', ')"
        $results["tests"] = $checkMark; $scoreMap["tests"] = 10
    } elseif ($testFiles.Count -ge 3) {
        Write-Result -Icon $checkMark -Artifact "Tests" -Status "Test files found" -Detail "$($testFiles.Count) files found"
        $results["tests"] = $checkMark; $scoreMap["tests"] = 8
    } elseif ($testFiles.Count -ge 1) {
        Write-Result -Icon $warnMark -Artifact "Tests" -Status "Minimal test files" -Detail "$($testFiles.Count) files found"
        $results["tests"] = $warnMark; $scoreMap["tests"] = 5
    } else {
        Write-Result -Icon $crossMark -Artifact "Tests" -Status "No test artifacts" -Detail "No test dirs or files found"
        $results["tests"] = $crossMark; $scoreMap["tests"] = 0
    }

    # --- 6. CI/CD ---
    $ciFound = @()
    if (Test-Path "$ProjectPath\.github\workflows") { $ciFound += "GitHub Actions" }
    if (Test-Path "$ProjectPath\Jenkinsfile") { $ciFound += "Jenkins" }
    if (Test-Path "$ProjectPath\.gitlab-ci.yml") { $ciFound += "GitLab CI" }
    if (Test-Path "$ProjectPath\azure-pipelines.yml") { $ciFound += "Azure Pipelines" }
    if (Test-Path "$ProjectPath\.circleci\config.yml") { $ciFound += "CircleCI" }
    if (Test-Path "$ProjectPath\Dockerfile") { $ciFound += "Docker" }

    if ($ciFound.Count -ge 2) {
        Write-Result -Icon $checkMark -Artifact "CI/CD" -Status "Multiple configs" -Detail ($ciFound -join ', ')
        $results["cicd"] = $checkMark; $scoreMap["cicd"] = 10
    } elseif ($ciFound.Count -eq 1) {
        Write-Result -Icon $warnMark -Artifact "CI/CD" -Status "Single config" -Detail ($ciFound[0])
        $results["cicd"] = $warnMark; $scoreMap["cicd"] = 5
    } else {
        Write-Result -Icon $crossMark -Artifact "CI/CD" -Status "Not found" -Detail "No CI/CD config detected"
        $results["cicd"] = $crossMark; $scoreMap["cicd"] = 0
    }

    # --- 7. Monitoring ---
    $monPatterns = @("*sentry*","*datadog*","*newrelic*","*grafana*","*prometheus*","*openTelemetry*",
                     "*appinsights*","*bugsnag*","*rollbar*","*logstash*","*honeycomb*","*dynatrace*")
    $monFound = @()
    foreach ($pat in $monPatterns) {
        $m = Get-ChildItem -Path "$ProjectPath" -Recurse -Include $pat -File -Exclude "*node_modules*",".git" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { $monFound += $m.Name }
    }
    $hasLogging = (Test-Path "$ProjectPath\logs") -or (Get-ChildItem -Path "$ProjectPath" -Directory -Include "metrics","monitoring","alerts" -ErrorAction SilentlyContinue)

    if ($monFound.Count -ge 1) {
        Write-Result -Icon $checkMark -Artifact "Monitoring" -Status "APM/tracing found" -Detail "$($monFound[0]) (+$($monFound.Count - 1) more)"
        $results["monitoring"] = $checkMark; $scoreMap["monitoring"] = 10
    } elseif ($hasLogging) {
        Write-Result -Icon $warnMark -Artifact "Monitoring" -Status "Basic logging only" -Detail "logs/ or metrics/ dir exists, no APM"
        $results["monitoring"] = $warnMark; $scoreMap["monitoring"] = 5
    } else {
        Write-Result -Icon $crossMark -Artifact "Monitoring" -Status "Not found" -Detail "No APM/tracing/logging config"
        $results["monitoring"] = $crossMark; $scoreMap["monitoring"] = 0
    }

    # --- Round Summary ---
    $totalScore = ($scoreMap.Values | Measure-Object -Sum).Sum
    $maxScore = $scoreMap.Count * 10
    $pct = if ($maxScore -gt 0) { [math]::Round(($totalScore / $maxScore) * 100, 1) } else { 0 }

    Write-Host ""
    Write-Host ("-" * 50) -ForegroundColor Cyan
    Write-Host ("  Resumen Iteracion " + $Round + ":") -ForegroundColor Cyan
    $scoreColor = if ($pct -ge 80) {"Green"} elseif ($pct -ge 50) {"Yellow"} else {"Red"}
    Write-Host "  Score: $totalScore/$maxScore ($pct%)" -ForegroundColor $scoreColor

    $criticalMissing = @()
    if ($results["roadmap"] -eq $crossMark) { $criticalMissing += "Roadmap" }
    if ($results["prd"] -eq $crossMark) { $criticalMissing += "PRD" }
    if ($results["readme"] -eq $crossMark) { $criticalMissing += "README" }
    if ($criticalMissing.Count -gt 0) {
        $criticalStr = $criticalMissing -join ', '
        Write-Host "  CRITICO: Sin $criticalStr el proyecto esta ciego" -ForegroundColor Red
    }

    return @{
        round = $Round
        results = $results
        scores = $scoreMap
        totalScore = $totalScore
        maxScore = $maxScore
        pct = $pct
        criticalMissing = $criticalMissing
    }
}

# --- MAIN ---

if (-not (Test-Path $ProjectPath)) {
    Write-Error "ProjectPath does not exist: $ProjectPath"
    exit 2
}

Write-Host ""
Write-Host ("#" * 58) -ForegroundColor Cyan
Write-Host "#           INTAKE VERIFICATION - $Iterations iteracion(es)          #" -ForegroundColor Cyan
Write-Host ("#" * 58) -ForegroundColor Cyan

# Auto-detect project type if "auto"
if ($ProjectType -eq "auto") {
    Write-Host ""
    Write-Host "Detectando tipo de proyecto..." -ForegroundColor Yellow
    $signals = @()

    if (Test-Path "$ProjectPath\package.json") {
        $pkg = Get-Content "$ProjectPath\package.json" -Raw -ErrorAction SilentlyContinue
        if ($pkg) {
            if ($pkg -match '"react"') { $signals += "frontend" }
            if ($pkg -match '"next"') { $signals += "frontend" }
            if ($pkg -match '"vue"') { $signals += "frontend" }
            if ($pkg -match '"express"') { $signals += "backend" }
            if ($pkg -match '"fastify"') { $signals += "backend" }
        }
        if ($signals.Count -eq 0) { $signals += "node" }
    }
    if (Test-Path "$ProjectPath\go.mod") { $signals += "backend" }
    if (Test-Path "$ProjectPath\pubspec.yaml") { $signals += "mobile" }
    if (Test-Path "$ProjectPath\Dockerfile") { $signals += "infra" }

    if ($signals -contains "frontend" -and $signals -contains "backend") {
        $ProjectType = "fullstack"
    } elseif ($signals -contains "frontend") {
        $ProjectType = "fe"
    } elseif ($signals -contains "backend") {
        $ProjectType = "be"
    } elseif ($signals -contains "mobile") {
        $ProjectType = "mobile"
    } else {
        $ProjectType = "be"
    }

    Write-Host "  -> Tech Layer: $ProjectType" -ForegroundColor Green
}

# Run iterations
for ($i = 1; $i -le $Iterations; $i++) {
    $round = Invoke-IntakeCheck -Round $i -ProjectPath $ProjectPath -ProjectType $ProjectType
    $script:roundResults += $round

    if ($i -lt $Iterations) {
        Write-Host ""
        Write-Host "Esperando antes de iteracion $($i+1)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 1

        if ($round.criticalMissing.Count -gt 0) {
            $gapStr = $round.criticalMissing -join ', '
            Write-Host "Sugerencia: Crea $gapStr antes de la proxima iteracion" -ForegroundColor Magenta
        }
    }
}

# --- FINAL REPORT ---
$elapsed = [math]::Round(((Get-Date) - $script:startTime).TotalSeconds, 1)
$first = $script:roundResults[0]
$last = $script:roundResults[-1]

Write-Host ""
Write-Host ("#" * 58) -ForegroundColor Cyan
Write-Host "#                    FINAL REPORT                          #" -ForegroundColor Cyan
Write-Host ("#" * 58) -ForegroundColor Cyan
Write-Host "  Proyecto: $ProjectPath"
Write-Host "  Tipo: $ProjectType"
Write-Host "  Iteraciones: $Iterations en ${elapsed}s"
Write-Host ""

$allArtifacts = @("roadmap","pr","prd","readme","tests","cicd","monitoring")

# Table header
Write-Host (" " * 2) -NoNewline
Write-Host ("-" * 55) -ForegroundColor Gray
$headerLine = "  | $('Artifact'.PadRight(19)) | $('Baseline'.PadRight(8)) | $('Current'.PadRight(8)) | $('Delta'.PadRight(8)) |"
Write-Host $headerLine -ForegroundColor Gray
Write-Host (" " * 2) -NoNewline
Write-Host ("-" * 55) -ForegroundColor Gray

foreach ($a in $allArtifacts) {
    $baseScore = if ($first.scores[$a]) { $first.scores[$a] } else { 0 }
    $lastScore = if ($last.scores[$a]) { $last.scores[$a] } else { 0 }
    $delta = $lastScore - $baseScore
    $dStr = if ($delta -gt 0) { "+$delta" } elseif ($delta -lt 0) { "$delta" } else { "-" }
    $dColor = if ($delta -gt 0) {"Green"} elseif ($delta -lt 0) {"Red"} else {"Gray"}

    $line = "  | $($a.PadRight(19)) | $($baseScore.ToString().PadLeft(8)) | $($lastScore.ToString().PadLeft(8)) | "
    Write-Host $line -NoNewline -ForegroundColor Gray
    Write-Host $dStr.PadLeft(8) -NoNewline -ForegroundColor $dColor
    Write-Host " |" -ForegroundColor Gray
}

Write-Host (" " * 2) -NoNewline
Write-Host ("-" * 55) -ForegroundColor Gray
$baseTotal = $first.totalScore; $lastTotal = $last.totalScore; $deltaTotal = $lastTotal - $baseTotal
$dTotalColor = if ($deltaTotal -gt 0) {"Green"} elseif ($deltaTotal -lt 0) {"Red"} else {"Gray"}
$totalLine = "  | $('TOTAL'.PadRight(19)) | $($baseTotal.ToString().PadLeft(8)) | $($lastTotal.ToString().PadLeft(8)) | "
Write-Host $totalLine -NoNewline -ForegroundColor Gray
Write-Host $deltaTotal.ToString().PadLeft(8) -NoNewline -ForegroundColor $dTotalColor
Write-Host " |" -ForegroundColor Gray
Write-Host (" " * 2) -NoNewline
Write-Host ("-" * 55) -ForegroundColor Gray

$overallPct = $last.pct
if ($overallPct -ge 90) { $grade = "A (EXCELENTE)" } elseif ($overallPct -ge 80) { $grade = "B (BUENO)" } elseif ($overallPct -ge 60) { $grade = "C (REGULAR)" } elseif ($overallPct -ge 40) { $grade = "D (MALO)" } else { $grade = "F (CRITICO)" }
$gradeColor = if ($overallPct -ge 80) {"Green"} elseif ($overallPct -ge 60) {"Yellow"} else {"Red"}
Write-Host ""
Write-Host "  Grade: $grade ($overallPct%)" -ForegroundColor $gradeColor

if ($last.criticalMissing.Count -gt 0) {
    Write-Host ""
    Write-Host "  CRITICAL GAPS still present:" -ForegroundColor Red
    foreach ($g in $last.criticalMissing) {
        Write-Host "     - $g" -ForegroundColor Red
    }
    Write-Host "  -> Fix these before proceeding with development" -ForegroundColor Yellow
}

# --- Save metrics ---
if ($SaveMetrics) {
    $metricsDir = "$ProjectPath\docs\metricas"
    if (-not (Test-Path $metricsDir)) {
        New-Item -ItemType Directory -Path $metricsDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $baselineFile = "$metricsDir\intake-baseline.json"

    $metrics = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        project = $ProjectPath
        type = $ProjectType
        iterations = $Iterations
        elapsedSeconds = $elapsed
        baseline = @{}
        current = @{}
        delta = @{}
        overall_pct = $overallPct
        critical_gaps = $last.criticalMissing
    }

    foreach ($a in $allArtifacts) {
        $metrics.baseline[$a] = if ($first.scores[$a]) { $first.scores[$a] } else { 0 }
        $metrics.current[$a] = if ($last.scores[$a]) { $last.scores[$a] } else { 0 }
        $metrics.delta[$a] = $metrics.current[$a] - $metrics.baseline[$a]
    }

    $metricsJson = $metrics | ConvertTo-Json
    $metricsJson | Out-File -FilePath $baselineFile -Encoding utf8

    # Human-readable markdown report
    $mdFile = "$metricsDir\intake-report-$timestamp.md"
    $mdContent = @"
# Intake Verification Report

**Project**: $ProjectPath
**Type**: $ProjectType
**Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Iterations**: $Iterations
**Elapsed**: ${elapsed}s
**Grade**: $grade ($overallPct%)

## Score Progression

| Artifact | Baseline | Current | Delta |
|----------|----------|---------|-------|
"@
    foreach ($a in $allArtifacts) {
        $b = if ($first.scores[$a]) { $first.scores[$a] } else { 0 }
        $c = if ($last.scores[$a]) { $last.scores[$a] } else { 0 }
        $d = $c - $b
        $dStr = if ($d -gt 0) { "+$d" } elseif ($d -lt 0) { "$d" } else { "-" }
        $mdContent += "`n| $a | $b/10 | $c/10 | $dStr |"
    }

    $mdContent += @"

## Artifact Details (Final Iteration)

| Artifact | Status | Detail |
|----------|--------|--------|
"@
    $statusMap = @{}
    $statusMap["roadmap"] = "Roadmap"
    $statusMap["pr"] = "PR"
    $statusMap["prd"] = "PRD/Specs"
    $statusMap["readme"] = "README"
    $statusMap["tests"] = "Tests"
    $statusMap["cicd"] = "CI/CD"
    $statusMap["monitoring"] = "Monitoring"
    foreach ($a in $allArtifacts) {
        $icon = if ($last.results[$a]) { $last.results[$a] } else { "-" }
        $score = if ($last.scores[$a]) { $last.scores[$a] } else { 0 }
        $mdContent += "`n| $($statusMap[$a]) | $icon | Score: $score/10 |"
    }

    if ($last.criticalMissing.Count -gt 0) {
        $mdContent += @"

## Critical Gaps
"@
        foreach ($g in $last.criticalMissing) {
            $mdContent += "`n- **$g**: Missing - Blocker"
        }
    }

    $mdContent | Out-File -FilePath $mdFile -Encoding utf8
    Write-Host ""
    Write-Host "Metrics saved: $baselineFile" -ForegroundColor Cyan
    Write-Host "Report saved: $mdFile" -ForegroundColor Cyan
}

# Return code
if ($last.criticalMissing.Count -gt 0) { exit 2 }
if ($overallPct -lt 80) { exit 1 }
exit 0
