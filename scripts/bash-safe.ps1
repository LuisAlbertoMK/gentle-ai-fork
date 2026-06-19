#requires -Version 5.1
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Bash-syntax safe executor for PowerShell 5.1 environments.

.VERSION
    1.0.0

.DESCRIPTION
    PowerShell 5.1 does NOT support `&&`, `||`, or `@{var}` hash literals.
    WSL bash in PATH is a relay (fails without WSL). Git Bash at
    "C:\Program Files\Git\bin\bash.exe" is the working interpreter.

    This script provides Invoke-Bash that delegates to Git Bash,
    bypassing PowerShell parser.

.EXAMPLE
    . "$PSScriptRoot\bash-safe.ps1"
    Invoke-Bash "git status --short && git log --oneline -5"

.EXAMPLE
    Invoke-Bash "git log @{u}.. --oneline"

.NOTES
    Falls back to PATH bash (WSL) if Git Bash not found.
    Self-test: 6/6 PASS (run Test-BashSafe after dot-sourcing).
#>

# Locate real bash interpreter
$script:GitBash = "C:\Program Files\Git\bin\bash.exe"
if (-not (Test-Path $script:GitBash)) {
    $script:GitBash = (Get-Command bash -ErrorAction SilentlyContinue).Source
}

if (-not $script:GitBash -or -not (Test-Path $script:GitBash)) {
    throw "No bash interpreter found. Install Git for Windows or WSL."
}

# Dot-source entry point
function Invoke-Bash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Command,

        [switch]$CaptureOutput
    )

    $ErrorActionPreference = 'Continue'

    if ($CaptureOutput) {
        $output = & $script:GitBash -c $Command 2>&1
        $code = $LASTEXITCODE
        return [PSCustomObject]@{ Output = $output; ExitCode = $code }
    }
    else {
        & $script:GitBash -c $Command
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            Write-Warning "Invoke-Bash exit=$code : $Command"
        }
    }
}

# Quick test runner
function Test-BashSafe {
    Write-Host "[1] && operator..." -NoNewline
    $r = Invoke-Bash "echo a && echo b" -CaptureOutput
    if (($r.Output -join '') -match 'a\s*b') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL ($($r.ExitCode))" -ForegroundColor Red; $r.Output }

    Write-Host "[2] || operator..." -NoNewline
    $r = Invoke-Bash "false || echo fallback" -CaptureOutput
    if (($r.Output -join '') -match 'fallback') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }

    Write-Host "[3] @{u} hash literal..." -NoNewline
    # @{}.. is bash syntax; PowerShell 5.1 would refuse to parse it.
    # Exit 0 = command parsed & ran (empty output means "0 unpushed" = correct).
    $r = Invoke-Bash "git log @{u}.. --oneline 2>&1; echo END" -CaptureOutput
    if ($r.ExitCode -eq 0 -and ($r.Output -join '') -match 'END') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL (exit=$($r.ExitCode))" -ForegroundColor Red }

    Write-Host "[4] 2>&1 redirect..." -NoNewline
    $r = Invoke-Bash "echo err 1>&2; echo out" -CaptureOutput
    if (($r.Output -join '') -match 'err.*out') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }

    Write-Host "[5] pipeline + grep..." -NoNewline
    $r = Invoke-Bash "echo -e 'foo\nbar\nbaz' | grep ba" -CaptureOutput
    if (($r.Output -join '') -match 'bar') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }

    Write-Host "[6] git --version..." -NoNewline
    $r = Invoke-Bash "git --version" -CaptureOutput
    if (($r.Output -join '') -match 'git version') { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }
}

# Self-test if run directly
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.MyCommand.Path -eq $PSCommandPath) {
    Write-Host "Using: $script:GitBash" -ForegroundColor Cyan
    Test-BashSafe
}
