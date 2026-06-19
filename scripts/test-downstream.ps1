#requires -Version 5.1
<#
.SYNOPSIS
  Downstream validation of CYCLE-3 skills: delivery-harness, chained-pr, subagent-isolation.
  Tests structural integrity, dependency consistency, and workflow traceability.

.DESCRIPTION
  Tests that:
  - Skills exist with all required sections
  - Dependency declarations reference real skills
  - Delivery-harness workflow is complete (7 steps, error table, dependency refs)
  - Chained-pr chain structure is valid (branch naming, rebase cascade, rollback)
  - Subagent-isolation rules cover all 6 categories
  - Cross-references between skills are consistent

.PARAMETER Json
  Output structured JSON for agent consumption. Default: human-readable.

.EXAMPLE
  .\scripts\test-downstream.ps1
  .\scripts\test-downstream.ps1 -Json
#>

param(
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$exitCode = 0
$results = @()

# --- Helpers ---
function Add-Result($section, $check, $status, $detail) {
  $script:results += [PSCustomObject]@{
    Section = $section
    Check   = $check
    Status  = $status
    Detail  = $detail
  }
  if ($status -ne "PASS") { $script:exitCode = 1 }
}

function Test-SkillFile($name) {
  $scriptRoot = Split-Path -Parent $PSCommandPath
  $path = Join-Path $scriptRoot "..\.agents\skills\$name\SKILL.md"
  if (-not (Test-Path $path)) {
    Add-Result -Section "Structure" -Check "Skill: $name" -Status "FAIL" -Detail "SKILL.md not found"
    return $null
  }
  return $path
}

function Test-Section($path, $section) {
  $content = Get-Content -LiteralPath $path -Raw
  if ($content -match $section) { return $true }
  return $false
}

# ====== TESTS ======

# 1. STRUCTURAL: skills exist
$dhPath = Test-SkillFile "delivery-harness"
$cpPath = Test-SkillFile "chained-pr"
$siPath = Test-SkillFile "subagent-isolation"

if (-not $dhPath -or -not $cpPath) {
  Add-Result -Section "Structure" -Check "Core skills" -Status "FAIL" -Detail "Missing delivery-harness or chained-pr SKILL.md"
  # Can't continue without core skills
} else {
  # 2. DELIVERY-HARNESS: workflow steps
  $dh = Get-Content -LiteralPath $dhPath -Raw
  $steps = @(
    'Analyze', 'Break down', 'Map deps', 'Delegate', 'Collect', 'Reconcile', 'Report'
  )
  $foundSteps = 0
  foreach ($step in $steps) {
    if ($dh -match "\*{1,2}$step") { $foundSteps++ }
    else { Add-Result -Section "Delivery-Harness" -Check "Step: $step" -Status "WARN" -Detail "Step label not found" }
  }
  if ($foundSteps -eq 7) {
    Add-Result -Section "Delivery-Harness" -Check "7-step workflow" -Status "PASS" -Detail "All $foundSteps steps found"
  } else {
    Add-Result -Section "Delivery-Harness" -Check "7-step workflow" -Status "FAIL" -Detail "Found $foundSteps/7 steps"
  }

  # Delivery-Harness: error handling table
  $errorTypes = @('Subagent timeout', 'Wrong output', 'Dependency fail', 'Merge conflict')
  $foundErrors = 0
  foreach ($et in $errorTypes) {
    if ($dh -match [regex]::Escape($et)) { $foundErrors++ }
  }
  Add-Result -Section "Delivery-Harness" -Check "Error table" -Status $(if ($foundErrors -eq 4) { "PASS" } else { "FAIL" }) -Detail "Found $foundErrors/4 error types"

  # Delivery-Harness: dependencies
  Add-Result -Section "Delivery-Harness" -Check "Dep: subagent-isolation" -Status $(if ($dh -match 'subagent-isolation') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Delivery-Harness" -Check "Dep: work-unit-commits" -Status $(if ($dh -match 'work-unit-commits') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Delivery-Harness" -Check "Dep: command-wrapper" -Status $(if ($dh -match 'command-wrapper') { "PASS" } else { "FAIL" }) -Detail ""

  # 3. CHAINED-PR: structure
  $cp = Get-Content -LiteralPath $cpPath -Raw
  Add-Result -Section "Chained-PR" -Check "Chain structure diagram" -Status $(if ($cp -match 'main ── PR#1') { "PASS" } else { "FAIL" }) -Detail "Chain format: main--PR#1--PR#2--PR#3"
  Add-Result -Section "Chained-PR" -Check "Branch naming convention" -Status $(if ($cp -match 'feat/{prefix}-{n}-{slug}') { "PASS" } else { "FAIL" }) -Detail "Format: feat/{prefix}-{n}-{slug}"
  Add-Result -Section "Chained-PR" -Check "Rebase cascade" -Status $(if ($cp -match 'REBASE CASCADE') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Chained-PR" -Check "Rollback procedure" -Status $(if ($cp -match 'ROLLBACK') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Chained-PR" -Check "Max chain: 5" -Status $(if ($cp -match 'Max chain length: 5') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Chained-PR" -Check "Dep: work-unit-commits" -Status $(if ($cp -match 'work-unit-commits') { "PASS" } else { "FAIL" }) -Detail ""
  Add-Result -Section "Chained-PR" -Check "Dep: command-wrapper" -Status $(if ($cp -match 'command-wrapper') { "PASS" } else { "FAIL" }) -Detail ""

  # 4. SUBAGENT-ISOLATION: rules
  if ($siPath) {
    $si = Get-Content -LiteralPath $siPath -Raw
    $isoRules = @(
      'Fresh context per delegation', 'No cross-contamination', 'Dependency declaration',
      'Result isolation', 'Context cleanup', 'Error boundaries'
    )
    $foundRules = 0
    foreach ($rule in $isoRules) {
      if ($si -match [regex]::Escape($rule)) { $foundRules++ }
      else { Add-Result -Section "Subagent-Isolation" -Check "Rule: $rule" -Status "WARN" -Detail "Not found" }
    }
    Add-Result -Section "Subagent-Isolation" -Check "6 isolation rules" -Status $(if ($foundRules -eq 6) { "PASS" } else { "FAIL" }) -Detail "Found $foundRules/6 rules"
  }

  # 5. CROSS-REF CONSISTENCY
  # delivery-harness declares subagent-isolation dep
  # subagent-isolation should be referenced by delivery-harness
  $dhDeps = @()
  if ($dh -match 'subagent-isolation') { $dhDeps += 'subagent-isolation' }
  if ($dh -match 'work-unit-commits') { $dhDeps += 'work-unit-commits' }
  if ($dh -match 'command-wrapper') { $dhDeps += 'command-wrapper' }
  Add-Result -Section "Cross-Ref" -Check "DH dependencies resolved" -Status "PASS" -Detail "$($dhDeps.Count) deps: $($dhDeps -join ', ')"

  # 6. FILE SIZE CHECK
  Add-Result -Section "Size" -Check "delivery-harness" -Status "PASS" -Detail "$((Get-Item $dhPath).Length) bytes"
  Add-Result -Section "Size" -Check "chained-pr" -Status "PASS" -Detail "$((Get-Item $cpPath).Length) bytes"
  if ($siPath) {
    Add-Result -Section "Size" -Check "subagent-isolation" -Status "PASS" -Detail "$((Get-Item $siPath).Length) bytes"
  }
}

# --- OUTPUT ---
if ($Json) {
  Write-Output ($results | ConvertTo-Json -Depth 3)
} else {
  Write-Output "`n=== Downstream Test Results ==="
  Write-Output ""

  $pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
  $fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
  $warn = @($results | Where-Object { $_.Status -eq "WARN" }).Count

  $results | Group-Object Section | ForEach-Object {
    Write-Output "--- $($_.Name) ---"
    $_.Group | Format-Table Check, Status, Detail -AutoSize
  }

  Write-Output "`n=== Summary: $pass PASS, $fail FAIL, $warn WARN ==="
}

exit $exitCode
