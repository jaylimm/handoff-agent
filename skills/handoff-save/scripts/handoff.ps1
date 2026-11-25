<#
.SYNOPSIS
    Helper for the handoff-save / handoff-resume skills. Works in Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
    One handoff note per project, stored outside the repo in $env:HANDOFF_DIR (default ~/.copilot/handoffs).
    The note file name is "<folder-name>-<hash of repo root>.md", so two folders with the same name never share a note.

    info     Show the current repo, its note/draft paths and git state. Run this first.
             For a saved note it also reports what changed since the save: commits, rewritten history, and
             whether the working tree (uncommitted + untracked files) still matches the save.
    changes  List the commits and changed files since the note was saved. -Preview adds a short diff
             (capped) for changed files that the note's "Modified Files & Key Changes" section mentions.
    check    Validate the draft (sections, size, possible secrets) without saving anything.
    edit     Copy the saved note body into the draft file so it can be changed.
    save     Validate the draft, add the auto-generated repo header, back up the old note as .prev.md, and replace it.
             A draft with possible secrets is not saved unless -AllowSecrets is given (only after the user confirms).
    list     List every saved note with its repo root and save time.
    view     Print the current project's saved note (read-only). -Note <path> shows a specific note from `list` instead.

    -Facts   With edit, check, save, view: work on the project's facts file (<note>.facts.md) instead of the note.
             The facts file keeps lasting project knowledge (Decisions, Don't Do, Environment & Commands) across saves.
             `edit -Facts` creates an empty template when there is no facts file yet.

    Limits: note body warns above 150 lines and is refused above 250; facts body warns above 80 and is refused above 150.
    Exit codes: 0 = OK, 1 = error / draft not savable, 2 = draft not saved because it may contain secrets.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('info', 'changes', 'check', 'edit', 'save', 'list', 'view')]
    [string]$Command,
    [string]$Folder = (Get-Location).Path,
    [switch]$Facts,
    [int]$WarnLines,
    [int]$MaxLines,
    [switch]$AllowSecrets,
    [switch]$Preview,
    [string]$Note
)

$ErrorActionPreference = 'Stop'
$HandoffDir = if ($env:HANDOFF_DIR) { $env:HANDOFF_DIR } else { Join-Path $HOME '.copilot\handoffs' }
$EndMarker = '<!-- end of auto header -->'
$RequiredSections = @(
    'Objective & Status',
    'Modified Files & Key Changes',
    'Verified Facts',
    'Active Errors',
    'Tried & Failed',
    'Waiting on You',
    'Next Steps'
)
$FactsSections = @('Decisions', "Don't Do", 'Environment & Commands')
if (-not $PSBoundParameters.ContainsKey('WarnLines')) { $WarnLines = if ($Facts) { 80 } else { 150 } }
if (-not $PSBoundParameters.ContainsKey('MaxLines')) { $MaxLines = if ($Facts) { 150 } else { 250 } }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$FormatVersion = 2
$MaxListed = 20
$MaxPreviewLines = 80

# Name, regex (named group 's' = the secret part), and whether the matched text is safe to show unmasked.
$SecretPatterns = @(
    @{ Name = 'GitHub token'; Rx = '\b(?<s>gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,})' },
    @{ Name = 'AWS access key'; Rx = '\b(?<s>AKIA[0-9A-Z]{16})\b' },
    @{ Name = 'Private key'; Rx = '(?<s>-----BEGIN [A-Z ]*PRIVATE KEY-----)'; Show = $true },
    @{ Name = 'Slack token'; Rx = '\b(?<s>xox[abprs]-[A-Za-z0-9-]{10,})' },
    @{ Name = 'API key (sk-...)'; Rx = '\b(?<s>sk-[A-Za-z0-9_-]{20,})' },
    @{ Name = 'JWT'; Rx = '\b(?<s>eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]*)' },
    @{ Name = 'Password in URL'; Rx = '://[^\s/:@]+:(?<s>[^\s@/]+)@' },
    @{ Name = 'Connection-string password'; Rx = '(?i)(?:(?<=;\s*)(?:Password|Pwd)\s*=\s*(?<s>[^;\s''"]+)|\b(?:Password|Pwd)\s*=\s*(?<s>[^;\s''"]+)(?=\s*;))' },
    @{ Name = 'Secret assignment'; Rx = '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\s*[:=]\s*[''"]?(?<s>[^\s''"`]{8,})'; NeedDigit = $true }
)

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

function Test-Git([string]$Dir, [string[]]$GitArgs) {
    $ErrorActionPreference = 'Continue'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    & git -C $Dir @GitArgs 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function ConvertTo-NativeArg([string]$Arg) {
    if ($Arg -and $Arg -notmatch '[\s"]') { return $Arg }
    return '"' + (($Arg -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-GitBytes([string]$Dir, [string[]]$GitArgs) {
    # Raw stdout bytes: PowerShell 5.1 and 7 decode native text differently, so hashing decoded text
    # would make a note saved from one shell look "changed" when checked from the other.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = (@(@('-C', $Dir) + $GitArgs | ForEach-Object { ConvertTo-NativeArg $_ })) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $ms = New-Object IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $null = $errTask.Result
    if ($p.ExitCode -ne 0) { return $null }
    return , $ms.ToArray()
}

function Get-Untracked([string]$Root) {
    $raw = Invoke-GitBytes $Root @('-c', 'core.quotepath=off', 'ls-files', '-z', '--others', '--exclude-standard')
    if (-not $raw) { return @() }
    return @($Utf8.GetString($raw) -split "`0" | Where-Object { $_ })
}

function Get-WorktreeFingerprint([string]$Root) {
    # SHA-256 over HEAD + the full uncommitted diff + untracked file contents. Same value = same files on disk.
    $ms = New-Object IO.MemoryStream
    $add = { param([byte[]]$Bytes) if ($Bytes) { $ms.Write($Bytes, 0, $Bytes.Length) }; $ms.WriteByte(0) }
    $head = Invoke-Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD') | Select-Object -First 1
    & $add $Utf8.GetBytes("head:$head")
    $diffArgs = @('-c', 'core.quotepath=off', 'diff', '--binary', '--no-color', '--no-ext-diff', '--no-textconv')
    if ($head) {
        & $add (Invoke-GitBytes $Root ($diffArgs + 'HEAD'))
    } else {
        & $add (Invoke-GitBytes $Root ($diffArgs + '--cached'))
        & $add (Invoke-GitBytes $Root $diffArgs)
    }
    $fileSha = [Security.Cryptography.SHA256]::Create()
    foreach ($rel in (Get-Untracked $Root | Sort-Object)) {
        $fi = Get-Item -LiteralPath (Join-Path $Root $rel) -Force -ErrorAction SilentlyContinue
        if (-not $fi -or $fi.PSIsContainer) { continue }
        $content = if ($fi.Length -le 5MB) {
            -join ($fileSha.ComputeHash([IO.File]::ReadAllBytes($fi.FullName)) | ForEach-Object { $_.ToString('x2') })
        } else { "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)" }
        & $add $Utf8.GetBytes("untracked:$rel|$content")
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    return -join ($sha.ComputeHash($ms.ToArray()) | ForEach-Object { $_.ToString('x2') })
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

function Get-LineCount([string]$Path) {
    $fi = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $fi -or $fi.PSIsContainer -or $fi.Length -gt 1MB) { return $null }
    $text = [IO.File]::ReadAllText($fi.FullName)
    if ($text.Length -eq 0) { return 0 }
    $n = $text.Split("`n").Count
    if ($text.EndsWith("`n")) { $n-- }
    return $n
}

function Get-NumStat([string]$Root, [string]$Base) {
    # path -> "+a/-r" (or "binary") for tracked changes between $Base and the working tree.
    $map = [ordered]@{}
    foreach ($line in @(Invoke-Git $Root @('-c', 'core.quotepath=off', 'diff', '--numstat', '--no-renames', $Base))) {
        $parts = "$line" -split "`t"
        if ($parts.Count -lt 3) { continue }
        $map[$parts[2]] = if ($parts[0] -eq '-') { 'binary' } else { "+$($parts[0])/-$($parts[1])" }
    }
    return $map
}

function Get-GitState([string]$Root) {
    $state = [ordered]@{ IsGit = $false; Remote = '(none)'; Branch = '(not a git repo)'; Head = ''; HeadSha = $null; Changes = @() }
    if ((Invoke-Git $Root @('rev-parse', '--is-inside-work-tree')) -ne 'true') { return $state }
    $state.IsGit = $true
    $remote = Invoke-Git $Root @('remote', 'get-url', 'origin')
    if ($remote) { $state.Remote = $remote }
    $branch = Invoke-Git $Root @('branch', '--show-current')
    $state.Branch = if ($branch) { $branch } else { '(detached HEAD)' }
    $head = Invoke-Git $Root @('log', '-1', '--format=%h %s')
    $state.Head = if ($head) { $head } else { '(no commits yet)' }
    $state.HeadSha = Invoke-Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD') | Select-Object -First 1
    $changes = Invoke-Git $Root @('-c', 'core.quotepath=off', 'status', '--short')
    if ($changes) { $state.Changes = @($changes) }
    return $state
}

function Format-Change([string]$Root, [string]$StatusLine, $NumStat) {
    # " M src/a.ts" -> "`M src/a.ts` (+3/-1)";  "?? new.ts" -> "`?? new.ts` (new, 41 lines)"
    $code = $StatusLine.Substring(0, [Math]::Min(2, $StatusLine.Length))
    $path = if ($StatusLine.Length -gt 3) { $StatusLine.Substring(3) } else { '' }
    if ($path -match ' -> (.+)$') { $path = $Matches[1] }
    $path = $path.Trim('"')
    $extra = ''
    if ($code -eq '??') {
        $full = Join-Path $Root $path
        if (Test-Path -LiteralPath $full -PathType Container) { $extra = ' (new folder)' }
        else {
            $n = Get-LineCount $full
            $extra = if ($null -ne $n) { " (new, $n lines)" } else { ' (new)' }
        }
    } elseif ($NumStat -and $NumStat.Contains($path)) {
        $extra = " ($($NumStat[$path]))"
    }
    return "- ``$($StatusLine.Trim())``$extra"
}

function Read-Note([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, $Utf8)
    $root = if ($text -match '<!-- handoff-root: (.+?) -->') { $Matches[1] } else { $null }
    $format = if ($text -match '<!-- handoff-format: (\d+) -->') { [int]$Matches[1] } else { 1 }
    $headSha = if ($text -match '<!-- handoff-head: ([0-9a-f]{7,64}) -->') { $Matches[1] } else { $null }
    $worktree = if ($text -match '<!-- handoff-worktree: ([0-9a-f]{64}) -->') { $Matches[1] } else { $null }
    $saved = if ($text -match '\*\*Saved:\*\* ([^|\r\n]+)') { $Matches[1].Trim() } else { $null }
    $branch = if ($text -match '\*\*Branch:\*\* ([^@\r\n]+)') { $Matches[1].Trim() } else { $null }
    # Format 1 notes only have the short hash in the Branch line: "**Branch:** main @ 1a2b3c4 subject".
    $shortHead = if ($text -match '\*\*Branch:\*\* [^@\r\n]+@ ([0-9a-f]{7,40})\b') { $Matches[1] } else { $null }
    $idx = $text.IndexOf($EndMarker)
    $body = if ($idx -ge 0) { $text.Substring($idx + $EndMarker.Length).Trim() } else { $text.Trim() }
    return [pscustomobject]@{
        Text = $text; Root = $root; Format = $format; HeadRef = $(if ($headSha) { $headSha } else { $shortHead })
        Worktree = $worktree; Saved = $saved; Branch = $branch; Body = $body
    }
}

function Get-SinceSave([string]$Root, $NoteInfo) {
    $r = [ordered]@{ Ref = $NoteInfo.HeadRef; Sha = $null; Head = $null; Ancestor = $false; Ahead = 0; WorktreeSaved = $NoteInfo.Worktree; WorktreeNow = $null }
    $r.Head = Invoke-Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD') | Select-Object -First 1
    if ($r.Ref) { $r.Sha = Invoke-Git $Root @('rev-parse', '--verify', '--quiet', "$($r.Ref)^{commit}") | Select-Object -First 1 }
    if ($r.Sha -and $r.Head) {
        $r.Ancestor = Test-Git $Root @('merge-base', '--is-ancestor', $r.Sha, $r.Head)
        $count = Invoke-Git $Root @('rev-list', '--count', "$($r.Sha)..$($r.Head)") | Select-Object -First 1
        if ($count) { $r.Ahead = [int]$count }
    }
    if ($r.WorktreeSaved) { $r.WorktreeNow = Get-WorktreeFingerprint $Root }
    return [pscustomobject]$r
}

function Get-DraftBody([string]$Path) {
    $body = [IO.File]::ReadAllText($Path, $Utf8).Trim()
    # Drop any title or auto header the model copied in; the script writes its own.
    $idx = $body.IndexOf($EndMarker)
    if ($idx -ge 0) { $body = $body.Substring($idx + $EndMarker.Length).Trim() }
    return ($body -replace '^(#\s[^\r\n]*\r?\n)+', '').Trim()
}

function Find-Secrets([string]$Text) {
    $hits = @()
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $taken = @()
        foreach ($p in $SecretPatterns) {
            foreach ($m in [regex]::Matches($lines[$i], $p.Rx)) {
                $s = $m.Groups['s']
                if ($s.Value -match '^(\$|<|\{|%|\*{3}|process\.env|env[.:])' -or $s.Value -match '(?i)^(x+|\*+|changeme|redacted|placeholder|password)$') { continue }
                if ($p.NeedDigit -and $s.Value -notmatch '\d') { continue }
                if ($taken | Where-Object { $s.Index -lt $_[1] -and $_[0] -lt ($s.Index + $s.Length) }) { continue }
                $taken += , @($s.Index, ($s.Index + $s.Length))
                $keep = [Math]::Min(4, [Math]::Floor($s.Length / 4))
                $shown = if ($p.Show) { $s.Value } else { $s.Value.Substring(0, $keep) + '***' }
                $prefix = $m.Value.Substring(0, $s.Index - $m.Index)
                $hits += [pscustomobject]@{ Line = $i + 1; Name = $p.Name; Masked = "$prefix$shown" }
            }
        }
    }
    return $hits
}

function Test-LegacyBody([string]$Body) {
    # Notes saved before the facts file existed have "Verified Facts & Decisions" / "Don't Do" and no "Active Errors".
    return ($Body -notmatch '(?m)^##\s+Active Errors\s*$')
}

function Get-FactsCount([string]$Body) {
    return @($Body -split "`n" | Where-Object { $_ -match '^\s*-\s+\S' -and $_ -notmatch '^\s*-\s+None\s*$' }).Count
}

function Test-Draft([string]$Path) {
    $body = Get-DraftBody $Path
    $problems = @()
    foreach ($s in $Sections) {
        if ($body -notmatch ('(?m)^##\s+' + [regex]::Escape($s) + '\s*$')) { $problems += "missing section '## $s'" }
    }
    $lines = ($body -split "`n").Count
    if ($lines -gt $MaxLines) { $problems += "body is $lines lines (limit $MaxLines) - shorten it" }
    return [pscustomobject]@{ Body = $body; Lines = $lines; Problems = $problems; Secrets = @(Find-Secrets $body) }
}

function Format-Secrets($Secrets) {
    foreach ($h in $Secrets) { " - line $($h.Line): $($h.Name)  $($h.Masked)" }
}

$root = Get-RepoRoot $Folder
$notePath = Get-NotePath $root
$noteDraftPath = $notePath -replace '\.md$', '.draft.md'
$factsPath = $notePath -replace '\.md$', '.facts.md'
$factsDraftPath = $notePath -replace '\.md$', '.facts.draft.md'
# edit / check / save / view work on the note by default, or on the facts file with -Facts.
$targetPath = if ($Facts) { $factsPath } else { $notePath }
$draftPath = if ($Facts) { $factsDraftPath } else { $noteDraftPath }
$prevPath = $targetPath -replace '\.md$', '.prev.md'
$Sections = if ($Facts) { $FactsSections } else { $RequiredSections }
$kind = if ($Facts) { 'facts file' } else { 'note' }

switch ($Command) {
    'info' {
        New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
        $git = Get-GitState $root
        "Repo root:    $root"
        "Remote:       $($git.Remote)"
        "Branch now:   $($git.Branch)$(if ($git.Head) { " @ $($git.Head)" })"
        "Uncommitted:  $($git.Changes.Count) file(s)"
        "Note:         $notePath"
        "Draft:        $noteDraftPath"
        if (Test-Path -LiteralPath $notePath) {
            $noteInfo = Read-Note $notePath
            $lines = ($noteInfo.Text -split "`n").Count
            "Note exists:  yes (saved $($noteInfo.Saved), $lines lines)"
            if (Test-LegacyBody $noteInfo.Body) {
                "Note layout:  LEGACY (no '## Active Errors'; has Decisions/Don't Do in the note). The next /handoff-save migrates it."
            }
            if (-not $noteInfo.Root) {
                "Repo match:   UNKNOWN - note has no handoff-root marker"
            } elseif ([string]::Equals($noteInfo.Root, $root, [StringComparison]::OrdinalIgnoreCase)) {
                "Repo match:   yes"
            } else {
                "Repo match:   NO - note belongs to $($noteInfo.Root)"
            }
            if ($noteInfo.Branch -and $git.IsGit -and $noteInfo.Branch -ne $git.Branch) {
                "Branch note:  note was saved on '$($noteInfo.Branch)', current branch is '$($git.Branch)'"
            }
            if ($git.IsGit -and $noteInfo.Root -and [string]::Equals($noteInfo.Root, $root, [StringComparison]::OrdinalIgnoreCase)) {
                $since = Get-SinceSave $root $noteInfo
                if (-not $since.Ref) {
                    "Saved at:     UNKNOWN - note has no commit reference"
                } else {
                    $shown = if ($since.Sha) { $since.Sha.Substring(0, 12) } else { $since.Ref }
                    "Saved at:     $shown (saved $($noteInfo.Saved), format $($noteInfo.Format))"
                    if (-not $since.Sha) {
                        "Since save:   UNKNOWN"
                        "History:      UNKNOWN - saved commit $($since.Ref) not found in this repo"
                    } elseif ($since.Sha -eq $since.Head) {
                        "Since save:   HEAD unchanged"
                        "History:      OK"
                    } else {
                        "Since save:   $($since.Ahead) commit(s) since save"
                        if ($since.Ancestor) { "History:      OK" }
                        else { "History:      REWRITTEN - saved commit is not an ancestor of HEAD (rebase, amend, reset or force-push)" }
                    }
                }
                if (-not $since.WorktreeSaved) {
                    "Worktree:     UNKNOWN - note was saved by an older version (no fingerprint)"
                } elseif ($since.WorktreeNow -eq $since.WorktreeSaved) {
                    "Worktree:     unchanged since save"
                } else {
                    "Worktree:     changed since save (run ``changes`` for details)"
                }
            }
        } else {
            "Note exists:  no"
        }
        if (Test-Path -LiteralPath $noteDraftPath) { "Draft exists: yes (unsaved draft from an earlier wrap-up)" }
        if (Test-Path -LiteralPath $factsPath) {
            $factsInfo = Read-Note $factsPath
            $match = if (-not $factsInfo.Root -or [string]::Equals($factsInfo.Root, $root, [StringComparison]::OrdinalIgnoreCase)) { '' } else { " - NO repo match, belongs to $($factsInfo.Root)" }
            "Facts:        $factsPath ($(Get-FactsCount $factsInfo.Body) entries, updated $($factsInfo.Saved))$match"
        } else {
            "Facts:        none yet ($factsPath)"
        }
        "Facts draft:  $factsDraftPath"
        if (Test-Path -LiteralPath $factsDraftPath) { "Facts draft exists: yes (unsaved facts draft from an earlier wrap-up)" }
    }

    'edit' {
        New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
        if ($Facts -and -not (Test-Path -LiteralPath $factsPath)) {
            $template = ($FactsSections | ForEach-Object { "## $_`n- None" }) -join "`n"
            [IO.File]::WriteAllText($draftPath, $template + "`n", $Utf8)
            "No facts file yet. Empty facts draft created: $draftPath"
            break
        }
        if (-not (Test-Path -LiteralPath $targetPath)) { Stop-WithError "No saved $kind for $root ($targetPath)." }
        $body = (Read-Note $targetPath).Body
        if (-not $Facts -and (Test-LegacyBody $body)) {
            Stop-WithError "Legacy note layout (no '## Active Errors'). Run /handoff-save once to migrate it, then edit."
        }
        [IO.File]::WriteAllText($draftPath, $body + "`n", $Utf8)
        "Draft created from saved ${kind}: $draftPath"
    }

    'changes' {
        if (-not (Test-Path -LiteralPath $notePath)) { Stop-WithError "No saved note for $root ($notePath)." }
        $noteInfo = Read-Note $notePath
        if (-not ($noteInfo.Root -and [string]::Equals($noteInfo.Root, $root, [StringComparison]::OrdinalIgnoreCase))) {
            Stop-WithError "The note belongs to $($noteInfo.Root), not $root."
        }
        if (-not (Test-Git $root @('rev-parse', '--is-inside-work-tree'))) { Stop-WithError "$root is not a git repo." }
        $since = Get-SinceSave $root $noteInfo
        if (-not $since.Head) { Stop-WithError "No commits yet in $root." }

        if ($since.Sha) {
            $base = $since.Sha
            $hist = if ($since.Sha -eq $since.Head -or $since.Ancestor) { 'OK' } else { 'REWRITTEN (diff is against the saved commit, which is no longer in the branch history)' }
            "Base:     $($base.Substring(0, 12)) (note saved $($noteInfo.Saved)); History: $hist"
        } else {
            $base = $since.Head
            "Base:     HEAD - saved commit $(if ($since.Ref) { $since.Ref } else { '(none)' }) not found; showing uncommitted changes only"
        }

        $log = if ($base -ne $since.Head) { @(Invoke-Git $root @('log', '--oneline', '--no-decorate', "$base..HEAD")) } else { @() }
        if ($log.Count -eq 0) { "Commits since save: none" } else {
            "Commits since save ($($log.Count)):"
            $log | Select-Object -First $MaxListed | ForEach-Object { "  - $_" }
            if ($log.Count -gt $MaxListed) { "  ...and $($log.Count - $MaxListed) more" }
        }

        $num = Get-NumStat $root $base
        $untracked = @(Get-Untracked $root)
        $total = $num.Count + $untracked.Count
        if ($total -eq 0) { "Files changed since save: none" } else {
            "Files changed since save ($total):"
            $rows = @($num.Keys | ForEach-Object { "  - $_ ($($num[$_]))" }) + @($untracked | ForEach-Object { "  - $_ (untracked)" })
            $rows | Select-Object -First $MaxListed
            if ($rows.Count -gt $MaxListed) { "  ...and $($rows.Count - $MaxListed) more" }
        }

        if ($Preview) {
            $section = if ($noteInfo.Body -match '(?ms)^##\s+Modified Files & Key Changes\s*$(.*?)(?=^##\s|\z)') { $Matches[1] } else { '' }
            $mentioned = @([regex]::Matches($section, '[\w.-]+(?:[/\\][\w.-]+)*\.[A-Za-z0-9]+') |
                ForEach-Object { $_.Value -replace '\\', '/' } | Select-Object -Unique)
            $isMentioned = { param($p) foreach ($m in $mentioned) { if ($p -ieq $m -or $p.EndsWith("/$m", [StringComparison]::OrdinalIgnoreCase)) { return $true } }; return $false }
            $hitTracked = @($num.Keys | Where-Object { & $isMentioned $_ })
            $hitUntracked = @($untracked | Where-Object { & $isMentioned $_ })
            '---'
            if (-not ($hitTracked + $hitUntracked)) {
                "Preview: none of the changed files are listed under '## Modified Files & Key Changes'."
            } else {
                "Preview of changed files the note mentions (max $MaxPreviewLines lines):"
                if ($hitTracked) {
                    $diff = @(Invoke-Git $root (@('-c', 'core.quotepath=off', 'diff', '-U3', '--no-color', '--no-ext-diff', $base, '--') + $hitTracked))
                    $diff | Select-Object -First $MaxPreviewLines
                    if ($diff.Count -gt $MaxPreviewLines) { "...truncated ($($diff.Count - $MaxPreviewLines) more lines); open the file for the rest" }
                }
                foreach ($u in $hitUntracked) { "- $u is untracked (new file); open it to read it" }
            }
        }
    }

    'check' {
        if (-not (Test-Path -LiteralPath $draftPath)) { Stop-WithError "Draft not found: $draftPath. Write the $kind body there first." }
        $d = Test-Draft $draftPath
        "Draft:    $draftPath ($kind)"
        "Lines:    $($d.Lines) body lines (warn above $WarnLines, limit $MaxLines)"
        $missing = @($d.Problems | Where-Object { $_ -like 'missing section*' })
        "Sections: $(if ($missing) { $missing -join '; ' } else { 'OK' })"
        if ($d.Secrets.Count -eq 0) { "Secrets:  none found" } else {
            "Secrets:  POSSIBLE SECRETS ($($d.Secrets.Count)) - ask the user to remove them or confirm they are safe:"
            Format-Secrets $d.Secrets
        }
        $warn = $d.Secrets.Count -gt 0 -or $d.Lines -gt $WarnLines
        if ($d.Problems) {
            "Result:   NOT SAVABLE - $($d.Problems -join '; ')"
            exit 1
        }
        "Result:   $(if ($warn) { 'OK with warnings' } else { 'OK' })"
    }

    'save' {
        if (-not (Test-Path -LiteralPath $draftPath)) { Stop-WithError "Draft not found: $draftPath. Write the $kind body there first." }
        $d = Test-Draft $draftPath
        $body = $d.Body
        if ($d.Problems) {
            $msg = "draft not saved:`n - " + ($d.Problems -join "`n - ")
            if ($d.Secrets) { $msg += "`nAlso found possible secrets:`n" + ((Format-Secrets $d.Secrets) -join "`n") }
            Stop-WithError $msg
        }
        if ($d.Secrets -and -not $AllowSecrets) {
            "POSSIBLE SECRETS (not saved):"
            Format-Secrets $d.Secrets
            "Remove them from the draft and save again. Only if the user confirms they are safe, run save with -AllowSecrets."
            exit 2
        }

        $git = Get-GitState $root
        if ($Facts) {
            $header = @(
                "# Project facts: $(Split-Path $root -Leaf)",
                "<!-- handoff-root: $root -->",
                "<!-- handoff-format: $FormatVersion -->",
                '',
                "- **Saved:** $(Get-Date -Format 'yyyy-MM-dd HH:mm (zzz)') | **Root:** ``$root``",
                '',
                $EndMarker,
                ''
            )
        } else {
        $num = if ($git.HeadSha) { Get-NumStat $root 'HEAD' } else { $null }
        $changeLines = if ($git.Changes.Count -eq 0) { @('- (none)') } else {
            $shown = @($git.Changes | Select-Object -First 25 | ForEach-Object { Format-Change $root $_ $num })
            if ($git.Changes.Count -gt 25) { $shown += "- ...and $($git.Changes.Count - 25) more" }
            $shown
        }
        $markers = @("<!-- handoff-format: $FormatVersion -->")
        if ($git.IsGit) {
            if ($git.HeadSha) { $markers += "<!-- handoff-head: $($git.HeadSha) -->" }
            $markers += "<!-- handoff-worktree: $(Get-WorktreeFingerprint $root) -->"
        }
        $header = @(
            "# Handoff: $(Split-Path $root -Leaf)",
            "<!-- handoff-root: $root -->"
        ) + $markers + @(
            '',
            "- **Saved:** $(Get-Date -Format 'yyyy-MM-dd HH:mm (zzz)') | **Root:** ``$root``",
            "- **Branch:** $($git.Branch) @ $($git.Head) | **Remote:** $($git.Remote)",
            "- **Uncommitted at save ($($git.Changes.Count)):**"
        ) + $changeLines + @('', $EndMarker, '')
        }

        New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
        $tmp = "$targetPath.tmp"
        [IO.File]::WriteAllText($tmp, (($header -join "`n") + $body + "`n"), $Utf8)
        if (Test-Path -LiteralPath $targetPath) { Copy-Item -LiteralPath $targetPath -Destination $prevPath -Force }
        Move-Item -LiteralPath $tmp -Destination $targetPath -Force
        Remove-Item -LiteralPath $draftPath -Force
        "Saved:    $targetPath ($($d.Lines) body lines, $kind)"
        if (Test-Path -LiteralPath $prevPath) { "Previous: $prevPath" }
        if ($d.Lines -gt $WarnLines) { "WARNING:  body is $($d.Lines) lines (soft limit $WarnLines). Consider trimming it with /handoff-edit." }
        if ($d.Secrets) { "Note:     saved with $($d.Secrets.Count) possible secret(s) the user confirmed as safe." }
    }

    'view' {
        $target = if ($Note) {
            $full = [IO.Path]::GetFullPath($Note)
            $dir = [IO.Path]::GetFullPath($HandoffDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) -or $full -notmatch '\.md$') {
                Stop-WithError "Not a handoff note: $full (notes live in $HandoffDir)."
            }
            $full
        } else { $targetPath }
        if (-not (Test-Path -LiteralPath $target)) { Stop-WithError "No saved $kind found: $target" }
        $item = Get-Item -LiteralPath $target
        "File:     $($item.FullName)"
        "Modified: $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
        '---'
        [IO.File]::ReadAllText($item.FullName, $Utf8).TrimEnd()
    }

    'list' {
        if (-not (Test-Path -LiteralPath $HandoffDir)) { "No handoff notes yet ($HandoffDir)."; break }
        $notes = Get-ChildItem -LiteralPath $HandoffDir -Filter '*.md' |
            Where-Object { $_.Name -notmatch '\.(prev|draft|facts)\.md$' } |
            Sort-Object LastWriteTime -Descending
        if (-not $notes) { "No handoff notes yet ($HandoffDir)."; break }
        foreach ($n in $notes) {
            $noteInfo = Read-Note $n.FullName
            $here = if ($noteInfo.Root -and [string]::Equals($noteInfo.Root, $root, [StringComparison]::OrdinalIgnoreCase)) { ' <- current repo' } else { '' }
            $hasFacts = if (Test-Path -LiteralPath ($n.FullName -replace '\.md$', '.facts.md')) { ' +facts' } else { '' }
            "$($noteInfo.Saved)  $($noteInfo.Root)$hasFacts$here"
            "    $($n.FullName)"
        }
    }
}
