# handoff-agent

Per-project session handoff notes for GitHub Copilot in VS Code: save where you stopped, read it back, and continue in a new chat without re-explaining.

- **One note per project.** Notes are stored outside the repo and never committed.
- **Always fresh.** Each save rebuilds the note; the previous version is kept as `.prev.md`.
- **You approve every save.** Drafts are shown in chat first.
- **Repo-checked.** Resume refuses a note from another repo and reports git changes since the save.

## Project Structure

```
handoff-agent/
├── plugin.json                         # Agent Plugins manifest
├── com.github.copilot/agents/
│   └── handoff.agent.md                # @Handoff chat agent
└── skills/
    ├── handoff-save/
    │   ├── SKILL.md                    # /handoff-save
    │   └── scripts/handoff.ps1         # helper script used by all skills
    ├── handoff-edit/SKILL.md           # /handoff-edit
    ├── handoff-view/SKILL.md           # /handoff-view
    └── handoff-resume/SKILL.md         # /handoff-resume
```

## Prerequisites

- VS Code with GitHub Copilot Chat, setting `chat.plugins.enabled` turned on
- Windows PowerShell 5.1 or PowerShell 7
- `git` (optional; enables the repo/branch checks)

## Environment Setup

1. Command Palette → **Chat: Install Plugin from Source**.
2. Enter `https://github.com/jaylimm/handoff-agent` (or a local folder path) and choose **User**.
3. Start a new chat; skills load when a session starts.

**Without plugin support:** copy the four folders in `skills\` to `%USERPROFILE%\.copilot\skills\`. You get the slash commands but not the `@Handoff` agent.

| Environment variable | Default | Purpose |
|---|---|---|
| `HANDOFF_DIR` | `%USERPROFILE%\.copilot\handoffs` | Where notes are stored |

## Command-line Reference

| Command | What it does |
|---|---|
| `/handoff-save` | Drafts a fresh note from this chat, shows it, saves after you approve. |
| `/handoff-edit <change>` | Changes only what you ask, e.g. `/handoff-edit remove the prune decision`. |
| `/handoff-view` | Shows this project's note as-is (read-only). |
| `/handoff-resume` | Checks the note against the repo and git, summarizes, asks before continuing. |
| `@Handoff <request>` | Plain-language agent for all of the above, plus "list my handoff notes" (all projects) and deleting a note after you confirm. |

## CLI Flag Summary

The skills call `skills\handoff-save\scripts\handoff.ps1`; you can also run it directly from a project folder.

```powershell
.\handoff.ps1 <command> [-Folder <path>] [-MaxLines <n>] [-Note <path>]
```

| Command | Description |
|---|---|
| `info` | Repo root, git state, note/draft paths, and whether the note matches this repo. |
| `edit` | Copies the saved note body into the draft file for editing. |
| `save` | Validates the draft, adds the git header, backs up the old note to `.prev.md`, saves. |
| `view` | Prints the saved note. |
| `list` | Lists every saved note with its repo and save time. |

| Flag | Default | Used by | Description |
|---|---|---|---|
| `-Folder` | current directory | all | Project folder to find the note for. |
| `-MaxLines` | `80` | `save` | Maximum note body length. |
| `-Note` | — | `view` | View a specific note path from `list` (must be inside `HANDOFF_DIR`). |

## Note Format

File: `<HANDOFF_DIR>\<folder>-<hash>.md`. The hash comes from the repo path, so same-named folders don't collide. The script writes the header (repo, branch, commit, uncommitted files, time); the body must contain these sections:

```markdown
## Objective & Status
## Modified Files & Key Changes
## Verified Facts & Decisions
## Tried & Failed
## Waiting on You
## Next Steps
## Don't Do
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Slash commands don't appear | Start a new chat; check `chat.plugins.enabled`. |
| "No saved note found" | Run `/handoff-save` first, or ask `@Handoff` to list notes if the folder was moved. |
| "Repo match: NO" | The note belongs to another folder; open that folder or save a new note here. |
| "draft not saved" | A section is missing or the body is over 80 lines; Copilot fixes the draft and saves again. |