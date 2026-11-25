---
name: handoff-edit
description: "Change only part of the current project's saved handoff note or project facts (add, remove, or fix items), let the user review it, then save it. Use when the user runs /handoff-edit, for example `/handoff-edit remove the prune decision`, or asks to add/remove/fix something in the handoff note or facts."
disable-model-invocation: true
---

# Edit a handoff note or the project facts

Changes only what the user asks for; everything else stays as it is. To rebuild the whole note from this chat, use `/handoff-save` instead.

The helper script lives in the sibling `handoff-save` skill. Run it from the project's working directory. This form works in PowerShell, cmd, and Git Bash:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill folder>/../handoff-save/scripts/handoff.ps1" <command> [options]
```

`<skill folder>` is the folder that contains this SKILL.md (in Claude Code: `${CLAUDE_SKILL_DIR}`).

## Which file

- **Facts file** (add `-Facts` to `edit`, `check`, `save`): decisions, Don't Do rules (including `(temporary)` ones), and build/test/run commands. Sections: `## Decisions`, `## Don't Do`, `## Environment & Commands`.
- **Note** (no `-Facts`): everything about the current session: status, modified files, verified facts, active errors, tried & failed, waiting on you, next steps.
- If it's unclear which one the user means, ask.

## Rules

- **Never write the note or facts file directly.** Only change the draft file, then run `save` (or `save -Facts`).
- Change only what was asked. Don't reword, reorder, or "improve" other lines.
- Keep all `##` sections. If a section becomes empty, write `- None`.
- A new decision gets `Why:` and the date; a new rule that only applies until something happens gets `(temporary)`.
- Never put passwords, tokens, keys, or connection strings in either file.

## Steps

1. If the user didn't say what to change (just `/handoff-edit`), ask what to add, remove, or fix, and stop.
2. Run `info`.
   - **Note:** if **Note exists: no** → tell the user there is no note to edit and suggest `/handoff-save`. Stop.
   - **Repo match: NO or UNKNOWN** (or the Facts line says **NO repo match**) → don't edit it. Tell the user which repo it belongs to and stop.
3. Run `edit` (note) or `edit -Facts` (facts). This copies the saved body into the **Draft** or **Facts draft** path; for facts with no file yet, it creates an empty template.
   - **Legacy note layout** error → the note is in the old layout; tell the user to run `/handoff-save` once to migrate it, then edit. Stop.
4. Make the requested change in that draft file. If the request is ambiguous (for example, more than one line could match), ask which one.
5. Run `check` (or `check -Facts`). **Review with the user.** Show what changed (removed/added lines) plus any warnings, and ask: save it, or what else to change? Use your ask-user tool if you have one; otherwise ask in chat and stop. Repeat until the user approves.
6. Run `save` (or `save -Facts`). If it reports problems, fix the draft and save again. If it exits with **POSSIBLE SECRETS** (exit code 2), show the masked list and ask the user to remove them (recommended) or keep them; add `-AllowSecrets` only if they say keep.
7. Report the saved path in one line.
