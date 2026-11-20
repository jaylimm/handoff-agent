---
name: handoff-edit
description: "Change only part of the current project's saved handoff note (add, remove, or fix items), let the user review it, then save it. Use when the user runs /handoff-edit, for example `/handoff-edit remove the prune decision`, or asks to add/remove/fix something in the handoff note."
disable-model-invocation: true
---

# Edit a handoff note

Changes only what the user asks for; everything else in the note stays as it is. To rebuild the whole note from this chat, use `/handoff-save` instead.

The helper script lives in the sibling `handoff-save` skill:

```powershell
& "<this skill's folder>\..\handoff-save\scripts\handoff.ps1" <command>
```

Run it from the project's working directory (or pass `-Folder <path>`).

## Rules

- **Never write the note file directly.** Only change the draft file, then run `save`.
- Change only what was asked. Don't reword, reorder, or "improve" other lines.
- Keep the seven `##` sections. If a section becomes empty, write `- None`.
- Never put passwords, tokens, keys, or connection strings in the note.

## Steps

1. If the user didn't say what to change (just `/handoff-edit`), ask what to add, remove, or fix, and stop.
2. Run `info`.
   - **Note exists: no** → tell the user there is no note to edit and suggest `/handoff-save`. Stop.
   - **Repo match: NO or UNKNOWN** → don't edit it. Tell the user which repo the note belongs to and stop.
3. Run `edit`. This copies the saved note body into the **Draft** path.
4. Make the requested change in the draft file. If the request is ambiguous (for example, more than one line could match), ask which one.
5. **Review with the user.** Show what changed (removed/added lines) and ask: save it, or what else to change? Use your ask-user tool if you have one; otherwise ask in chat and stop. Repeat until the user approves.
6. Run `save`. If it reports problems, fix the draft and run `save` again.
7. Report the saved path in one line.
