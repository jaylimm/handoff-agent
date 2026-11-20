---
name: handoff-view
description: "Show the current project's saved handoff note as-is, read-only, so the user can read and follow it. Use when the user runs /handoff-view or asks to view, show, open, or read the handoff note (or its previous version)."
disable-model-invocation: true
---

# View a handoff note

Read-only. This skill only shows the note; it does not resume work, check the repo, or change anything.

The helper script lives in the sibling `handoff-save` skill:

```powershell
& "<this skill's folder>\..\handoff-save\scripts\handoff.ps1" view
```

Run it from the project's working directory (or pass `-Folder <path>`).

| User asks for | Run |
|---|---|
| This project's note (default) | `view` |
| The previous version | `view -Previous` |
| Another project's note | `list`, then `view -Note "<path from list>"` |

## Steps

1. Run the matching command from the table.
   - **ERROR: No saved note** → tell the user there is no note for this repo (show the path), run `list`, show the result, and stop.
   - **ERROR: No previous version** → say the note has only been saved once and stop.
2. Show the note text (everything after the `---` line) to the user **exactly as printed**, rendered as Markdown. Don't summarize, reorder, or rewrite it.
3. After the note, add one line: the file path, plus "Run `/handoff-resume` to continue from it, or `/handoff-save edit: ...` to change it."

## Rules

- Never edit, save, or delete the note from this skill.
- Don't start any work listed in the note; viewing is not resuming.
- Only show another project's note when the user names it or picks it from `list`.
