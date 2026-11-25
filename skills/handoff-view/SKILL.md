---
name: handoff-view
description: "Show the current project's saved handoff note, or its project facts file, as-is, read-only, so the user can read and follow it. Use when the user runs /handoff-view (or /handoff-view facts) or asks to view, show, open, or read the handoff note or project facts."
disable-model-invocation: true
---

# View a handoff note

Read-only. This skill only shows the note or facts; it does not resume work, check the repo, or change anything.

The helper script lives in the sibling `handoff-save` skill. Run it from the project's working directory. This form works in PowerShell, cmd, and Git Bash:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill folder>/../handoff-save/scripts/handoff.ps1" <command> [options]
```

`<skill folder>` is the folder that contains this SKILL.md (in Claude Code: `${CLAUDE_SKILL_DIR}`).

| User asks for | Run |
|---|---|
| This project's note (default) | `view` |
| This project's facts (decisions, Don't Do, commands) | `view -Facts` |
| Another project's note | `list`, then `view -Note "<path from list>"` |

## Steps

1. Run the matching command from the table.
   - **ERROR: No saved note / facts file found** → tell the user there is nothing saved for this repo (show the path), run `list`, show the result, and stop.
2. Show the text (everything after the `---` line) to the user **exactly as printed**, rendered as Markdown. Don't summarize, reorder, or rewrite it.
3. After it, add one line: the file path, plus "Run `/handoff-resume` to continue from it, or `/handoff-edit` to change it." When showing the note, also mention `/handoff-view facts` if `list` or `info` shows the project has a facts file.

## Rules

- Never edit, save, or delete the note from this skill.
- Don't start any work listed in the note; viewing is not resuming.
- Only show another project's note when the user names it or picks it from `list`.
