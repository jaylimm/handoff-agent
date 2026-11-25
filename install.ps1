<#
.SYNOPSIS
    Installs the handoff skills (and the @Handoff agent where supported) for VS Code Copilot, Copilot CLI, Codex,
    Claude Code and Antigravity. Works in Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
    Copies the skills into one folder per group of tools, only for tools found on this PC. Run it again after `git pull`.

      %USERPROFILE%\.agents\skills\handoff-*          VS Code Copilot, Copilot CLI, Codex (all three read this folder)
      %USERPROFILE%\.claude\skills\handoff-*          Claude Code
      %USERPROFILE%\.gemini\config\skills\handoff-*   Antigravity
      %APPDATA%\Code\User\prompts\handoff.agent.md    @Handoff agent for VS Code
      %USERPROFILE%\.gemini\config\agents\handoff.md  Handoff agent for Antigravity

    Older versions installed into %USERPROFILE%\.copilot\skills. VS Code and Copilot CLI read that folder too, so those
    copies are removed to avoid every command appearing twice.

    Only the handoff-* skill folders and the handoff agent files are created, replaced, or removed. Saved notes are never touched.

.PARAMETER Uninstall
    Remove the handoff skills and agents from every location above. Saved notes are kept.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$home_ = $env:USERPROFILE
$skills = @(Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory | Where-Object Name -like 'handoff-*')
if (-not $skills) { throw "No handoff-* skills found in $repo\skills." }

function Test-Tool([string[]]$Paths, [string[]]$Commands) {
    foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } }
    foreach ($c in $Commands) { if (Get-Command $c -ErrorAction SilentlyContinue) { return $true } }
    return $false
}

$tools = [ordered]@{
    'VS Code'     = Test-Tool @((Join-Path $env:APPDATA 'Code')) @()
    'Copilot CLI' = Test-Tool @() @('copilot')
    'Codex'       = Test-Tool @((Join-Path $home_ '.codex')) @('codex')
    'Claude Code' = Test-Tool @((Join-Path $home_ '.claude')) @('claude')
    'Antigravity' = Test-Tool @((Join-Path $home_ '.gemini')) @()
}

$skillTargets = @(
    [pscustomobject]@{ Dir = Join-Path $home_ '.agents\skills'; Tools = @('VS Code', 'Copilot CLI', 'Codex') },
    [pscustomobject]@{ Dir = Join-Path $home_ '.claude\skills'; Tools = @('Claude Code') },
    [pscustomobject]@{ Dir = Join-Path $home_ '.gemini\config\skills'; Tools = @('Antigravity') }
)
$agentTargets = @(
    [pscustomobject]@{ Tool = 'VS Code'; Source = Join-Path $repo 'com.github.copilot\agents\handoff.agent.md'; Path = Join-Path $env:APPDATA 'Code\User\prompts\handoff.agent.md' },
    [pscustomobject]@{ Tool = 'Antigravity'; Source = Join-Path $repo 'agents\handoff.md'; Path = Join-Path $home_ '.gemini\config\agents\handoff.md' }
)
$legacySkillsDir = Join-Path $home_ '.copilot\skills'

function Remove-Installed([string]$Path) {
    # GetAttributes still works on a broken junction, where Test-Path returns false.
    try { $attr = [IO.File]::GetAttributes($Path) } catch { return $false }
    if ($attr -band [IO.FileAttributes]::ReparsePoint) {
        # A manually created link: delete only the link, never what it points to.
        if ($attr -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($Path) } else { [IO.File]::Delete($Path) }
    } elseif ($attr -band [IO.FileAttributes]::Directory) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    } else {
        Remove-Item -LiteralPath $Path -Force
    }
    return $true
}

function Remove-Skills([string]$Dir) {
    $n = 0
    foreach ($s in $skills) { if (Remove-Installed (Join-Path $Dir $s.Name)) { $n++ } }
    return $n
}

Write-Host 'Tools found:'
foreach ($k in $tools.Keys) { Write-Host ("  {0,-12} {1}" -f $k, $(if ($tools[$k]) { 'yes' } else { 'no' })) }
Write-Host ''

# Old installs (<= 0.1) used ~/.copilot/skills; remove them in both modes.
$legacy = Remove-Skills $legacySkillsDir
if ($legacy) { Write-Host "Removed $legacy old handoff skill folder(s) from $legacySkillsDir$(if (-not $Uninstall) { ' (now installed in ~\.agents\skills instead, to avoid duplicates)' })." }

$done = 0
foreach ($t in $skillTargets) {
    $using = @($t.Tools | Where-Object { $tools[$_] })
    if ($Uninstall) {
        $n = Remove-Skills $t.Dir
        if ($n) { Write-Host "Removed $n skill folder(s) from $($t.Dir)"; $done++ }
        continue
    }
    if (-not $using) {
        Write-Host "Skipped $($t.Dir) ($($t.Tools -join ', ') not found)"
        continue
    }
    New-Item -ItemType Directory -Force -Path $t.Dir | Out-Null
    foreach ($s in $skills) {
        $dest = Join-Path $t.Dir $s.Name
        $null = Remove-Installed $dest
        Copy-Item -LiteralPath $s.FullName -Destination $dest -Recurse
        # Files from a downloaded zip carry a "blocked" mark that stops PowerShell from running them.
        Get-ChildItem -LiteralPath $dest -Recurse -Filter '*.ps1' | Unblock-File
    }
    Write-Host "Installed $($skills.Count) skills to $($t.Dir)  [for $($using -join ', ')]"
    $done++
}

foreach ($a in $agentTargets) {
    if ($Uninstall) {
        if (Remove-Installed $a.Path) { Write-Host "Removed agent $($a.Path)"; $done++ }
        continue
    }
    if (-not $tools[$a.Tool]) { continue }
    New-Item -ItemType Directory -Force -Path (Split-Path $a.Path) | Out-Null
    $null = Remove-Installed $a.Path
    Copy-Item -LiteralPath $a.Source -Destination $a.Path
    Write-Host "Installed agent $($a.Path)  [for $($a.Tool)]"
}

if (-not $Uninstall) {
    foreach ($dir in @($skillTargets.Dir) + $legacySkillsDir) {
        foreach ($old in 'wrap-up', 'resume-handoff') {
            if (Test-Path -LiteralPath (Join-Path $dir $old)) {
                Write-Warning "Old skill '$old' found in $dir. Delete it if it's an earlier version of this project, or it may trigger instead of handoff-save/handoff-resume."
            }
        }
    }
}

Write-Host ''
if ($Uninstall) {
    Write-Host "Done. Handoff skills and agents removed. Saved notes are kept."
} elseif ($done -eq 0) {
    Write-Warning 'Nothing was installed: none of VS Code, Copilot CLI, Codex, Claude Code or Antigravity was found.'
} else {
    if ((Get-ExecutionPolicy) -in 'Restricted', 'AllSigned') {
        Write-Host "Note: PowerShell's execution policy is '$(Get-ExecutionPolicy)'. The skills run the helper with -ExecutionPolicy Bypass, which works unless a machine policy (GPO) blocks it."
    }
    Write-Host 'Done. Restart each tool, open a project, and type /handoff in a new chat (Codex: $handoff).'
}
