#requires -Version 5.1

<#
.SYNOPSIS
  Run cross-session pattern extraction via Engram
.DESCRIPTION
  Executes the dreaming process: searches Engram for error/bugfix patterns,
  consolidates learnings, and updates LEARNINGS.md / ERRORS.md.
.PARAMETER Mode
  Modo de ejecución: full (complete cycle), quick (summary only), report (default).
#>
param(
    [ValidateSet('full','quick','report')]
    [string]$Mode = 'report'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$learningsDir = Join-Path $repoRoot '.learnings'
$logFile = Join-Path $learningsDir 'LEARNINGS.md'
$errorFile = Join-Path $learningsDir 'ERRORS.md'
$catalogFile = Join-Path $repoRoot 'ANTI-PATTERN-CATALOG.md'
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
$cycleId = "DRM-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not (Test-Path $learningsDir)) {
    New-Item -ItemType Directory -Path $learningsDir -Force | Out-Null
}

function Write-Log {
    param([string]$Section, [string]$Message)
    $line = "| $timestamp | $cycleId | $Section | $Message |"
    Add-Content -Path $logFile -Value $line
}

Write-Host "=== Dreaming Session: $cycleId ==="
Write-Host "Mode: $Mode"

# ---- Quick scan (error pattern check) ----
if ($Mode -in 'quick','full','report') {
    Write-Host '[1/3] Scanning error patterns...'

    $errorCounts = @{}
    if (Test-Path $errorFile) {
        $content = Get-Content $errorFile
        foreach ($line in $content) {
            $startsWithPipe = $line.StartsWith('|')
            $startsWithPipeTS = $line.StartsWith('| Timestamp')
            if ($startsWithPipe -and (-not $startsWithPipeTS)) {
                $parts = $line.Split('|')
                if ($parts.Count -ge 4) {
                    $errText = $parts[3].Trim()
                    $key = $errText -replace '\[.*?\]',''
                    $key = $key -replace '\s+',' '
                    $key = $key -replace '^error[:\s]+',''
                    $key = $key -replace '^fix[:\s]+',''
                    if ($key.Length -gt 3) {
                        if ($errorCounts.ContainsKey($key)) {
                            $val = $errorCounts[$key]
                            $val.Count = $val.Count + 1
                            $val.Lines = $val.Lines + @($line)
                        } else {
                            $errorCounts[$key] = @{
                                Text = $errText
                                Count = 1
                                Lines = @($line)
                            }
                        }
                    }
                }
            }
        }
    }

    $repeated = @()
    foreach ($key in $errorCounts.Keys) {
        $entry = $errorCounts[$key]
        if ($entry.Count -ge 2) {
            $repeated += $entry
        }
    }

    if ($repeated.Count -gt 0) {
        $msg = "$($repeated.Count) repeated error pattern(s) found"
        Write-Host "  WARNING: $($msg):"
        foreach ($r in $repeated) {
            $severity = 'INFO'
            if ($r.Count -ge 3) { $severity = 'CRITICAL' }
            elseif ($r.Count -ge 2) { $severity = 'WARNING' }
            Write-Host "    [$severity] $($r.Text) appears $($r.Count) times"
        }
    } else {
        Write-Host '  No repeated error patterns. Clean.'
    }
}

# ---- Learning patterns scan ----
if ($Mode -in 'full','report') {
    Write-Host '[2/3] Scanning learning patterns...'

    $learningCounts = @{}
    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile
        foreach ($line in $logContent) {
            $startsWithPipe = $line.StartsWith('|')
            $startsWithPipeTS = $line.StartsWith('| Timestamp')
            if ($startsWithPipe -and (-not $startsWithPipeTS)) {
                $parts = $line.Split('|')
                if ($parts.Count -ge 4) {
                    $section = $parts[2].Trim()
                    $msg = $parts[3].Trim()
                    $key = "$section/$msg"
                    if ($learningCounts.ContainsKey($key)) {
                        $val = $learningCounts[$key]
                        $val.Count = $val.Count + 1
                    } else {
                        $learningCounts[$key] = @{
                            Section = $section
                            Message = $msg
                            Count = 1
                        }
                    }
                }
            }
        }
    }

    $workflowPatterns = @()
    foreach ($key in $learningCounts.Keys) {
        $entry = $learningCounts[$key]
        if ($entry.Count -ge 3) {
            $workflowPatterns += $entry
        }
    }

    $workflowCount = $workflowPatterns.Count
    if ($workflowCount -gt 0) {
        Write-Host "  Found $workflowCount recurring workflow pattern(s):"
        foreach ($wp in $workflowPatterns) {
            Write-Host "    [$($wp.Section)] $($wp.Message) - $($wp.Count)x"
        }
    } else {
        Write-Host '  No recurring workflow patterns (need 3+ for promotion).'
    }
}

# ---- Anti-pattern catalog drift check ----
if ($Mode -in 'full','report') {
    Write-Host '[3/3] Checking catalog drift...'
    if (Test-Path $catalogFile) {
        $catalogItem = Get-Item $catalogFile
        $catalogContent = Get-Content $catalogFile -Raw
        $age = (Get-Date) - $catalogItem.LastWriteTime
        Write-Host "  ANTI-PATTERN-CATALOG.md last updated: $($age.Days)d $($age.Hours)h ago"

        $entryCount = 0
        $lines = $catalogContent -split "`n"
        foreach ($l in $lines) {
            if ($l -match '^## ') {
                $entryCount = $entryCount + 1
            }
        }
        Write-Host "  Catalog entries: $entryCount"
    } else {
        Write-Host '  ANTI-PATTERN-CATALOG.md not found.'
    }
}

Write-Host ''

Write-Host "=== Dreaming Complete: $cycleId ==="
$finalRepeated = 0
$finalPatterns = 0
if ($repeated.Count -gt 0) { $finalRepeated = $repeated.Count }
if ($learningCounts.Count -gt 0) { $finalPatterns = $learningCounts.Keys.Count }
$msg = "Mode=$Mode | Repeated=$finalRepeated | Patterns=$finalPatterns"
Write-Log -Section 'Dreaming' -Message $msg
