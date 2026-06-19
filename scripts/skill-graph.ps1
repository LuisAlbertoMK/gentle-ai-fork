#requires -Version 5.1

<#
.SYNOPSIS
  Skill dependency graph — sparse loading resolver.
  Given task keywords, returns the minimal skill set needed (matched + 1-hop dependencies).

.DESCRIPTION
  Builds a dependency graph of all 54 gentleman-agent skills with:
  - Triggers (keywords that activate each skill)
  - Categories (compression, quality, memory, meta, code-ops, SDD, web-quality)
  - Dependencies (skills that must be loaded together)
  - Cross-references (related skills)

  Resolution: task keywords to BFS match to expand 1-hop to return skill set.

.PARAMETER Task
  Task description or keywords to resolve skills for.

.PARAMETER Expand
  How many hops of dependencies to include (default: 1, max: 3).

.PARAMETER ListAll
  List all skills with their categories and dependencies (no resolution).

.PARAMETER Format
  Output format: Text (default), Json, or Csv.

.EXAMPLE
  .\scripts\skill-graph.ps1 -Task "security audit, fix vulnerabilities"
  .\scripts\skill-graph.ps1 -Task "code review, commit" -Expand 2
  .\scripts\skill-graph.ps1 -ListAll
  .\scripts\skill-graph.ps1 -Task "performance" -Format Json
#>

param(
    [string]$Task = "",
    [ValidateRange(0,3)]
    [int]$Expand = 1,
    [switch]$ListAll,
    [ValidateSet("Text","Json","Csv")]
    [string]$Format = "Text"
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

# ============================================================
# SKILL REGISTRY — 60 skills with triggers, categories, deps
# ============================================================

$skillRegistry = @()

function Add-Skill {
    param(
        [string]$Name,
        [string[]]$Triggers,
        [string]$Category = "general",
        [string[]]$DependsOn = @(),
        [string[]]$Related = @(),
        [string]$Description = ""
    )
    $script:skillRegistry += [PSCustomObject]@{
        Name        = $Name
        Triggers    = $Triggers
        Category    = $Category
        DependsOn   = $DependsOn
        Related     = $Related
        Description = $Description
    }
}

# --- Compression / Style ---
Add-Skill -Name "karpathy-prompt" -Category "compression" -Triggers @("karpathy","less tokens","context compression","compact prompt") -Description "Apply Karpathy-style compression to prompts"
Add-Skill -Name "karpathy-loop" -Category "compression" -Triggers @("karpathy loop","optimize prompt","measure tokens","self-improve prompt") -Description "Karpathy-style self-improvement loop for prompts"
Add-Skill -Name "lean-context" -Category "compression" -Triggers @("compact","less tokens","caveman","caveman","ultra-lean","minimal context") -Description "Ultra-lean context mode"
Add-Skill -Name "execution-mode" -Category "compression" -Triggers @("execution mode","quick","thorough","draft","modo") -Description "Quick or Thorough or Draft execution modes"
Add-Skill -Name "skill-digestion" -Category "compression" -Triggers @("skill digestion","compact on load","compress skill") -Description "Digest and compact skills when loaded"

# --- Quality ---
Add-Skill -Name "quality-gate" -Category "quality" -Triggers @("quality gate","pre-commit","validate commit") -Description "Pre-commit quality gate with 5 checks" -Related @("auto-metrics","commit-crafter")
Add-Skill -Name "auto-metrics" -Category "quality" -Triggers @("auto-score","metrics","post-task","evaluate","self-evaluate") -Description "Post-task self-evaluation with 7-dim scoring" -DependsOn @("skill-validate")
Add-Skill -Name "immune-system" -Category "quality" -Triggers @("immune system","anti-pattern","permanent immunity","nunca mas","bug","fix","error") -Description "Permanent immunity catalog for repeated errors"
Add-Skill -Name "code-review-agent" -Category "quality" -Triggers @("code review","CR","revisar codigo","review code") -Description "Automated code review with standards" -DependsOn @("best-practices")
Add-Skill -Name "skill-testing" -Category "quality" -Triggers @("test skill","verify skill","coverage","skill test") -Description "Test and verify skill coverage"
Add-Skill -Name "skill-validate" -Category "quality" -Triggers @("skill validation","benchmark","multi-trial","validate skill","3 trials") -Description "3-trial benchmark validation for skills"
Add-Skill -Name "judgment-day" -Category "quality" -Triggers @("judgment day","dual review","juzgar","evaluar skill") -Description "Dual review and judgment for skills"

# --- Memory ---
Add-Skill -Name "session-resume" -Category "memory" -Triggers @("resume","donde lo dejamos","continua","session start","git state") -Description "Safe session resume with git state gate" -DependsOn @("dreaming")
Add-Skill -Name "code-memory" -Category "memory" -Triggers @("code memory","memory","recordar","acordate","multi-session") -Description "Cross-session code memory and recall" -Related @("session-resume","dreaming")
Add-Skill -Name "dreaming" -Category "memory" -Triggers @("dreaming","cross-session","pattern extraction","memory curation","engram") -Description "Cross-session pattern extraction via Engram" -DependsOn @("auto-metrics")
Add-Skill -Name "bitacora" -Category "memory" -Triggers @("bitacora","historial","historico","request log") -Description "Session activity log and history tracking"
Add-Skill -Name "metricas" -Category "memory" -Triggers @("metricas","before or after","percent improvement","delta") -Description "Before or after metrics tracking for improvements"
Add-Skill -Name "decision-capture" -Category "memory" -Triggers @("decision","trade-off","decision log") -Description "Capture and log architectural decisions"

# --- Skills Meta ---
Add-Skill -Name "skill-creator" -Category "meta" -Triggers @("create skill","new skill","crear skill") -Description "Create new AI skills from requirements"
Add-Skill -Name "skill-registry" -Category "meta" -Triggers @("skill registry","catalog","registro skills") -Description "Skill registry management and catalog"
Add-Skill -Name "skill-improver" -Category "meta" -Triggers @("skill improvement","audit skills","refactor skills") -Description "Audit and improve existing skills"
Add-Skill -Name "skill-refresher" -Category "meta" -Triggers @("skill refresher","drift detection","auto-heal") -Description "Detect and fix skill drift"
Add-Skill -Name "gap-analysis" -Category "meta" -Triggers @("gap analysis","system audit","identificar gaps","project intake") -Description "Complete 8-dim gap analysis for any system" -Related @("project-mapper","security-scanner")

# --- Code Ops ---
Add-Skill -Name "commit-crafter" -Category "code-ops" -Triggers @("commit","commit message","conventional commit") -Description "Craft conventional commit messages from diff" -Related @("quality-gate")
Add-Skill -Name "refactoring-planner" -Category "code-ops" -Triggers @("refactor","refactoring","reestructurar","migrate") -Description "Plan and execute code refactoring"
Add-Skill -Name "project-mapper" -Category "code-ops" -Triggers @("mapear","project map","estructura","tech stack") -Description "Map project structure, stack, and architecture" -Related @("gap-analysis")
Add-Skill -Name "security-scanner" -Category "code-ops" -Triggers @("security","seguridad","vulnerabilidad","auditar") -Description "Security audit and vulnerability scanner" -DependsOn @("best-practices")
Add-Skill -Name "performance-tracker" -Category "code-ops" -Triggers @("performance score","mobile perf","desktop perf","rendimiento","app score","benchmark") -Description "Score and track app performance across 6 dimensions"

# --- SDD ---
Add-Skill -Name "sdd-init" -Category "SDD" -Triggers @("SDD init","bootstrap","iniciar SDD") -Description "Initialize SDD project context and config"
Add-Skill -Name "sdd-explore" -Category "SDD" -Triggers @("explore codebase","pre-design","investigar","codebase exploration") -Description "Explore codebase before designing changes"
Add-Skill -Name "sdd-propose" -Category "SDD" -Triggers @("proposal","intent","approach","change proposal") -Description "Create formal change proposals" -DependsOn @("sdd-explore")
Add-Skill -Name "sdd-spec" -Category "SDD" -Triggers @("specs","specification","Given When Then","requisitos","spec") -Description "Write detailed specifications from proposals" -DependsOn @("sdd-propose")
Add-Skill -Name "sdd-design" -Category "SDD" -Triggers @("technical design","HOW","diseno tecnico") -Description "Create technical design from specs" -DependsOn @("sdd-spec")
Add-Skill -Name "sdd-tasks" -Category "SDD" -Triggers @("task breakdown","implementation plan","tareas","task list") -Description "Break down designs into implementation tasks" -DependsOn @("sdd-design")
Add-Skill -Name "sdd-apply" -Category "SDD" -Triggers @("apply tasks","implement","aplicar") -Description "Apply SDD tasks to implement changes" -DependsOn @("sdd-tasks") -Related @("commit-crafter")
Add-Skill -Name "sdd-verify" -Category "SDD" -Triggers @("validate vs specs","verify","verificar") -Description "Validate implementation against specs" -DependsOn @("sdd-spec")
Add-Skill -Name "sdd-archive" -Category "SDD" -Triggers @("archive changes","delta to main","archivar") -Description "Archive completed changes with lineage" -DependsOn @("sdd-verify","sdd-apply")
Add-Skill -Name "sdd-onboard" -Category "SDD" -Triggers @("SDD onboard","onboarding","nuevo proyecto SDD","guia SDD") -Description "Guide users through complete SDD cycle"

# --- Coordination ---
Add-Skill -Name "delivery-harness" -Category "coordination" -Triggers @("coordinate","orchestrate","multi-agent","delegate work") -Description "Orchestrate multi-agent work delivery" -DependsOn @("subagent-isolation","work-unit-commits") -Related @("chained-pr")
Add-Skill -Name "chained-pr" -Category "coordination" -Triggers @("stacked PR","chained PR","sequential branches","PR chain") -Description "Manage stacked sequential PRs (refs: chaining-details.md)" -DependsOn @("work-unit-commits") -Related @("delivery-harness","branch-pr")
Add-Skill -Name "branch-pr" -Category "coordination" -Triggers @("branch PR","branch naming","create PR","open pull request") -Description "Branch creation and PR workflow for gentle-ai" -Related @("chained-pr","issue-creation")
Add-Skill -Name "issue-creation" -Category "coordination" -Triggers @("create issue","GitHub issue","bug report","feature request") -Description "GitHub issue creation with issue-first workflow for gentle-ai" -Related @("branch-pr")
Add-Skill -Name "subagent-isolation" -Category "coordination" -Triggers @("subagent isolation","context boundaries","delegation") -Description "Isolate subagent contexts and prevent contamination"
Add-Skill -Name "command-wrapper" -Category "coordination" -Triggers @("command wrapper","safe execution","error handling","output parse") -Description "Safe command execution with error handling"

# --- Web Quality ---
Add-Skill -Name "accessibility" -Category "web-quality" -Triggers @("accessibility","a11y","WCAG","screen reader","keyboard nav","make accessible") -Description "Audit and improve web accessibility"
Add-Skill -Name "performance" -Category "web-quality" -Triggers @("web performance","speed up","reduce load time","page speed","performance audit") -Description "Optimize web performance for faster loading"
Add-Skill -Name "seo" -Category "web-quality" -Triggers @("SEO","search engine","meta tags","structured data","sitemap") -Description "Optimize for search engine visibility"
Add-Skill -Name "core-web-vitals" -Category "web-quality" -Triggers @("Core Web Vitals","LCP","INP","CLS","layout shift","page experience") -Description "Optimize Core Web Vitals metrics"
Add-Skill -Name "best-practices" -Category "web-quality" -Triggers @("best practices","security audit","modernize code","code quality review") -Description "Apply modern web development best practices"
Add-Skill -Name "web-quality-audit" -Category "web-quality" -Triggers @("web quality audit","lighthouse audit","review web quality") -Description "Comprehensive web quality audit" -DependsOn @("accessibility","performance","seo","core-web-vitals","best-practices")
Add-Skill -Name "development-mode" -Category "web-quality" -Triggers @("performance mode","dev mode","modo desarrollo","high performance","modo rendimiento") -Description "System resource prioritization mode"

# --- Research ---
Add-Skill -Name "research" -Category "research" -Triggers @("research","investigar","technical investigation","learn","compare solutions","evaluate") -Description "Structured research workflow for technical investigations"

# --- General / Specialized ---
Add-Skill -Name "recovery-protocol" -Category "specialized" -Triggers @("recovery","no es eso","frustration","stuck","bloqueado","bug","fix","error") -Description "Recovery protocol for frustration and errors"
Add-Skill -Name "context-watchdog" -Category "specialized" -Triggers @("context overflow","token limit","context explosion") -Description "Monitor and prevent context window overflow"
Add-Skill -Name "ci-cd" -Category "specialized" -Triggers @("CI/CD","pipeline","GitHub Actions","continuous integration") -Description "CI/CD pipeline automation"
Add-Skill -Name "work-unit-commits" -Category "specialized" -Triggers @("work-unit","commit organization") -Description "Organize commits into logical work units"
Add-Skill -Name "self-reflection" -Category "specialized" -Triggers @("self-reflection","Hermes","error patterns","reflexion") -Description "Hermes closed learning loop"
Add-Skill -Name "cognitive-doc-design" -Category "specialized" -Triggers @("doc design","documentation patterns","cognitive load","progressive disclosure") -Description "Design docs that reduce cognitive load"
Add-Skill -Name "comment-writer" -Category "specialized" -Triggers @("comment writer","PR feedback","review comment","write feedback") -Description "Write warm, direct collaboration comments"
Add-Skill -Name "senior-engineer" -Category "specialized" -Triggers @("senior architect","trade-offs","system design","arquitectura") -Description "Senior engineer persona for architecture decisions"
Add-Skill -Name "prompt-engineering" -Category "specialized" -Triggers @("improve prompt","ReAct","multi-agent","prompt engineering") -Description "Advanced prompt engineering techniques"
Add-Skill -Name "go-testing" -Category "specialized" -Triggers @("Go tests","Bubbletea TUI","golang test") -Description "Go testing patterns and tools"
Add-Skill -Name "python-async" -Category "specialized" -Triggers @("Python async","asyncio") -Description "Python async/await patterns"

# ============================================================
# GRAPH FUNCTIONS
# ============================================================

function New-Graph {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param()
    $g = @{ Nodes = @{}; AdjList = @{} }
    foreach ($s in $script:skillRegistry) {
        $name = $s.Name
        $g.Nodes[$name] = $s
        $g.AdjList[$name] = @{ to = @{}; from = @{} }
    }
    foreach ($s in $script:skillRegistry) {
        foreach ($dep in $s.DependsOn) {
            if ($g.AdjList.ContainsKey($dep)) {
                $g.AdjList[$dep].to[$s.Name] = "depends_on"
                $g.AdjList[$s.Name].from[$dep] = "depended_by"
            }
        }
    }
    foreach ($s in $script:skillRegistry) {
        foreach ($rel in $s.Related) {
            if ($g.AdjList.ContainsKey($rel)) {
                $g.AdjList[$rel].to[$s.Name] = "related"
                $g.AdjList[$s.Name].from[$rel] = "related"
            }
        }
    }
    return $g
}

function Resolve-Skill {
    param(
        [hashtable]$Graph,
        [string]$Task,
        [int]$MaxHops = 1
    )
    $taskLower = $Task.ToLower()
    $matched = @{}
    $usedTriggers = @{}

    # Phase 1: match by trigger keywords
    foreach ($s in $script:skillRegistry) {
        foreach ($trigger in $s.Triggers) {
            $triggerWords = $trigger.ToLower() -split '\s+|,|/'
            $matchedAny = $false
            foreach ($word in $triggerWords) {
                if ($word.Length -lt 3) { continue }
                if ($taskLower -match [regex]::Escape($word)) {
                    $matched[$s.Name] = $true
                    if (-not $usedTriggers.ContainsKey($s.Name)) {
                        $usedTriggers[$s.Name] = @()
                    }
                    $usedTriggers[$s.Name] += $trigger
                    $matchedAny = $true
                    break
                }
            }
            if ($matchedAny) { break }
        }
    }

    # Phase 2: BFS expand dependencies
    $expanded = @{}
    foreach ($name in $matched.Keys) {
        $expanded[$name] = $true
        Expand-Hop -Graph $Graph -Start $name -Hops $MaxHops -Visited $expanded
    }

    # Phase 3: build result
    $result = @()
    foreach ($name in $expanded.Keys) {
        $s = $Graph.Nodes[$name]
        if ($s) {
            $result += [PSCustomObject]@{
                Name       = $s.Name
                Category   = $s.Category
                Matched    = $matched.ContainsKey($name)
                Triggers   = if ($matched.ContainsKey($name)) { $usedTriggers[$name] -join "; " } else { "" }
                DependsOn  = $s.DependsOn -join "; "
                Related    = $s.Related -join "; "
                Description = $s.Description
            }
        }
    }

    $result = $result | Sort-Object -Property @{E={-$_.Matched}}, Category, Name
    return $result
}

function Expand-Hop {
    param($Graph, $Start, $Hops, $Visited)
    if ($Hops -le 0) { return }
    $current = $Graph.AdjList[$Start]
    if (-not $current) { return }
    foreach ($neighbor in $current.to.Keys) {
        if (-not $Visited[$neighbor]) {
            $Visited[$neighbor] = $true
            Expand-Hop -Graph $Graph -Start $neighbor -Hops ($Hops - 1) -Visited $Visited
        }
    }
    foreach ($neighbor in $current.from.Keys) {
        if (-not $Visited[$neighbor]) {
            $Visited[$neighbor] = $true
            Expand-Hop -Graph $Graph -Start $neighbor -Hops ($Hops - 1) -Visited $Visited
        }
    }
}

# ============================================================
# OUTPUT
# ============================================================

$graph = New-Graph
$resolved = $null

if ($ListAll) {
    $groups = $script:skillRegistry | Group-Object Category
    switch ($Format) {
        "Json" { try { $groups | ForEach-Object {
                $g = $_
                @{ Category = $g.Name; Skills = $g.Group | Sort-Object Name | ForEach-Object {
                    @{ Name = $_.Name; DependsOn = $_.DependsOn; Related = $_.Related }
                }}
            } | ConvertTo-Json -Depth 3; } catch { Write-Host "Error generating JSON: $_" -ForegroundColor Red; exit 1 }
        }
        "Csv" {
            $flat = foreach ($g in $groups) {
                foreach ($s in $g.Group | Sort-Object Name) {
                    [PSCustomObject]@{
                        Category   = $g.Name
                        Skill      = $s.Name
                        DependsOn  = if ($s.DependsOn.Count -gt 0) { $s.DependsOn -join "; " } else { "" }
                        Related    = if ($s.Related.Count -gt 0) { $s.Related -join "; " } else { "" }
                    }
                }
            }
            $flat | ConvertTo-Csv -NoTypeInformation
        }
        "Text" {
            foreach ($g in $groups) {
                Write-Host ("`n[" + $g.Name.ToUpper() + "]  (" + $g.Count + " skills)") -ForegroundColor Green
                $g.Group | Sort-Object Name | ForEach-Object {
                    $deps = if ($_.DependsOn.Count -gt 0) { "  deps: " + ($_.DependsOn -join ", ") } else { "" }
                    Write-Host ("  " + $_.Name.PadRight(22) + $deps) -ForegroundColor White
                }
            }
            Write-Host ("`nTotal: " + $script:skillRegistry.Count + " skills in " + $groups.Count + " categories") -ForegroundColor Cyan
        }
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Task)) {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host ("  .\scripts\skill-graph.ps1 -Task ""<task description>"" [-Expand N] [-Format Json|Csv]") -ForegroundColor Cyan
    Write-Host ("  .\scripts\skill-graph.ps1 -ListAll [-Format Json|Csv]") -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("Registry: " + $script:skillRegistry.Count + " skills") -ForegroundColor Green
    exit 0
}

$resolved = Resolve-Skill -Graph $graph -Task $Task -MaxHops $Expand

if ($null -eq $resolved) {
    Write-Host "Resolution error for task: '$Task'" -ForegroundColor Red
    exit 1
}

if ($resolved.Count -eq 0) {
    Write-Host "No skills matched task: '$Task'" -ForegroundColor Yellow
    Write-Host "Try broader keywords or check: .\scripts\skill-graph.ps1 -ListAll" -ForegroundColor Cyan
    exit 0
}

$matchedCount = ($resolved | Where-Object { $_.Matched }).Count
$expandedCount = ($resolved | Where-Object { -not $_.Matched }).Count

switch ($Format) {
    "Json" {
        try {
            $resolved | ConvertTo-Json -Depth 2
        } catch {
            Write-Host "Error converting results to JSON: $_" -ForegroundColor Red
            exit 1
        }
    }
    "Csv" {
        $resolved | ConvertTo-Csv -NoTypeInformation
    }
    "Text" {
        Write-Host "=== Skill Resolution ===" -ForegroundColor Cyan
        Write-Host ("Task: " + $Task) -ForegroundColor White
        Write-Host ("Matched: " + $matchedCount + " | Expanded (1-hop): " + $expandedCount + " | Total: " + $resolved.Count) -ForegroundColor Green
        Write-Host ""

        $matched = $resolved | Where-Object { $_.Matched }
        $expanded = $resolved | Where-Object { -not $_.Matched }

        if ($matched) {
            Write-Host "--- MATCHED SKILLS (load these) ---" -ForegroundColor Green
            $matched | Format-Table @{N="Skill";E={$_.Name}}, @{N="Category";E={$_.Category}}, @{N="Match";E={$_.Triggers}} -AutoSize -Wrap
        }
        if ($expanded) {
            Write-Host "--- DEPENDENCIES (load with matched) ---" -ForegroundColor Yellow
            $expanded | Format-Table @{N="Skill";E={$_.Name}}, @{N="Category";E={$_.Category}}, @{N="Reason";E={$_.DependsOn}} -AutoSize -Wrap
        }

        Write-Host ""
        Write-Host "Load commands:" -ForegroundColor Cyan
        $resolved | Where-Object { $_.Matched } | ForEach-Object {
            Write-Host ("  skill_use @(""" + $_.Name + """)") -ForegroundColor White
        }
        if ($expanded) {
            Write-Host "  # Also load dependencies:" -ForegroundColor DarkYellow
            $expanded | ForEach-Object {
                Write-Host ("  skill_use @(""" + $_.Name + """)") -ForegroundColor DarkYellow
            }
        }
    }
}
