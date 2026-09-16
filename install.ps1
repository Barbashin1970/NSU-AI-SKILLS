#!/usr/bin/env pwsh
# Install the семейства навыков gost-19 for BOTH Claude Code (~/.claude/skills)
# and Codex (~/.agents/skills) on Windows.
#
# Uses directory JUNCTIONS (not copies / not `ln -s`): on Windows, MSYS `ln -s`
# silently makes non-propagating copies, so edits/`git pull` wouldn't show up.
# Junctions are followed natively by both agents and need no admin rights.
# Re-runnable: it SKIPS any skill name that already exists in a target (never clobbers).

$ErrorActionPreference = 'Stop'
$repoSkills = Join-Path $PSScriptRoot 'skills'
if (-not (Test-Path $repoSkills)) { throw "skills/ folder not found next to this script." }

$targets = @(
  (Join-Path $env:USERPROFILE '.claude\skills'),   # Claude Code
  (Join-Path $env:USERPROFILE '.agents\skills')     # Codex
)

foreach ($t in $targets) {
  New-Item -ItemType Directory -Force -Path $t | Out-Null
  Write-Host "`nTarget: $t" -ForegroundColor Cyan
  Get-ChildItem $repoSkills -Directory | ForEach-Object {
    $link = Join-Path $t $_.Name
    if (Test-Path $link) {
      Write-Host "  skip (exists): $($_.Name)" -ForegroundColor Yellow
    } else {
      New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
      Write-Host "  linked: $($_.Name)" -ForegroundColor Green
    }
  }
}

Write-Host "`nDone. Restart Claude Code / Codex to load the skills. Update later with: git pull" -ForegroundColor Cyan
