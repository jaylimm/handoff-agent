---
name: handoff-save
description: "Wrap up the session: draft a fresh handoff note for the current project, let the user review it, then save it. Also edits an existing note. Use when the user runs /handoff-save, or asks to wrap up, hand off, save progress, or add/remove something in the handoff note."
disable-model-invocation: true
---

# Save a handoff note

Each project has its own note, outside the repo. The helper script finds it from the current folder:

```powershell
& "<this skill's folder>\scripts\handoff.ps1" <command>
```

Run it from the project's working directory (or pass `-Folder <path>`). Commands: `info`, `edit`, `save`, `list`.

## Rules

- **Never write the note file directly.** Only write the draft file, then run `save`. The script adds the repo header, backs up the old note as `.prev.md`, and replaces it.
- Never put passwords, tokens, keys, or connection strings in the note.
- Keep it short: bullets, no prose, body limit 80 lines. Facts must be specific (names, numbers, paths, commands).

## Steps

1. Run `info`. Note the **Note**, **Draft**, and **Note exists** lines.
2. **Choose the mode:**
   - **Edit mode:** the user asks to add, remove, or fix something in the existing note (for example `/handoff-save edit: remove the prune decision`). Run `edit`, change only what was asked in the draft file, then go to step 4.
   - **New handoff (default):** go to step 3.
3. **Write the draft** to the Draft path. Build it from this conversation. If a note already exists, read it first. Carry forward only facts and decisions that are still true. Drop anything finished, reversed, or replaced in this session. Never copy the old note wholesale. Use exactly these sections; write `- None` if a section is empty:

   ```markdown
   ## Objective & Status
   ## Modified Files & Key Changes
   ## Verified Facts & Decisions
   ## Tried & Failed
   ## Waiting on You
   ## Next Steps
   ## Don't Do
   ```

   - **Tried & Failed:** approaches that didn't work and why, so the next session doesn't repeat them.
   - **Waiting on You:** decisions or answers only the user can give.
   - **Don't Do:** constraints the next session must respect (for example "DB is read-only", "don't commit until approved").
   - Don't add a title or repo/branch/git lines. The script generates them.
4. **Review with the user.** Show the full draft in chat and ask: save it, or what to change? Use your ask-user tool if you have one; otherwise ask in chat and stop. Apply requested changes to the draft and show it again until the user approves.
5. Run `save`. If it reports problems (missing section, too long), fix the draft and run `save` again.
6. Report the saved path in one line, then output a copy-ready summary of the note (about 300 words).
