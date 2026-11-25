---
name: handoff-resume
description: "Resume work from the current project's saved handoff note and project facts. Use when the user runs /handoff-resume or asks to resume, pick up, or continue from the last handoff."
disable-model-invocation: true
---

# Resume from a handoff note

The helper script lives in the sibling `handoff-save` skill. Run it from the project's working directory. This form works in PowerShell, cmd, and Git Bash:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill folder>/../handoff-save/scripts/handoff.ps1" <command> [options]
```

`<skill folder>` is the folder that contains this SKILL.md (in Claude Code: `${CLAUDE_SKILL_DIR}`).

## Steps

1. Run `info`.
   - **Note exists: no** → tell the user there is no note for this repo (show the path). Run `list` in case the folder was moved or renamed, show the result, and ask what to work on. Stop.
   - **Repo match: NO or UNKNOWN** → don't load it. Tell the user which repo the note belongs to and stop.
   - **Draft exists: yes** or **Facts draft exists: yes** → mention there is an unsaved draft from an earlier wrap-up; don't treat it as the note or facts.

2. Read the file at the **Note** path, and the file at the **Facts** path if it exists. Read nothing else from the handoff folder (no `.prev.md` backups, no other projects) unless the user asks.
   - If the user pasted a summary in this message and it conflicts with the note, the one with the newer timestamp wins.

3. **Check the note against the repo**, using the `info` lines:
   - **Since save: HEAD unchanged** and **Worktree: unchanged since save** → the files on disk are exactly as they were when the note was written, including the uncommitted work listed in its header. Trust the note; don't reopen source files just to verify it. Say "Repo unchanged since the handoff."
   - Otherwise (commits since save, **Worktree: changed**, or **UNKNOWN**) → run `changes`. If any changed file is listed in the note's **Modified Files & Key Changes**, run `changes -Preview`. Report only the differences that matter for the next step. Open a source file only if the next step needs it.
   - **History: REWRITTEN** → warn that commit references in the note may be stale (rebase, amend, reset, or force-push since the save).
   - **Branch note** → mention the branch difference.
   - **Note layout: LEGACY** → the note still has `Don't Do` and decisions inside it; follow them, and mention that the next `/handoff-save` moves them to the facts file.

4. Reply briefly:
   - Objective and status in 1–2 lines.
   - **Waiting on You** items first, as questions.
   - **Active Errors**, with the exact message and where.
   - The immediate next step.
   - **Every** Don't Do rule from the facts file (and from a legacy note), as the rules you'll follow.
   - Only the decisions and commands from the facts file that matter for the next step, not the whole file.
   - Differences found in step 3, if any.

5. Ask whether to continue with the next step or change priorities. Don't start changing code until the user confirms.
