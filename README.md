# handoff-agent

Per-project session handoff notes for GitHub Copilot in VS Code and for Antigravity: save where you stopped, read it back, and continue in a new chat without re-explaining.

- **One note per project.** Notes are stored outside the repo and never committed.
- **Always fresh.** Each save rebuilds the note; the previous version is kept as `.prev.md`.
- **You approve every save.** Drafts are shown in chat first.
- **Repo-checked.** Resume refuses a note from another repo and reports git changes since the save.

## Project Structure

```
handoff-agent/
├── install.ps1                         # installs skills + agent for Antigravity and VS Code
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

- Antigravity, or VS Code with GitHub Copilot Chat
- Windows PowerShell 5.1 or PowerShell 7
- `git` (to clone the repo; also enables the repo/branch checks)

## Environment Setup

Works for Antigravity and VS Code. Do this once per PC, in a normal PowerShell window (not inside the editor).

1. **Open each editor at least once**, so its settings folder exists. The installer skips editors it can't find.
2. **Clone the repo** anywhere; it doesn't need to be an editor project:
   ```powershell
   git clone https://github.com/jaylimm/handoff-agent "$HOME\handoff-agent"
   cd "$HOME\handoff-agent"
   ```
3. **Run the installer:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   It copies the skills and agent into each editor it finds and prints what it installed. Fix any warning it shows before continuing.
4. **Fully restart the editor.**
5. **Open a project** (Antigravity: pick it from the **No Project** menu) and start a new chat.
6. **Check it works:** type `/handoff`. You should see `/handoff-save`, `/handoff-edit`, `/handoff-view` and `/handoff-resume`.

**Update:** run `git pull`, then step 3 again. **Uninstall:** add `-Uninstall` to the step 3 command (your saved notes are kept).

The installer writes only these, and both editors share one notes folder, so a note saved in one can be resumed in the other:

| | Antigravity | VS Code |
|---|---|---|
| Skills | `%USERPROFILE%\.gemini\config\skills\handoff-*` | `%USERPROFILE%\.copilot\skills\handoff-*` |
| Agent | `%USERPROFILE%\.gemini\config\agents\handoff.md` | `%APPDATA%\Code\User\prompts\handoff.agent.md` |
| Notes | `%USERPROFILE%\.copilot\handoffs\` (change with the `HANDOFF_DIR` environment variable) | same |

**VS Code alternative:** Command Palette → **Chat: Install Plugin from Source** → `https://github.com/jaylimm/handoff-agent` → **User**. Use either the plugin or the installer for VS Code, not both, or each command appears twice.

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

File: `<HANDOFF_DIR>\<folder>-<hash>.md`. The hash comes from the repo path, so same-named folders don't collide. The script writes the header: repo, branch, full commit, uncommitted files with `+added/-removed` counts, time, and a fingerprint of the uncommitted files. On resume, `info` uses the header to report commits since the save, rewritten history (rebase/amend/reset), and whether the working files still match the save. The body must contain these sections; aim for under 150 lines (hard limit 250):

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
| Slash commands don't appear | Restart the editor and start a new chat. Re-run `.\install.ps1` and check it reports the editor as installed, not skipped. VS Code plugin: check `chat.plugins.enabled`. |
| Commands appear but the script fails with "running scripts is disabled" | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. Work PCs may lock this; ask IT. |
| Each command appears twice in VS Code | Both the plugin and the installer are set up. Uninstall the plugin, or delete the `handoff-*` folders in `%USERPROFILE%\.copilot\skills\`. |
| Antigravity asks permission or fails to save the note | Its command sandbox is blocking writes to `%USERPROFILE%\.copilot\handoffs`. Approve the command, or set `HANDOFF_DIR` to a folder it may write to. |
| "No saved note found" | Run `/handoff-save` first, or ask `@Handoff` to list notes if the folder was moved. |
| "Repo match: NO" | The note belongs to another folder; open that folder or save a new note here. |
| "draft not saved" | A section is missing or the body is over 250 lines; the agent fixes the draft and saves again. |
| "POSSIBLE SECRETS (not saved)" | The draft looks like it contains a token, key, or password. Remove it, or tell the agent it's safe to keep. |