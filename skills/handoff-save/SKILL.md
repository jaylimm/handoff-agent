---
name: handoff-save
description: "Wrap up the session: draft a fresh handoff note for the current project plus proposed updates to its project facts file, let the user review them, then save. Use when the user runs /handoff-save, or asks to wrap up, hand off, or save progress. To change only part of an existing note or the facts, use /handoff-edit instead."
disable-model-invocation: true
---

# Save a handoff note

Each project has two files outside the repo, found from the current folder by the helper script:

- **Note**: this session's state (rebuilt on every save).
- **Facts**: lasting project knowledge (Decisions, Don't Do, Environment & Commands), kept across saves and changed only with the user's approval.

Run the script from the project's working directory. This form works in PowerShell, cmd, and Git Bash:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill folder>/scripts/handoff.ps1" <command> [options]
```

`<skill folder>` is the folder that contains this SKILL.md (in Claude Code: `${CLAUDE_SKILL_DIR}`). Commands: `info`, `check`, `edit`, `save`, `changes`, `list`, `view`. Add `-Facts` to `edit`, `check`, `save`, `view` to work on the facts file. Exit codes: 0 OK, 1 error, 2 possible secrets (not saved).

## Rules

- **Never write the note or facts file directly.** Only write the draft files, then run `save` / `save -Facts`. The script adds the header, keeps the old version as `.prev.md`, and replaces the file.
- Never put passwords, tokens, keys, or connection strings in either file.
- Bullets, no prose, no filler. Be specific: names, numbers, `path:line`, exact commands. The next session must be able to continue without the user re-explaining anything.
- Note body: aim for under 150 lines (refused above 250). Facts body: aim for under 80 lines (refused above 150).

## Steps

1. Run `info`. Note the **Note**, **Draft**, **Note layout**, **Facts**, and **Facts draft** lines.
   - If the user only wants to add, remove, or fix something in the existing note or facts, stop and point them to `/handoff-edit`.

2. **Write the note draft** to the Draft path. Build it from this conversation. If a note exists, read it first; carry forward only what is still true, drop anything finished, reversed, or replaced. Never copy the old note wholesale. Use exactly these sections; write `- None` if a section is empty:

   ```markdown
   ## Objective & Status
   ## Modified Files & Key Changes
   ## Verified Facts
   ## Active Errors
   ## Tried & Failed
   ## Waiting on You
   ## Next Steps
   ```

   - **Objective & Status:** the goal, status (done / partial / blocked), and exactly where work stopped, including half-finished uncommitted changes.
   - **Modified Files & Key Changes:** `path:line` references with what changed and why. Add a code snippet (10 lines max) only for a signature being changed or code tied to an Active Error.
   - **Verified Facts:** what this session proved, and how (test run, output observed). Not guesses.
   - **Active Errors:** each unresolved error with the **exact message copied verbatim**, where it happens (`path:line`), and the command that reproduces it.
   - **Tried & Failed:** approaches that didn't work and why, so the next session doesn't repeat them.
   - **Waiting on You:** decisions or answers only the user can give.
   - **Next Steps:** numbered; step 1 is the immediate next action. Include exact commands.
   - Decisions, Don't Do rules, and build/test/run commands belong in the facts file (step 3), not in the note.
   - Don't add a title or repo/branch/git lines. The script generates them.
   - **Note layout: LEGACY** → the old note has `Verified Facts & Decisions` and `Don't Do`. Put its still-true verified facts in `Verified Facts`, and propose its decisions and Don't Do rules as facts additions in step 3.

3. **Propose facts changes.** If the Facts line shows a file, read it.
   - **Add:** decisions made in this session (with `Why:` and the date), new Don't Do rules, and build/test/run commands used or discovered. Mark a rule `(temporary)` if it only applies until something happens (for example "don't commit until the API shape is approved").
   - **Remove:** facts this session reversed or finished, including temporary rules whose condition is now met (for example the user allowed coding after a "don't edit code yet" rule).
   - Skip anything already in the facts file. If there is nothing to add or remove, skip to step 4.
   - Otherwise run `edit -Facts` (creates the Facts draft from the saved facts, or an empty template) and apply only the proposed additions and removals to the **Facts draft** path. Don't reword or reorder other facts. Sections: `## Decisions`, `## Don't Do`, `## Environment & Commands`.

4. Run `check` (and `check -Facts` if you wrote a facts draft). Fix any missing sections.

5. **Review with the user.** Show the full note draft, then the facts changes as a list of `+ added` / `- removed` lines, then any `check` warnings (over the soft line limit, possible secrets). Ask: save both, change something, or save without some of the facts changes? Use your ask-user tool if you have one; otherwise ask in chat and stop. Apply changes and show them again until the user approves.
   - **Possible secrets:** list them as `check` printed them (masked) and ask: remove them (recommended) or keep them? Never print the unmasked value.

6. **Save.** If facts changes were approved, run `save -Facts` first, then `save`. If the user rejected all facts changes, delete the Facts draft file instead.
   - If `save` reports problems (missing section, over the limit), fix the draft and save again.
   - If it exits with **POSSIBLE SECRETS** (exit code 2), remove them; run the same save with `-AllowSecrets` only if the user explicitly said to keep them.

7. Report the saved path(s) in one line each, then output a copy-ready summary of the note (about 300 words).
