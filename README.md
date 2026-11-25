# handoff-agent

Per-project session handoff notes for VS Code Copilot, Copilot CLI, Antigravity, Claude Code and Codex: save where you stopped, read it back, and continue in a new chat without re-explaining.

- **One note per project.** Notes are stored outside the repo and never committed.
- **Always fresh.** Each save rebuilds the note; the previous version is kept as `.prev.md`.
- **Lasting facts kept.** Decisions, Don't Do rules and build/test commands live in a separate facts file that survives every save.
- **You approve every save.** Drafts and facts changes are shown in chat first.
- **Repo-checked.** Resume refuses a note from another repo and reports git changes since the save.

## Project Structure

```
handoff-agent/
├── install.ps1                         # installs skills (+ agent where supported) for every tool it finds
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

- At least one of: VS Code with GitHub Copilot Chat, GitHub Copilot CLI, Antigravity, Claude Code, Codex
- Windows PowerShell 5.1 or PowerShell 7
- `git` (to clone the repo; also enables the repo/branch checks)

## Environment Setup

Do this once per PC, in a normal PowerShell window (not inside an editor).

1. **Open each tool at least once**, so its settings folder exists. The installer skips tools it can't find.
2. **Clone the repo** anywhere; it doesn't need to be an editor project:
   ```powershell
   git clone https://github.com/jaylimm/handoff-agent "$HOME\handoff-agent"
   cd "$HOME\handoff-agent"
   ```
3. **Run the installer:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   It lists the tools it found, copies the skills (and agent, where supported) for them, and prints what it installed. Fix any warning it shows before continuing.
4. **Fully restart each tool.**
5. **Open a project** (Antigravity: pick it from the **No Project** menu) and start a new chat.
6. **Check it works:** type `/handoff` (Codex: `$handoff`). You should see `handoff-save`, `handoff-edit`, `handoff-view` and `handoff-resume`, each **once**.

**Update:** run `git pull`, then step 3 again. **Uninstall:** add `-Uninstall` to the step 3 command (your saved notes are kept).

The installer writes only these. All tools share one notes folder, so a note saved in one can be resumed in another:

| What | Where | Used by |
|---|---|---|
| Skills | `%USERPROFILE%\.agents\skills\handoff-*` | VS Code Copilot, Copilot CLI, Codex |
| Skills | `%USERPROFILE%\.claude\skills\handoff-*` | Claude Code |
| Skills | `%USERPROFILE%\.gemini\config\skills\handoff-*` | Antigravity |
| Agent | `%APPDATA%\Code\User\prompts\handoff.agent.md` | VS Code (`@Handoff`) |
| Agent | `%USERPROFILE%\.gemini\config\agents\handoff.md` | Antigravity |
| Notes | `%USERPROFILE%\.copilot\handoffs\` (change with the `HANDOFF_DIR` environment variable) | all |

VS Code and Copilot CLI read both `~\.agents\skills` and `~\.copilot\skills`, so the installer uses only the first and removes copies an older version left in `~\.copilot\skills`. Claude Code and Codex have no `@Handoff` agent; use the slash commands (or ask in plain language, e.g. "save a handoff note").

**VS Code alternative:** Command Palette → **Chat: Install Plugin from Source** → `https://github.com/jaylimm/handoff-agent` → **User**. Use either the plugin or the installer for VS Code, not both, or each command appears twice.

## Command-line Reference

| Command | What it does |
|---|---|
| `/handoff-save` | Drafts a fresh note from this chat plus proposed changes to the project facts, shows them, saves after you approve. |
| `/handoff-edit <change>` | Changes only what you ask in the note or facts, e.g. `/handoff-edit remove the prune decision`. |
| `/handoff-view` | Shows this project's note as-is (read-only). `/handoff-view facts` shows the facts file. |
| `/handoff-resume` | Reads the note and facts, checks what changed in git since the save, summarizes, asks before continuing. |
| `@Handoff <request>` | Plain-language agent for all of the above, plus "list my handoff notes" (all projects) and deleting a note after you confirm. VS Code and Antigravity only. |

**Per tool:** VS Code, Copilot CLI, Antigravity and Claude Code use `/handoff-save` etc. Codex uses `$handoff-save` (or pick it from `/skills`).

The skills do their work through `skills\handoff-save\scripts\handoff.ps1`, called as `powershell -NoProfile -ExecutionPolicy Bypass -File ...` so it works from PowerShell, cmd, and Git Bash (Claude Code's default shell on Windows). You don't need to run it yourself; for details, see `Get-Help .\handoff.ps1 -Detailed`.

## Note Format

Each project has two files in `<HANDOFF_DIR>`, named `<folder>-<hash>`; the hash comes from the repo path, so same-named folders don't collide.

**Note** (`<folder>-<hash>.md`): this session's state, rebuilt on every save. The script writes the header: repo, branch, full commit, uncommitted files with `+added/-removed` counts, time, and a fingerprint of the uncommitted files. On resume, `info` uses the header to report commits since the save, rewritten history (rebase/amend/reset), and whether the working files still match the save; if nothing changed, resume trusts the note without re-reading source files. The body must contain these sections; aim for under 150 lines (hard limit 250):

```markdown
## Objective & Status
## Modified Files & Key Changes      <- path:line refs; short snippets only when needed
## Verified Facts
## Active Errors                     <- exact message, where, how to reproduce
## Tried & Failed
## Waiting on You
## Next Steps
```

**Facts** (`<folder>-<hash>.facts.md`): lasting project knowledge that survives every save. `/handoff-save` proposes additions and removals, and nothing changes without your approval. Aim for under 80 lines (hard limit 150):

```markdown
## Decisions                         <- each with "Why:" and the date
## Don't Do                          <- "(temporary)" rules are proposed for removal once their condition is met
## Environment & Commands            <- build / test / run
```

Notes saved by an older version (with `Verified Facts & Decisions` and `Don't Do` in the note) still resume; the next `/handoff-save` moves their decisions and rules into the facts file.

## Troubleshooting

| Problem | Fix |
|---|---|
| Slash commands don't appear | Restart the tool and start a new chat. Re-run `.\install.ps1` and check it lists the tool as found and its skills folder as installed, not skipped. VS Code plugin: check `chat.plugins.enabled`. Copilot CLI: `/skills list`. |
| The script fails with "running scripts is disabled" | The skills already pass `-ExecutionPolicy Bypass`; if it still fails, a machine policy blocks scripts. Ask IT, or try `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. |
| Each command appears twice in VS Code or Copilot CLI | An old copy is in `%USERPROFILE%\.copilot\skills\` (re-run `.\install.ps1`, which removes it), or both the VS Code plugin and the installer are set up (uninstall the plugin). |
| Antigravity, Codex, or Claude Code asks permission to save the note | Saving writes to `%USERPROFILE%\.copilot\handoffs`, outside the project, so sandboxes and permission prompts ask first. Read the command and approve it, or set `HANDOFF_DIR` to a folder the tool may write to. |
| "No saved note found" | Run `/handoff-save` first, or ask `@Handoff` to list notes if the folder was moved. |
| "Repo match: NO" | The note belongs to another folder; open that folder or save a new note here. |
| "draft not saved" | A section is missing or the body is over 250 lines; the agent fixes the draft and saves again. |
| "POSSIBLE SECRETS (not saved)" | The draft looks like it contains a token, key, or password. Remove it, or tell the agent it's safe to keep. |