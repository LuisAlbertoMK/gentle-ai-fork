#requires -Version 5.1

<#
.SYNOPSIS
  Compute project score from fresh repo state — zero memory required.

.DESCRIPTION
  Measures 10 dimensions objectively using only repo artifacts.
  Outputs JSON matching .project.json schema.
  Can run from a fresh clone with no session history.

.PARAMETER Json
  Output raw JSON only (no headers, no colors). Default: human-readable.

.PARAMETER Quiet
  Suppress score table, print only summary line.

.EXAMPLE
  .\scripts\score-auto.ps1                  # Human-readable table
  .\scripts\score-auto.ps1 -Json            # JSON for .project.json
  .\scripts\score-auto.ps1 -Quiet           # One-liner score
#>

param(
  [switch]$Json,
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location -LiteralPath $RepoRoot

# --- Helpers ---
$ScoreLog = @{}

function Add-DimensionLog($Name, $Score, $Max, $Evidence, $Rationale) {
  $ScoreLog[$Name] = @{
    score     = [math]::Round($Score, 1)
    max       = $Max
    evidence  = $Evidence
    rationale = $Rationale
  }
}

# --- 1. Project Artifacts ---
$ErrorActionPreference = "SilentlyContinue"
$AllSkillDirs = Get-ChildItem -Directory ".\.agents\skills" -Name
$SkillCount = ($AllSkillDirs | Where-Object { $_ -ne '_shared' }).Count
& ".\scripts\cross-ref-check.ps1" *>$null
$CrossRefOk = ($LASTEXITCODE -eq 0)
$HasReadme = Test-Path "README.md"
$HasChangelog = Test-Path "CHANGELOG.md"
$HasProjectJson = Test-Path ".project.json"
$HasRoadmap = Test-Path "ROADMAP.md"

$ArtifactScore = 10
if (-not $CrossRefOk) { $ArtifactScore -= 2 }
if (-not $HasReadme) { $ArtifactScore -= 2 }
if (-not $HasChangelog) { $ArtifactScore -= 1 }
if ($SkillCount -lt 60) { $ArtifactScore -= 2 }
if (-not $HasProjectJson) { $ArtifactScore -= 1 }
$ArtifactScore = [math]::Max(0, $ArtifactScore)

Add-DimensionLog -Name "Project Artifacts" -Score $ArtifactScore -Max 10 -Evidence @{
  skills       = $SkillCount
  cross_ref    = $CrossRefOk
  readme       = $HasReadme
  changelog    = $HasChangelog
  project_json = $HasProjectJson
  roadmap      = $HasRoadmap
} -Rationale "Cross-ref $CrossRefOk, $SkillCount skills (excl _shared)"

# --- 2. Security ---
$SecurityScore = 10
$WeakCryptoFound = $false
$SecretsFound = $false

# Weak crypto in scripts
$WeakCrypto = Select-String -Path ".\scripts\*.ps1" -Pattern "MD5|SHA1\b" -SimpleMatch | Where-Object {
  $_.Line -notmatch "SHA1ToSHA256|SHA256|# deprecat|# legacy|SHA1SHA256|Select-String.*MD5"
}
if ($WeakCrypto) { $WeakCryptoFound = $true; $SecurityScore -= 2 }

# Secrets in skills (crude scan — key=value patterns)
$Secrets = Select-String -Path ".\.agents\skills\*\SKILL.md" -Pattern "(?i)(api[_-]?key|secret|password|token|credential)\s*[=:]\s*['""][^'""]{8,}"
if ($Secrets) { $SecretsFound = $true; $SecurityScore -= 3 }

# Check PSSA latest result
if (Test-Path "docs/metricas/errors/LATEST_error.json") {
  $PssaResult = Get-Content "docs/metricas/errors/LATEST_error.json" -Raw | ConvertFrom-Json
  if ($PssaResult.source -ne "quality-gate" -or $PssaResult.passed -lt 5) { $SecurityScore -= 1 }
} else {
  $PssaOutput = & ".\scripts\pssa-gate.ps1" -Mode Check 2>&1
  if ($LASTEXITCODE -ne 0 -or $PssaOutput -match "FAIL|violation|security") { $SecurityScore -= 1 }
}

$SecurityScore = [math]::Max(0, [math]::Min(10, $SecurityScore))

Add-DimensionLog -Name "Security" -Score $SecurityScore -Max 10 -Evidence @{
  weak_crypto = $WeakCryptoFound
  secrets     = $SecretsFound
} -Rationale "Weak crypto: $WeakCryptoFound, secrets: $SecretsFound"

# --- 3. Dead Code ---
$DeadScore = 10

# Orphan files in skills\ workspace
$WorkspaceFiles = Get-ChildItem ".\skills" -File -ErrorAction SilentlyContinue
$OrphanCount = ($WorkspaceFiles | Where-Object { $_.Name -notin $AllSkillDirs }).Count
if ($OrphanCount -gt 5) { $DeadScore -= 2 }
elseif ($OrphanCount -gt 0) { $DeadScore -= 1 }

# Dead junctions
$JunctionIssues = 0
Get-ChildItem ".\skills" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  if (-not (Test-Path $_.Target)) { $JunctionIssues++ }
}
if ($JunctionIssues -gt 0) { $DeadScore -= 1 }

# Commented-out code (exclude self-detection)
$CommentedCode = Select-String -Path ".\scripts\*.ps1" -Pattern "#.*function|#.*if|#.*for\s*\(" -SimpleMatch | Where-Object {
  $_.Filename -ne "score-auto.ps1"
}
if ($CommentedCode.Count -gt 10) { $DeadScore -= 1 }

$DeadScore = [math]::Max(0, [math]::Min(10, $DeadScore))

Add-DimensionLog -Name "Dead Code" -Score $DeadScore -Max 10 -Evidence @{
  orphans        = $OrphanCount
  dead_junctions = $JunctionIssues
  commented_out  = $CommentedCode.Count
} -Rationale "Orphans: $OrphanCount, dead junctions: $JunctionIssues"

# --- 4. Clean Code ---
$Scripts = Get-ChildItem ".\scripts\*.ps1"
$TotalScripts = $Scripts.Count
$WithHelp = 0
$WithParams = 0
$WithStrict = 0

foreach ($Script in $Scripts) {
  $Content = Get-Content $Script.FullName -Raw
  if ($Content -match '<#') { $WithHelp++ }
  # param( without line-start anchor — some scripts indent differently
  if ($Content -match 'param\(') { $WithParams++ }
  if ($Content -match 'Set-StrictMode') { $WithStrict++ }
}

$CleanRatio = @($WithHelp, $WithParams, $WithStrict | ForEach-Object { [math]::Round($_ / $TotalScripts, 2) })
$CleanScore = [math]::Round(($CleanRatio[0] + $CleanRatio[1] + $CleanRatio[2]) / 3 * 10, 1)

Add-DimensionLog -Name "Clean Code" -Score $CleanScore -Max 10 -Evidence @{
  total_scripts   = $TotalScripts
  with_help       = $WithHelp
  with_params     = $WithParams
  with_strictmode = $WithStrict
} -Rationale "Scripts: $TotalScripts, help: $WithHelp, params: $WithParams, strict: $WithStrict"

# --- 5. Best Practices ---
$BestScore = [math]::Round(($WithParams / $TotalScripts) * 10, 1)

# Try/catch coverage
$WithTryCatch = 0
foreach ($Script in $Scripts) {
  if ((Get-Content $Script.FullName -Raw) -match 'try\s*\{') { $WithTryCatch++ }
}
$TryCatchRatio = $WithTryCatch / $TotalScripts
if ($TryCatchRatio -ge 0.8) { $BestScore = [math]::Min(10, $BestScore + 1) }
elseif ($TryCatchRatio -le 0.3) { $BestScore = [math]::Max(0, $BestScore - 1) }

Add-DimensionLog -Name "Best Practices" -Score $BestScore -Max 10 -Evidence @{
  param_coverage = $WithParams
  trycatch       = $WithTryCatch
} -Rationale "Params: $WithParams/$TotalScripts, try/catch: $WithTryCatch/$TotalScripts"

# --- 6. Orthography (byte-level scan, encoding-agnostic) ---
$CorruptedCount = 0
$SkillFiles = Get-ChildItem ".\.agents\skills\*\SKILL.md"
foreach ($File in $SkillFiles) {
  try {
    $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $Corrupted = $false
    for ($i = 0; $i -lt $Bytes.Length - 3; $i++) {
      # Pattern A: Ã (0xC3 0x83) + 0x80-0xBF = corrupted accented chars (áéíóúñ)
      if ($Bytes[$i] -eq 0xC3 -and $Bytes[$i+1] -eq 0x83 -and $Bytes[$i+2] -ge 0x80) {
        $Corrupted = $true; break
      }
      # Pattern B: â (0xC3 0xA2) + E2 80/82 = corrupted symbols (arrows, em dashes, box drawing)
      if ($Bytes[$i] -eq 0xC3 -and $Bytes[$i+1] -eq 0xA2 -and $i + 3 -lt $Bytes.Length) {
        if ($Bytes[$i+2] -eq 0xE2 -and ($Bytes[$i+3] -eq 0x80 -or $Bytes[$i+3] -eq 0x82)) {
          $Corrupted = $true; break
        }
      }
    }
    if ($Corrupted) { $CorruptedCount++ }
  } catch {
    Write-Debug "score-auto: cannot read bytes ($($_.Exception.Message))"
  }
}

$OrthoScore = 10
if ($CorruptedCount -gt 10) { $OrthoScore = 4 }
elseif ($CorruptedCount -gt 5) { $OrthoScore = 7 }
elseif ($CorruptedCount -gt 0) { $OrthoScore = 9 }

Add-DimensionLog -Name "Orthography" -Score $OrthoScore -Max 10 -Evidence @{
  corrupted_files = $CorruptedCount
  total_scanned   = $SkillFiles.Count
} -Rationale "Encoding corruption: $CorruptedCount/$($SkillFiles.Count) files"

# --- 7. Bitácora ---
$BitaScore = 0
if (Test-Path "BITACORA.md") {
  $BitaContent = Get-Content "BITACORA.md" -Raw
  $BitaLines = $BitaContent.Split("`n").Count
  if ($BitaLines -gt 10) { $BitaScore = 10 }
  elseif ($BitaLines -gt 5) { $BitaScore = 7 }
  else { $BitaScore = 5 }
}

Add-DimensionLog -Name "Bitácora" -Score $BitaScore -Max 10 -Evidence @{
  exists = (Test-Path "BITACORA.md")
  lines  = if (Test-Path "BITACORA.md") { (Get-Content "BITACORA.md").Count } else { 0 }
} -Rationale "BITACORA.md exists: $(Test-Path 'BITACORA.md')"

# --- 8. Metrics ---
$HasMetricsDir = Test-Path "docs/metricas"
$HasErrorsDir = Test-Path "docs/metricas/errors"
$HasErrorJson = Test-Path "docs/metricas/errors/LATEST_error.json"
$HasReports = (Get-ChildItem "docs/metricas" -File -ErrorAction SilentlyContinue).Count -gt 0

$MetricScore = 4
if ($HasMetricsDir -and $HasErrorJson) { $MetricScore = 9 }
elseif ($HasMetricsDir) { $MetricScore = 7 }
if ($HasReports -and $HasErrorsDir) { $MetricScore = [math]::Min(10, $MetricScore + 1) }

Add-DimensionLog -Name "Metrics" -Score $MetricScore -Max 10 -Evidence @{
  metrics_dir  = $HasMetricsDir
  errors_dir   = $HasErrorsDir
  error_json   = $HasErrorJson
  has_reports  = $HasReports
} -Rationale "Metrics dir: $HasMetricsDir, error json: $HasErrorJson"

# --- 9. Script Performance ---
$ScriptSizes = Get-ChildItem ".\scripts\*.ps1" | Select-Object Name, Length
$AvgSizeKB = [math]::Round(($ScriptSizes | Measure-Object -Average Length).Average / 1KB, 1)
$Over50KB = ($ScriptSizes | Where-Object { $_.Length -gt 51200 }).Count
$ScriptCount = $ScriptSizes.Count

$PerfScore = 10
if ($ScriptCount -lt 15 -or $ScriptCount -gt 35) { $PerfScore -= 1 }
if ($AvgSizeKB -gt 15) { $PerfScore -= 1 }
elseif ($AvgSizeKB -gt 20) { $PerfScore -= 2 }
if ($Over50KB -gt 0) { $PerfScore -= 2 }
$PerfScore = [math]::Max(0, [math]::Min(10, $PerfScore))

Add-DimensionLog -Name "Script Performance" -Score $PerfScore -Max 10 -Evidence @{
  script_count = $ScriptCount
  avg_size_kb  = $AvgSizeKB
  over_50kb    = $Over50KB
} -Rationale "Scripts: $ScriptCount, avg: ${AvgSizeKB}KB, >50KB: $Over50KB"

# --- 10. Skill Effectiveness ---
$SkillFiles = Get-ChildItem ".\.agents\skills\*\SKILL.md" | Where-Object { $_.Directory.Name -ne '_shared' }
$TotalSkills = $SkillFiles.Count
$Over3KB = ($SkillFiles | Where-Object { $_.Length -gt 3072 }).Count
$Over5KB = ($SkillFiles | Where-Object { $_.Length -gt 5120 }).Count
$TotalBytes = ($SkillFiles | Measure-Object -Sum Length).Sum
$AvgSkillKB = [math]::Round($TotalBytes / $TotalSkills / 1KB, 1)

$EffectScore = 10
if ($Over5KB -gt 0) { $EffectScore -= 2 }
elseif ($Over3KB -gt 3) { $EffectScore -= 2 }
elseif ($Over3KB -gt 1) { $EffectScore -= 1 }
if ($AvgSkillKB -le 2.5) { $EffectScore = [math]::Min(10, $EffectScore + 0.5) }
if ($TotalSkills -lt 60) { $EffectScore -= 2 }
$EffectScore = [math]::Round([math]::Max(0, [math]::Min(10, $EffectScore)), 1)

Add-DimensionLog -Name "Skill Effectiveness" -Score $EffectScore -Max 10 -Evidence @{
  total_skills   = $TotalSkills
  over_3kb       = $Over3KB
  over_5kb       = $Over5KB
  avg_size_kb    = $AvgSkillKB
  total_bytes    = $TotalBytes
} -Rationale "Skills: $TotalSkills, >3KB: $Over3KB, >5KB: $Over5KB, avg: ${AvgSkillKB}KB"

# --- 11. Cycle Progress (inter(30)) ---
$InterTrackPath = ".learnings\inter-track.json"
$CycleScore = 0
$InterCount = 0
$InterTarget = 30
if (Test-Path $InterTrackPath) {
  try {
    $InterData = Get-Content $InterTrackPath -Raw | ConvertFrom-Json
    $InterCount = [int]$InterData.cycle.count
    $InterTarget = [int]$InterData.cycle.target
    # Score = (count / target) * 10, capped at 10
    $CycleScore = [math]::Min(10, [math]::Round(($InterCount / $InterTarget) * 10, 1))
  } catch {
    $CycleScore = 0
  }
}

Add-DimensionLog -Name "Cycle Progress" -Score $CycleScore -Max 10 -Evidence @{
  inter_count  = $InterCount
  inter_target = $InterTarget
} -Rationale "inter: $InterCount/$InterTarget"

# --- Composite ---
$AllScores = $ScoreLog.Values | ForEach-Object { $_.score }
$FinalScore = [math]::Round(($AllScores | Measure-Object -Average).Average, 1)

# --- Output ---
$DimOrder = @(
  "Project Artifacts", "Security", "Dead Code", "Clean Code",
  "Best Practices", "Orthography", "Bitácora", "Metrics",
  "Script Performance", "Skill Effectiveness",
  "Cycle Progress"
)

$Result = @{
  score = @{
    current      = $FinalScore
    dimensions   = [ordered]@{}
    last_updated = (Get-Date -Format "yyyy-MM-dd")
    trend        = "stable"
  }
  dimensions_detail = $ScoreLog
}
foreach ($Dim in $DimOrder) { $Result.score.dimensions[$Dim] = $ScoreLog[$Dim].score }

# Trend vs .project.json
if (Test-Path ".project.json") {
  try {
    $Prev = Get-Content ".project.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $PrevScore = $Prev.score.current
    if ($FinalScore -gt $PrevScore) { $Result.score.trend = "up" }
    elseif ($FinalScore -lt $PrevScore) { $Result.score.trend = "down" }
    else { $Result.score.trend = "stable" }
  } catch { $Result.score.trend = "unknown" }
}

if ($Json) {
  $Result | ConvertTo-Json -Depth 4
} elseif ($Quiet) {
  Write-Host "Score: $FinalScore/10 (trend: $($Result.score.trend))"
} else {
  Write-Host "`n=== Project Score: gentleman-agent-gh ===" -ForegroundColor Cyan
  Write-Host "Date: $($Result.score.last_updated)  |  Trend: $($Result.score.trend)" -ForegroundColor Gray
  Write-Host "`nDimensions:" -ForegroundColor Yellow
  foreach ($Dim in $DimOrder) {
    $D = $ScoreLog[$Dim]
    $Rounded = [math]::Round($D.score)
    $Dots = 10 - $Rounded
    if ($Dots -lt 0) { $Dots = 0 }
    $Bar = ("#" * $Rounded) + ("." * $Dots)
    $Color = if ($D.score -ge 9) { "Green" } elseif ($D.score -ge 7) { "Yellow" } else { "Red" }
    $DimScore = $D.score.ToString('F1').PadLeft(4)
    $DimLabel = $Dim.PadRight(22)
    Write-Host "  $DimLabel $DimScore/10  [$Bar]" -ForegroundColor $Color
  }
  Write-Host "  $(('-' * 42))" -ForegroundColor Gray
  $ScoreStr = $FinalScore.ToString('F1').PadLeft(4)
  $TotalLabel = ('TOTAL').PadRight(22)
  Write-Host "  $TotalLabel $ScoreStr/10" -ForegroundColor White
  Write-Host "`nEvidence:" -ForegroundColor Gray
  foreach ($Dim in $DimOrder) {
    $D = $ScoreLog[$Dim]
    $Parts = ($D.evidence.Keys | ForEach-Object { "$_=$($D.evidence[$_])" })
    Write-Host "  $($Dim): $($Parts -join ', ')" -ForegroundColor DarkGray
  }
  Write-Host "`nTo update .project.json: .\scripts\score-auto.ps1 -Json | Set-Content .project.json -Encoding UTF8" -ForegroundColor Cyan
}
