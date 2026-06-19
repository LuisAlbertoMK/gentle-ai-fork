<#
.SYNOPSIS
  Tokenize every SKILL.md in the repo
.DESCRIPTION
  Escanea todos los skills y calcula tokens usando tiktoken (si instalado)
  o heurística chars/3.5 como fallback. Output opcional a CSV.
.PARAMETER Path
  Directorio de skills (default: .agents/skills/).
.PARAMETER OutCsv
  Ruta para exportar resultados a CSV.
#>
#requires -Version 5.1

param(
    [string]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) ".agents\skills"),
    [string]$OutCsv = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $Path)) { Write-Host "[tokenize] Skills dir not found: $Path" -ForegroundColor Red; exit 1 }

$rows = @()
$skills = Get-ChildItem $Path -Directory
foreach ($s in $skills) {
    $md = Join-Path $s.FullName "SKILL.md"
    if (Test-Path $md) {
        $content = Get-Content $md -Raw
        $chars = $content.Length
        $heur = [int]($chars / 3.5)
        $tokens = $null
        try {
            $escaped = $md -replace "'", "''"
            $tokens = & python -c "import tiktoken; e=tiktoken.get_encoding('cl100k_base'); print(len(e.encode(open(r'$escaped',encoding='utf-8').read())))" 2>$null
        } catch { Write-Warning "[tokenize] tiktoken not available for $($s.Name), using heuristic" }
        $rows += [PSCustomObject]@{
            Skill = $s.Name
            Chars = $chars
            TokensHeur = $heur
            TokensReal = if ($tokens) { [int]$tokens } else { -1 }
        }
    }
}
$rows | Sort-Object Chars -Descending | Format-Table Skill, Chars, TokensHeur, TokensReal -AutoSize
$totalChars = ($rows | Measure-Object -Property Chars -Sum).Sum
$totalTokens = ($rows | Where-Object { $_.TokensReal -gt 0 } | Measure-Object -Property TokensReal -Sum).Sum
Write-Host "Skills: $($rows.Count) | Total chars: $totalChars | Total tokens (real): $totalTokens" -ForegroundColor Cyan

if ($OutCsv) {
    $rows | Sort-Object Chars -Descending | Export-Csv $OutCsv -NoTypeInformation
    Write-Host "Output: $OutCsv"
}
