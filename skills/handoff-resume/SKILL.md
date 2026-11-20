---
name: handoff-resume
description: "Resume work from the current project's saved handoff note. Use when the user runs /handoff-resume or asks to resume, pick up, or continue from the last handoff."
disable-model-invocation: true
---

# Resume from a handoff note

The helper script lives in the sibling `handoff-save` skill:

```powershell
& "<this skill's folder>\..\handoff-save\scripts\handoff.ps1" <command>
```

Run it from the project's working directory (or pass `-Folder <path>`).

## Steps

1. Run `info`.
   - **Note exists: no** → tell the user there is no note for this repo (show the path). Run `list` in case the folder was moved or renamed, show the result, and ask what to work on. Stop.
   - **Repo match: NO or UNKNOWN** → don't load it. Tell the user which repo the note belongs to and stop.
   - **Draft exists: yes** → mention there is an unsaved draft from an earlier wrap-up; don't treat it as the note.
2. Read the file at the **Note** path. Read only this note, not other handoff files or `.prev.md` backups (unless the user asks).
   - If the user pasted a summary in this message and it conflicts with the note, the one with the newer timestamp wins.
3. **Check the note against the repo.** The disk is the truth, not the summary.
   - Compare the note's branch and "Uncommitted at save" list with `info` (branch now, uncommitted count). Run `git status --short` if counts differ.
   - Skim the files listed under **Modified Files & Key Changes** that matter for the next step. Mention anything that no longer matches the note.
4. Reply briefly:
   - Objective and status in 1–2 lines.
   - **Waiting on You** items first, as questions.
   - The immediate next step, and any **Don't Do** rules you'll follow.
   - Differences found in step 3, if any.
5. Ask whether to continue with the next step or change priorities. Don't start changing code until the user confirms.
