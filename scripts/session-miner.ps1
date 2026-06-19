<#
.SYNOPSIS
  Mine session histories for error patterns and propose corrections.
  Inspired by headroom learn -- mines failed sessions, writes to AGENTS.md.

.DESCRIPTION
  Cross-references ANTI-PATTERN-CATALOG.md, .learnings/ERRORS.md, and
  .learnings/LEARNINGS.md to detect repeated error patterns and propose
  new anti-patterns or AGENTS.md corrections.

  Designed to be called by the agent during dreaming cycle and on-demand.

.PARAMETER Mode
  scan     -- analyze and report patterns (default)
  apply    -- write proposed anti-patterns to catalog
  check    -- quick health check for pre-commit gate

.PARAMETER Json
  Output structured JSON for agent consumption.

.PARAMETER Threshold
  Minimum occurrence count to flag a pattern (default: 2).

.EXAMPLE
  .\scripts\session-miner.ps1 -Mode scan
  .\scripts\session-miner.ps1 -Mode scan -Threshold 1 -Json
  .\scripts\session-miner.ps1 -Mode apply

.NOTES
  PS5.1 compatible -- ASCII-only, no emoji, no Unicode box-drawing.
  Uses -cmatch for case-sensitive matching.
#>

param(
    [ValidateSet('scan','apply','check')]
    [string]$Mode = 'scan',

    [switch]$Json,

    [int]$Threshold = 2
)

Set-StrictMode -Version 5.1
$ErrorActionPreference = 'Stop'

# -- Paths -------------------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path -Path $repoRoot -ChildPath 'ANTI-PATTERN-CATALOG.md'
$learningsDir = Join-Path -Path $repoRoot -ChildPath '.learnings'
$errorsPath = Join-Path -Path $learningsDir -ChildPath 'ERRORS.md'
$learningsPath = Join-Path -Path $learningsDir -ChildPath 'LEARNINGS.md'

# -- Helpers -----------------------------------------------------------------

function Read-Catalog {
    <# Parse ANTI-PATTERN-CATALOG.md into pattern objects #>
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        return @()
    }

    $content = Get-Content -LiteralPath $catalogPath -Raw
    $patterns = @()

    # Match each row in the table (pipe-delimited rows)
    $rows = [regex]::Matches($content, '^\|\s*\d+\s*\|.*?\|.*?\|.*?\|.*?\|.*?\|.*?\|', [System.Text.RegularExpressions.RegexOptions]::Multiline)

    foreach ($row in $rows) {
        $parts = $row.Value -split '\|' | ForEach-Object { $_.Trim() }
        if ($parts.Count -ge 8) {
            $parsedId = 0
            if ($parts[1]) {
                $tryResult = [int]::TryParse($parts[1], [ref]$parsedId)
                if (-not $tryResult) { $parsedId = 0 }
            }
            $patterns += [PSCustomObject]@{
                Id         = $parsedId
                Date       = $parts[2]
                Pattern    = $parts[3]
                Symptom    = $parts[4]
                RootCause  = $parts[5]
                Fix        = $parts[6]
                Prevention = $parts[7]
            }
        }
    }

    return $patterns
}

function Read-LearningsPatternKey {
    <# Extract Pattern-Key entries from LEARNINGS.md #>
    if (-not (Test-Path -LiteralPath $learningsPath)) {
        return @()
    }

    $content = Get-Content -LiteralPath $learningsPath -Raw
    $keys = @()

    # Match Pattern-Key values
    $patternMatches = [regex]::Matches($content, 'Pattern-Key:\s*([^\n\r]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $patternMatches) {
        $keys += $m.Groups[1].Value.Trim()
    }

    return $keys
}

function Read-ErrorEntry {
    <# Parse structured error entries from ERRORS.md #>
    if (-not (Test-Path -LiteralPath $errorsPath)) {
        return @()
    }

    $content = Get-Content -LiteralPath $errorsPath -Raw
    $errors = @()

    # Match error entry headers
    $entries = [regex]::Matches($content, '##\s+\[\w+-\d+-\d+\]\s+(.+?)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($entry in $entries) {
        $errors += $entry.Groups[1].Value.Trim()
    }

    return $errors
}

function Find-RepeatedPattern {
    <# Cross-reference learnings with catalog to detect repeats #>
    param(
        [array]$CatalogPatterns,
        [array]$PatternKeys,
        [int]$MinCount
    )

    # Count occurrences of each pattern key
    $keyCounts = @{}
    foreach ($key in $PatternKeys) {
        if ($keyCounts.ContainsKey($key)) {
            $keyCounts[$key]++
        } else {
            $keyCounts[$key] = 1
        }
    }

    # Find patterns above threshold
    $repeated = @()
    foreach ($entry in $keyCounts.GetEnumerator()) {
        if ($entry.Value -ge $MinCount) {
            # Check if already cataloged
            $cataloged = $false
            foreach ($cp in $CatalogPatterns) {
                if ($cp.Pattern -cmatch [regex]::Escape($entry.Name)) {
                    $cataloged = $true
                    break
                }
            }

            $repeated += [PSCustomObject]@{
                PatternKey = $entry.Name
                Count      = $entry.Value
                Cataloged  = $cataloged
            }
        }
    }

    return $repeated
}

# -- Main --------------------------------------------------------------------

$catalog = Read-Catalog
$patternKeys = Read-LearningsPatternKey
$errors = Read-ErrorEntry

$repeated = Find-RepeatedPattern -CatalogPatterns $catalog -PatternKeys $patternKeys -MinCount $Threshold

if ($Mode -eq 'check') {
    $result = [PSCustomObject]@{
        CatalogEntries   = @($catalog).Count
        PatternKeys      = @($patternKeys).Count
        ErrorEntries     = @($errors).Count
        RepeatedPatterns = @($repeated).Count
        Mode             = 'check'
        Status           = if (@($repeated).Count -gt 0) { 'PATTERNS_FOUND' } else { 'CLEAN' }
    }

    if ($Json) {
        return ($result | ConvertTo-Json -Compress)
    }

    Write-Host '-- session-miner check --' -ForegroundColor Cyan
    Write-Host "  Catalog:    $(@($catalog).Count) entries"
    Write-Host "  Patterns:   $(@($patternKeys).Count) keys"
    Write-Host "  Errors:     $(@($errors).Count) entries"
    Write-Host "  Repeated:   $(@($repeated).Count) patterns"
    Write-Host "  Status:     $($result.Status)"
    return
}

if ($Mode -eq 'scan') {
    $uncataloged = @($repeated | Where-Object { -not $_.Cataloged })

    $result = [PSCustomObject]@{
        CatalogCount     = @($catalog).Count
        PatternKeyCount  = @($patternKeys).Count
        ErrorCount       = @($errors).Count
        RepeatedPatterns = $repeated
        UnCatalogedCount = $uncataloged.Count
        CanApply         = $uncataloged.Count -gt 0
    }

    if ($Json) {
        return ($result | ConvertTo-Json -Depth 3 -Compress)
    }

    Write-Host '== session-miner scan report ==' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Catalog:      $($catalog.Count) anti-patterns cataloged"
    Write-Host "Pattern keys: $($patternKeys.Count) from learnings"
    Write-Host "Errors:       $($errors.Count) entries"
    Write-Host ''

    if ($repeated.Count -eq 0) {
        Write-Host '[OK] No repeated patterns found (threshold: '$Threshold')' -ForegroundColor Green
        return
    }

    Write-Host '[WARN] Repeated patterns detected:' -ForegroundColor Yellow
    foreach ($r in $repeated) {
        $status = if ($r.Cataloged) { '[cataloged]' } else { '[UNCATA LOGED]' }
        Write-Host "  [$($r.Count)x] $($r.PatternKey) -- $status"
    }

    Write-Host ''
    if ($uncataloged.Count -gt 0) {
        Write-Host "Proposal: run with -Mode apply to add $($uncataloged.Count) new anti-pattern(s)" -ForegroundColor Yellow
    }

    return
}

if ($Mode -eq 'apply') {
    $uncataloged = @($repeated | Where-Object { -not $_.Cataloged })

    if ($uncataloged.Count -eq 0) {
        Write-Host '[OK] Nothing to apply -- all repeated patterns already cataloged' -ForegroundColor Green
        return
    }

    Write-Host '-- session-miner apply --' -ForegroundColor Cyan
    Write-Host "Would add $($uncataloged.Count) new anti-pattern(s) based on repeated learnings:"
    foreach ($u in $uncataloged) {
        $safeKey = $u.PatternKey -replace '[^\w-]', '_'
        Write-Host "  - [$($u.Count)x] $($u.PatternKey) -> ANTI-PATTERN-CATALOG.md + docs/anti-patterns/$safeKey.md"
    }

    Write-Host ''
    Write-Host 'Run manually: edit ANTI-PATTERN-CATALOG.md with pattern details' -ForegroundColor Yellow
    Write-Host 'Auto-apply not yet implemented' -ForegroundColor Yellow

    return
}
