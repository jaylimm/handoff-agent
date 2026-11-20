<#
.SYNOPSIS
    Installs the handoff skills and agent for Antigravity and VS Code. Works in Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
    Copies the skills and agent into the user folders of each editor found on this PC. Run it again after `git pull` to update.

      Antigravity  skills -> %USERPROFILE%\.gemini\config\skills\handoff-*
                   agent  -> %USERPROFILE%\.gemini\config\agents\handoff.md
      VS Code      skills -> %USERPROFILE%\.copilot\skills\handoff-*
                   agent  -> %APPDATA%\Code\User\prompts\handoff.agent.md

    Only the handoff-* skill folders and the handoff agent files are created, replaced, or removed.

.PARAMETER Uninstall
    Remove the handoff skills and agent. Saved notes are kept.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$skills = @(Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory | Where-Object Name -like 'handoff-*')
if (-not $skills) { throw "No handoff-* skills found in $repo\skills." }

$targets = @(
    [pscustomobject]@{
        Name        = 'Antigravity'
        AppDir      = Join-Path $env:USERPROFILE '.gemini'
        SkillsDir   = Join-Path $env:USERPROFILE '.gemini\config\skills'
        AgentSource = Join-Path $repo 'agents\handoff.md'
        AgentPath   = Join-Path $env:USERPROFILE '.gemini\config\agents\handoff.md'
    },
    [pscustomobject]@{
        Name        = 'VS Code'
        AppDir      = Join-Path $env:APPDATA 'Code'
        SkillsDir   = Join-Path $env:USERPROFILE '.copilot\skills'
        AgentSource = Join-Path $repo 'com.github.copilot\agents\handoff.agent.md'
        AgentPath   = Join-Path $env:APPDATA 'Code\User\prompts\handoff.agent.md'
    }
)

function Remove-Installed([string]$Path) {
    # GetAttributes still works on a broken junction, where Test-Path returns false.
    try { $attr = [IO.File]::GetAttributes($Path) } catch { return }
    if ($attr -band [IO.FileAttributes]::ReparsePoint) {
        # A manually created link: delete only the link, never what it points to.
        if ($attr -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($Path) } else { [IO.File]::Delete($Path) }
    } elseif ($attr -band [IO.FileAttributes]::Directory) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    } else {
        Remove-Item -LiteralPath $Path -Force
    }
}

$done = 0
foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.AppDir)) {
        Write-Host "$($t.Name): not found, skipped. (If it is installed, open it once and run this again.)"
        continue
    }

    if ($Uninstall) {
        foreach ($s in $skills) { Remove-Installed (Join-Path $t.SkillsDir $s.Name) }
        Remove-Installed $t.AgentPath
        Write-Host "$($t.Name): removed handoff skills and agent."
        $done++
        continue
    }

    New-Item -ItemType Directory -Force -Path $t.SkillsDir, (Split-Path $t.AgentPath) | Out-Null
    foreach ($s in $skills) {
        $dest = Join-Path $t.SkillsDir $s.Name
        Remove-Installed $dest
        Copy-Item -LiteralPath $s.FullName -Destination $dest -Recurse
        # Files from a downloaded zip carry a "blocked" mark that stops PowerShell from running them.
        Get-ChildItem -LiteralPath $dest -Recurse -Filter '*.ps1' | Unblock-File
    }
    Remove-Installed $t.AgentPath
    Copy-Item -LiteralPath $t.AgentSource -Destination $t.AgentPath
    Write-Host "$($t.Name): installed $($skills.Count) skills to $($t.SkillsDir)"

    foreach ($old in 'wrap-up', 'resume-handoff') {
        if (Test-Path -LiteralPath (Join-Path $t.SkillsDir $old)) {
            Write-Warning "Old skill '$old' found in $($t.SkillsDir). Delete it if it's an earlier version of this project, or it may trigger instead of handoff-save/handoff-resume."
        }
    }
    $done++
}

if ($done -eq 0) {
    Write-Warning 'Nothing was changed: neither Antigravity nor VS Code was found.'
} elseif (-not $Uninstall) {
    if ((Get-ExecutionPolicy) -in 'Restricted', 'AllSigned') {
        Write-Warning "PowerShell's execution policy is '$(Get-ExecutionPolicy)', which blocks the helper script the skills run. Fix it with: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    }
    Write-Host 'Done. Restart the editor, open a project, and type /handoff in a new chat.'
}
