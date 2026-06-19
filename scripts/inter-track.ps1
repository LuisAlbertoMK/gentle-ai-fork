#requires -Version 5.1

<#
.SYNOPSIS
  Track inter(30) — meaningful interactions per improvement cycle.
  Each "inter" = one fix+verify+log cycle (not trivial changes).

.DESCRIPTION
  Maintains a JSON counter at .learnings/inter-track.json.
  - Increment: .\scripts\inter-track.ps1 -Increment
  - Read current: .\scripts\inter-track.ps1
  - Reset cycle: .\scripts\inter-track.ps1 -Reset
  - Set target: .\scripts\inter-track.ps1 -Target 30

.PARAMETER Increment
  Increment the counter by 1.

.PARAMETER Reset
  Reset counter to 0 for a new cycle.

.PARAMETER Target
  Set the inter target for current cycle (default: 30).

.PARAMETER Quiet
  Output JSON only (machine-readable).
#>

param(
    [switch]$Increment,
    [switch]$Reset,
    [int]$Target = 30,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$trackPath = Join-Path -Path $repoRoot -ChildPath ".learnings\inter-track.json"

# Initialize if not exists
if (-not (Test-Path -LiteralPath $trackPath)) {
    $init = @{
        cycle  = @{
            id     = ""
            start  = ""
            target = $Target
            count  = 0
        }
        history = @()
    }
    $init | ConvertTo-Json | Set-Content -LiteralPath $trackPath -Encoding UTF8
}

$data = Get-Content -LiteralPath $trackPath -Raw | ConvertFrom-Json

if ($Reset) {
    $cycleId = "CYC-" + (Get-Date -Format "yyyyMMdd") + "-" + (Get-Random -Minimum 100 -Maximum 999)
    # Archive current cycle to history
    if ($data.cycle.count -gt 0) {
        $archived = [PSCustomObject]@{
            id     = $data.cycle.id
            start  = $data.cycle.start
            target = $data.cycle.target
            count  = $data.cycle.count
            end    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $data.history = @($data.history) + @($archived)
    }
    $data.cycle = @{
        id     = $cycleId
        start  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        target = $Target
        count  = 0
    }
    if (-not $Quiet) {
        Write-Host "[inter-track] Reset. New cycle: $cycleId (target: $Target)" -ForegroundColor Cyan
    }
}

if ($Increment) {
    $data.cycle.count = [int]$data.cycle.count + 1
    if (-not $Quiet) {
        $remaining = [int]$data.cycle.target - [int]$data.cycle.count
        if ($remaining -le 0) {
            Write-Host "[inter-track] ✅ Target met: $($data.cycle.count)/$($data.cycle.target)" -ForegroundColor Green
        } else {
            Write-Host "[inter-track] inter: $($data.cycle.count)/$($data.cycle.target) ($remaining remaining)" -ForegroundColor Yellow
        }
    }
}

# Save
$data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $trackPath -Encoding UTF8

# Output
$result = [PSCustomObject]@{
    cycleId  = $data.cycle.id
    count    = [int]$data.cycle.count
    target   = [int]$data.cycle.target
    complete = ([int]$data.cycle.count -ge [int]$data.cycle.target)
    remaining = [Math]::Max(0, [int]$data.cycle.target - [int]$data.cycle.count)
}

if ($Quiet) {
    $result | ConvertTo-Json
} else {
    Write-Host "  Cycle: $($data.cycle.id) | inter: $($data.cycle.count)/$($data.cycle.target)" -ForegroundColor Cyan
    # Show score when in Show mode (used by !cycle)
    if (-not $Increment -and -not $Reset) {
        $scorePath = Join-Path -Path $repoRoot -ChildPath ".project.json"
        if (Test-Path $scorePath) {
            try {
                $scoreData = Get-Content $scorePath -Raw | ConvertFrom-Json
                Write-Host "  Score: $($scoreData.score.current)/10 (trend: $($scoreData.score.trend))" -ForegroundColor Green
            } catch {
                Write-Debug "inter-track: cannot read score ($($_.Exception.Message))"
            }
        }
    }
}
