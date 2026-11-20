<#
.SYNOPSIS
    Helper for the handoff-save / handoff-resume skills. Works in Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
    One handoff note per project, stored outside the repo in $env:HANDOFF_DIR (default ~/.copilot/handoffs).
    The note file name is "<folder-name>-<hash of repo root>.md", so two folders with the same name never share a note.

    info   Show the current repo, its note/draft paths and git state. Run this first.
    edit   Copy the saved note body into the draft file so it can be changed.
    save   Validate the draft, add the auto-generated repo header, back up the old note as .prev.md, and replace it.
    list   List every saved note with its repo root and save time.
    view   Print the current project's saved note (read-only). -Previous shows the .prev.md backup;
           -Note <path> shows a specific note from `list` instead.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('info', 'edit', 'save', 'list', 'view')]
    [string]$Command,
    [string]$Folder = (Get-Location).Path,
    [int]$MaxLines = 80,
    [switch]$Previous,
    [string]$Note
)

$ErrorActionPreference = 'Stop'
$HandoffDir = if ($env:HANDOFF_DIR) { $env:HANDOFF_DIR } else { Join-Path $HOME '.copilot\handoffs' }
$EndMarker = '<!-- end of auto header -->'
$RequiredSections = @(
    'Objective & Status',
    'Modified Files & Key Changes',
    'Verified Facts & Decisions',
    'Tried & Failed',
    'Waiting on You',
    'Next Steps',
    "Don't Do"
)
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Stop-WithError([string]$Message) {
    Write-Output "ERROR: $Message"
    exit 1
}

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    # Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $out = & git -C $Dir @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $out
}

function Get-RepoRoot([string]$Dir) {
    $root = Invoke-Git $Dir @('rev-parse', '--show-toplevel')
    if (-not $root) { $root = $Dir }
    return [IO.Path]::GetFullPath(($root | Select-Object -First 1)).TrimEnd('\', '/')
}

function Get-NotePath([string]$Root) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash($Utf8.GetBytes($Root.ToLowerInvariant()))
    $hash = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
    $name = (Split-Path $Root -Leaf) -replace '[^\w.-]', '_'
    return Join-Path $HandoffDir "$name-$hash.md"
}

function Get-GitState([string]$Root) {
    $state = [ordered]@{ IsGit = $false; Remote = '(none)'; Branch = '(not a git repo)'; Head = ''; Changes = @() }
    if ((Invoke-Git $Root @('rev-parse', '--is-inside-work-tree')) -ne 'true') { return $state }
    $state.IsGit = $true
    $remote = Invoke-Git $Root @('remote', 'get-url', 'origin')
    if ($remote) { $state.Remote = $remote }
    $branch = Invoke-Git $Root @('branch', '--show-current')
    $state.Branch = if ($branch) { $branch } else { '(detached HEAD)' }
    $head = Invoke-Git $Root @('log', '-1', '--format=%h %s')
    $state.Head = if ($head) { $head } else { '(no commits yet)' }
    $changes = Invoke-Git $Root @('status', '--short')
    if ($changes) { $state.Changes = @($changes) }
    return $state
}

function Read-Note([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, $Utf8)
    $root = if ($text -match '<!-- handoff-root: (.+?) -->') { $Matches[1] } else { $null }
    $saved = if ($text -match '\*\*Saved:\*\* ([^|\r\n]+)') { $Matches[1].Trim() } else { $null }
    $branch = if ($text -match '\*\*Branch:\*\* ([^@\r\n]+)') { $Matches[1].Trim() } else { $null }
    $idx = $text.IndexOf($EndMarker)
    $body = if ($idx -ge 0) { $text.Substring($idx + $EndMarker.Length).Trim() } else { $text.Trim() }
    return [pscustomobject]@{ Text = $text; Root = $root; Saved = $saved; Branch = $branch; Body = $body }
}

$root = Get-RepoRoot $Folder
$notePath = Get-NotePath $root
$draftPath = $notePath -replace '\.md$', '.draft.md'
$prevPath = $notePath -replace '\.md$', '.prev.md'

switch ($Command) {
    'info' {
        New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
        $git = Get-GitState $root
        "Repo root:    $root"
        "Remote:       $($git.Remote)"
        "Branch now:   $($git.Branch)$(if ($git.Head) { " @ $($git.Head)" })"
        "Uncommitted:  $($git.Changes.Count) file(s)"
        "Note:         $notePath"
        "Draft:        $draftPath"
        if (Test-Path -LiteralPath $notePath) {
            $note = Read-Note $notePath
            $lines = ($note.Text -split "`n").Count
            "Note exists:  yes (saved $($note.Saved), $lines lines)"
            if (-not $note.Root) {
                "Repo match:   UNKNOWN - note has no handoff-root marker"
            } elseif ([string]::Equals($note.Root, $root, [StringComparison]::OrdinalIgnoreCase)) {
                "Repo match:   yes"
            } else {
                "Repo match:   NO - note belongs to $($note.Root)"
            }
            if ($note.Branch -and $git.IsGit -and $note.Branch -ne $git.Branch) {
                "Branch note:  note was saved on '$($note.Branch)', current branch is '$($git.Branch)'"
            }
        } else {
            "Note exists:  no"
        }
        if (Test-Path -LiteralPath $draftPath) { "Draft exists: yes (unsaved draft from an earlier wrap-up)" }
    }

    'edit' {
        if (-not (Test-Path -LiteralPath $notePath)) { Stop-WithError "No saved note for $root ($notePath)." }
        [IO.File]::WriteAllText($draftPath, (Read-Note $notePath).Body + "`n", $Utf8)
        "Draft created from saved note: $draftPath"
    }

    'save' {
        if (-not (Test-Path -LiteralPath $draftPath)) { Stop-WithError "Draft not found: $draftPath. Write the note body there first." }
        $body = [IO.File]::ReadAllText($draftPath, $Utf8).Trim()
        # Drop any title or auto header the model copied in; the script writes its own.
        $idx = $body.IndexOf($EndMarker)
        if ($idx -ge 0) { $body = $body.Substring($idx + $EndMarker.Length).Trim() }
        $body = ($body -replace '^(#\s[^\r\n]*\r?\n)+', '').Trim()

        $problems = @()
        foreach ($s in $RequiredSections) {
            if ($body -notmatch ('(?m)^##\s+' + [regex]::Escape($s) + '\s*$')) { $problems += "missing section '## $s'" }
        }
        $bodyLines = ($body -split "`n").Count
        if ($bodyLines -gt $MaxLines) { $problems += "body is $bodyLines lines (limit $MaxLines) - shorten it" }
        if ($problems) { Stop-WithError ("draft not saved:`n - " + ($problems -join "`n - ")) }

        $git = Get-GitState $root
        $changeLines = if ($git.Changes.Count -eq 0) { @('- (none)') } else {
            $shown = @($git.Changes | Select-Object -First 25 | ForEach-Object { "- ``$($_.Trim())``" })
            if ($git.Changes.Count -gt 25) { $shown += "- ...and $($git.Changes.Count - 25) more" }
            $shown
        }
        $header = @(
            "# Handoff: $(Split-Path $root -Leaf)",
            "<!-- handoff-root: $root -->",
            '',
            "- **Saved:** $(Get-Date -Format 'yyyy-MM-dd HH:mm (zzz)') | **Root:** ``$root``",
            "- **Branch:** $($git.Branch) @ $($git.Head) | **Remote:** $($git.Remote)",
            "- **Uncommitted at save ($($git.Changes.Count)):**"
        ) + $changeLines + @('', $EndMarker, '')

        New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
        $tmp = "$notePath.tmp"
        [IO.File]::WriteAllText($tmp, (($header -join "`n") + $body + "`n"), $Utf8)
        if (Test-Path -LiteralPath $notePath) { Copy-Item -LiteralPath $notePath -Destination $prevPath -Force }
        Move-Item -LiteralPath $tmp -Destination $notePath -Force
        Remove-Item -LiteralPath $draftPath -Force
        "Saved:    $notePath ($bodyLines body lines)"
        if (Test-Path -LiteralPath $prevPath) { "Previous: $prevPath" }
    }

    'view' {
        $target = if ($Note) {
            $full = [IO.Path]::GetFullPath($Note)
            $dir = [IO.Path]::GetFullPath($HandoffDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) -or $full -notmatch '\.md$') {
                Stop-WithError "Not a handoff note: $full (notes live in $HandoffDir)."
            }
            $full
        } else { $notePath }
        if ($Previous) { $target = $target -replace '(\.prev)?\.md$', '.prev.md' }
        if (-not (Test-Path -LiteralPath $target)) {
            $what = if ($Previous) { 'No previous version' } else { 'No saved note' }
            Stop-WithError "$what found: $target"
        }
        $item = Get-Item -LiteralPath $target
        "File:     $($item.FullName)"
        "Modified: $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
        '---'
        [IO.File]::ReadAllText($item.FullName, $Utf8).TrimEnd()
    }

    'list' {
        if (-not (Test-Path -LiteralPath $HandoffDir)) { "No handoff notes yet ($HandoffDir)."; break }
        $notes = Get-ChildItem -LiteralPath $HandoffDir -Filter '*.md' |
            Where-Object { $_.Name -notmatch '\.(prev|draft)\.md$' } |
            Sort-Object LastWriteTime -Descending
        if (-not $notes) { "No handoff notes yet ($HandoffDir)."; break }
        foreach ($n in $notes) {
            $note = Read-Note $n.FullName
            $here = if ($note.Root -and [string]::Equals($note.Root, $root, [StringComparison]::OrdinalIgnoreCase)) { ' <- current repo' } else { '' }
            "$($note.Saved)  $($note.Root)$here"
            "    $($n.FullName)"
        }
    }
}
