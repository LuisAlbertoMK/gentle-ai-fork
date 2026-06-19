#requires -Version 5.1

<#
.SYNOPSIS
    Pull-from-Upstream Workflow — detect, classify, and selectively apply upstream changes.
.DESCRIPTION
    Compares this fork (master) against upstream/main, categorizes changes by
    directory and type (new/modified/ours-only), and optionally applies safe changes.

    Path mapping:
      upstream skills/ -> .agents/skills/ (our canonical location)
      upstream scripts/ -> scripts/ (direct)
      upstream root files -> root (README, LICENSE, etc.)

    Modes:
      Check   (default) — show drift report only.
      Apply-New        — fetch upstream and checkout NEW files (safe, no conflicts).
      Apply-File       — checkout a specific file from upstream. Usage: -TargetFile "path"
.PARAMETER Mode
    Operation mode: Check, Apply-New, or Apply-File.
.PARAMETER TargetFile
    File path to apply from upstream (use with Apply-File mode).
.PARAMETER Branch
    Upstream branch to compare against (default: main).
.PARAMETER Remote
    Upstream remote name (default: upstream).
.EXAMPLE
    .\scripts\pull-upstream.ps1 -Mode Check
    .\scripts\pull-upstream.ps1 -Mode Apply-New
    .\scripts\pull-upstream.ps1 -Mode Apply-File -TargetFile "scripts/example.ps1"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Check', 'Apply-New', 'Apply-File')]
    [string]$Mode = 'Check',

    [string]$TargetFile = '',

    [string]$Branch = 'main',

    [string]$Remote = 'upstream'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Resolve-Path "$PSScriptRoot/.."
Push-Location $repoRoot

# ---- helpers ----
function Write-Header {
    param([string]$Text)
    Write-Host "`n========================================"
    Write-Host "  $Text"
    Write-Host "========================================"
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n--- $Text ---"
}

function Test-GitRemote {
    param([string]$Name)
    $remotes = git remote
    return $remotes -contains $Name
}

# ---- path mapping tables ----
# Upstream paths we care about and their local equivalents
$pathMap = @(
    @{ Upstream = 'skills/';    Local = '.agents/skills/'; Label = 'Skills' }
    @{ Upstream = 'scripts/';   Local = 'scripts/';        Label = 'Scripts' }
    @{ Upstream = '';           Local = '';                 Label = 'Root files' }
)

# ---- main ----
Write-Header "Pull-from-Upstream Workflow"

# 1. Validate remote
if (-not (Test-GitRemote $Remote)) {
    Write-Warning "Remote '$Remote' not found. Add it: git remote add $Remote <url>"
    Pop-Location; exit 1
}

# 2. Fetch
Write-Host "Fetching $Remote/$Branch..."
$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
git fetch $Remote $Branch 2>&1 | Out-Null
$ErrorActionPreference = $savedEAP
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Fetch failed. Check remote URL and network."
    Pop-Location; exit 1
}

# 3. Compute drift
$remoteRef = "$Remote/$Branch"
$localRef = "HEAD"

Write-Host "`nDrift summary:"
$behind = git rev-list --count "${localRef}..${remoteRef}" 2>&1
$ahead  = git rev-list --count "${remoteRef}..${localRef}" 2>&1
Write-Host "  Behind ${remoteRef}: $behind commits (new upstream changes)"
Write-Host "  Ahead of ${remoteRef}: $ahead commits (our local changes)"
Write-Host "  Total diff: $([int]$behind + [int]$ahead) commits"

# 4. File-level comparison per path
Write-Header "File-Level Analysis"

$newUpstreamFiles = @()
$modifiedFiles    = @()
$ourOnlyFiles     = @()

foreach ($map in $pathMap) {
    $upPrefix = $map.Upstream
    $locPrefix = $map.Local
    $label = $map.Label

    if ([string]::IsNullOrEmpty($upPrefix)) {
        # Root files — compare root-level files (no .md, no hidden)
        $upFiles = @(git ls-tree -r --name-only $remoteRef | Where-Object {
            $_ -notmatch '^skills/|^scripts/|^\.' -and $_ -notlike '*/'
        })
        $locFiles = @(git ls-tree -r --name-only $localRef | Where-Object {
            $_ -notmatch '^\.agents/skills/|^scripts/|^\.' -and $_ -notlike '*/'
        })
    } else {
        $upFiles = @(git ls-tree -r --name-only $remoteRef -- "$upPrefix" | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($locPrefix) -and $locPrefix -ne $upPrefix) {
                # Path mapping: replace upstream prefix with local prefix
                $_.Replace($upPrefix, $locPrefix)
            } else { $_ }
        })
        $locFiles = @(git ls-tree -r --name-only $localRef -- "$locPrefix" | ForEach-Object { $_ })
    }

    # Ensure distinct sets
    $upSet = @($upFiles | Sort-Object -Unique)
    $locSet = @($locFiles | Sort-Object -Unique)

    # NEW: in upstream but not locally
    $new = @($upSet | Where-Object { $_ -notin $locSet })
    # MODIFIED: in both — check content hash
    $common = @($upSet | Where-Object { $_ -in $locSet })
    # OURS ONLY: in local but not upstream
    $ours = @($locSet | Where-Object { $_ -notin $upSet })

    if ($label -eq 'Root files') {
        # For root files, show a sample
        $new = $new | Where-Object { $_ -notmatch '\.md$|LICENSE' }  # skip doc-only
    }

    # Get upstream hash for common files to check if modified
    $modified = @()
    if ($label -ne 'Root files') {
        # For Skills and Scripts, check actual modification
        # Upstream hash
        $upHashes = @{}
        if ([string]::IsNullOrEmpty($upPrefix)) {
            $rootItems = @(git ls-tree $remoteRef | ForEach-Object {
                $parts = $_ -split '\s+'
                @{ Hash = $parts[2]; Path = $parts[3] }
            })
            $rootItems | ForEach-Object { $upHashes[$_.Path] = $_.Hash }
        } else {
            $upItems = @(git ls-tree -r $remoteRef -- "$upPrefix" | ForEach-Object {
                # Map path
                $path = ($_ -split '\s+')[3]
                $localPath = $path
                if (-not [string]::IsNullOrEmpty($locPrefix) -and $locPrefix -ne $upPrefix) {
                    $localPath = $path.Replace($upPrefix, $locPrefix)
                }
                @{ Hash = ($_ -split '\s+')[2]; Path = $localPath }
            })
            $upItems | ForEach-Object { $upHashes[$_.Path] = $_.Hash }
        }

        # Local hash
        $locHashes = @{}
        if ([string]::IsNullOrEmpty($locPrefix)) {
            $locItems = @(git ls-tree $localRef | ForEach-Object {
                $parts = $_ -split '\s+'
                @{ Hash = $parts[2]; Path = $parts[3] }
            })
            $locItems | ForEach-Object { $locHashes[$_.Path] = $_.Hash }
        } else {
            $locItems = @(git ls-tree -r $localRef -- "$locPrefix" | ForEach-Object {
                $parts = $_ -split '\s+'
                @{ Hash = $parts[2]; Path = $parts[3] }
            })
            $locItems | ForEach-Object { $locHashes[$_.Path] = $_.Hash }
        }

        # Find modified (different hash, excluding path-mapped new files)
        foreach ($path in $common) {
            if ($upHashes[$path] -and $locHashes[$path] -and $upHashes[$path] -ne $locHashes[$path]) {
                $modified += $path
            }
        }
    }

    Write-Section $label
    if ($new.Count -gt 0) {
        Write-Host "  NEW (upstream only, safe to add): $($new.Count) files"
        $new | ForEach-Object { Write-Host "    + $_" }
    }
    if ($modified.Count -gt 0) {
        Write-Host "  MODIFIED (both changed, may conflict): $($modified.Count) files"
        $modified | ForEach-Object { Write-Host "    ~ $_" }
    }
    if ($ours.Count -gt 0) {
        Write-Host "  OURS ONLY (local additions): $($ours.Count) files"
        $ours | ForEach-Object { Write-Host "    - $_" }
    }
    if ($new.Count -eq 0 -and $modified.Count -eq 0 -and $ours.Count -eq 0) {
        Write-Host "  (no changes)"
    }

    $newUpstreamFiles += $new
    $modifiedFiles += $modified
    $ourOnlyFiles += $ours
}

# 5. Summary
Write-Header "Summary"
Write-Host "  New files upstream (safe to apply): $($newUpstreamFiles.Count)"
Write-Host "  Files changed both sides (review):  $($modifiedFiles.Count)"
Write-Host "  Files only local (keep):            $($ourOnlyFiles.Count)"

# 6. Mode-specific actions
if ($Mode -eq 'Apply-New') {
    Write-Header "Apply-New Mode"

    # Filter: only apply skills/ and scripts/ changes, skip Go source & test data
    $safeFiles = $newUpstreamFiles | Where-Object {
        $_ -match '^\.agents/skills/' -or $_ -match '^scripts/'
    }
    $skipped = @($newUpstreamFiles | Where-Object { $_ -notin $safeFiles })

    if ($skipped.Count -gt 0) {
        Write-Host "Skipping $($skipped.Count) upstream source files (Go code, tests, config)."
        Write-Host "  Use -Apply-File -TargetFile <path> for individual files."
    }

    if ($safeFiles.Count -eq 0) {
        Write-Host "No new skills or scripts to apply."
        Pop-Location; exit 0
    }

    Write-Host "Applying $($safeFiles.Count) new files (skills/scripts) from $Remote/$Branch..."
    $applied = 0
    $failed = 0

    foreach ($file in $safeFiles) {
        # Reverse path mapping for git checkout
        $upstreamPath = $file
        foreach ($map in $pathMap) {
            if (-not [string]::IsNullOrEmpty($map.Local) -and $file.StartsWith($map.Local)) {
                $upstreamPath = $file.Replace($map.Local, $map.Upstream)
                break
            }
        }

        # Ensure parent dir exists
        $parentDir = Split-Path $file -Parent
        if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        # Checkout from upstream
        Write-Host "  + $file"
        $savedEAP2 = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        git checkout "$Remote/$Branch" -- "$upstreamPath" 2>&1 | Out-Null
        $ErrorActionPreference = $savedEAP2
        if ($LASTEXITCODE -eq 0) {
            # If path was mapped, rename to local path
            if ($upstreamPath -ne $file) {
                if (Test-Path $upstreamPath) {
                    Move-Item -Path $upstreamPath -Destination $file -Force
                }
            }
            $applied++
            $null = git add $file 2>&1
        } else {
            Write-Warning "  FAILED: $upstreamPath"
            $failed++
        }
    }

    Write-Host "`nResult: $applied applied, $failed failed."
    if ($applied -gt 0) {
        Write-Host "Files staged. Review with 'git status' then commit."
    }
}

if ($Mode -eq 'Apply-File') {
    Write-Header "Apply-File Mode"
    if ([string]::IsNullOrEmpty($TargetFile)) {
        Write-Warning "Usage: -TargetFile 'path/to/file.ps1'"
        Pop-Location; exit 1
    }

    # Reverse path mapping
    $upstreamPath = $TargetFile
    foreach ($map in $pathMap) {
        if (-not [string]::IsNullOrEmpty($map.Local) -and $TargetFile.StartsWith($map.Local)) {
            $upstreamPath = $TargetFile.Replace($map.Local, $map.Upstream)
            break
        }
    }

    Write-Host "Checking out '$upstreamPath' from $Remote/$Branch..."
    git checkout "$Remote/$Branch" -- "$upstreamPath" 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($upstreamPath -ne $TargetFile) {
            $parentDir = Split-Path $TargetFile -Parent
            if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            Move-Item -Path $upstreamPath -Destination $TargetFile -Force
        }
        Write-Host "Done. Review the file with 'git diff --cached $TargetFile'"
    } else {
        Write-Warning "Failed to checkout '$upstreamPath' from upstream."
    }
}

Pop-Location
exit 0
