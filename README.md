# handoff-agent

Per-project session handoff notes for GitHub Copilot in VS Code and for Antigravity: save where you stopped, read it back, and continue in a new chat without re-explaining.

- **One note per project.** Notes are stored outside the repo and never committed.
- **Always fresh.** Each save rebuilds the note; the previous version is kept as `.prev.md`.
- **You approve every save.** Drafts are shown in chat first.
- **Repo-checked.** Resume refuses a note from another repo and reports git changes since the save.

## Project Structure

```
handoff-agent/
├── plugin.json                         # Agent Plugins manifest (VS Code)
├── .antigravity-plugin/plugin.json     # Antigravity manifest
├── com.github.copilot/agents/
│   └── handoff.agent.md                # @Handoff chat agent (VS Code)
├── agents/
│   └── handoff.md                      # Handoff agent (Antigravity)
└── skills/
    ├── handoff-save/
    │   ├── SKILL.md                    # /handoff-save
    │   └── scripts/handoff.ps1         # helper script used by all skills
    ├── handoff-edit/SKILL.md           # /handoff-edit
    ├── handoff-view/SKILL.md           # /handoff-view
    └── handoff-resume/SKILL.md         # /handoff-resume
```

## Prerequisites

- VS Code with GitHub Copilot Chat (setting `chat.plugins.enabled` turned on), or Antigravity
- Windows PowerShell 5.1 or PowerShell 7
- `git` (optional; enables the repo/branch checks)

## Environment Setup

### VS Code

1. Command Palette → **Chat: Install Plugin from Source**.
2. Enter `https://github.com/jaylimm/handoff-agent` (or a local folder path) and choose **User**.
3. Start a new chat; skills load when a session starts.

**Without plugin support:** copy the four folders in `skills\` to `%USERPROFILE%\.copilot\skills\`. You get the slash commands but not the `@Handoff` agent.

### Antigravity

1. From a clone of this repo, run:
   ```powershell
   agy plugin validate --strict .
   agy plugin install .
   ```
2. Start a new chat. Use the slash commands, or pick the **handoff** agent.

Both editors use the same notes folder, so a note saved in one can be resumed in the other.

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

The skills do their work through `skills\handoff-save\scripts\handoff.ps1`. You don't need to run it yourself; for details, see `Get-Help .\handoff.ps1 -Detailed`.

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
| Slash commands don't appear | Start a new chat. VS Code: check `chat.plugins.enabled`. Antigravity: check `agy plugin list`. |
| "No saved note found" | Run `/handoff-save` first, or ask `@Handoff` to list notes if the folder was moved. |
| "Repo match: NO" | The note belongs to another folder; open that folder or save a new note here. |
| "draft not saved" | A section is missing or the body is over 80 lines; the agent fixes the draft and saves again. |