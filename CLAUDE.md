# Dotfiles

This repo is the single source of truth for two Macs, a headless Mac mini server and a Windows gaming PC:

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | corporate-managed |
| hal | macOS 27 | Mac mini (Apple Silicon) | Headless server, SSH only; `DOTFILES_PROFILE=server ./install`, run as `hal` (`docs/reference/install-and-server.md`) |
| gaming-pc | Windows 11 Pro | Ryzen 7 5800X / RTX 3070 | Gaming; set up by `install.ps1`, not Dotbot (`docs/reference/windows.md`) |
| gaming-pc WSL | Ubuntu 26.04 LTS (WSL 2) | same PC | The Linux layer; a separate clone inside WSL (`docs/reference/wsl-linux.md`). Same release as CI's Linux leg (VIL-154) |

Managed by [Dotbot](https://github.com/anishathalye/dotbot). Run `./install` to set up a machine — the wrapper runs a shared `dotbot-conf/base.yaml` and then the platform layer (`dotbot-conf/darwin.yaml` on Darwin, `dotbot-conf/linux.yaml` on Linux) automatically. The active Linux target is WSL Ubuntu on the gaming PC (since 2026-09-24); the earlier Hetzner VPS target was retired 2026-05-21 (runbook: `docs/solutions/cross-machine/vps-dotfiles-target.md`).

> **How this file works.** It holds the rules; the write-ups behind them live in
> `docs/reference/` (one file per area, listed below). Before changing an area, read its
> file. [`AGENTS.md`](AGENTS.md) is the tool-neutral brief for other agents (Codex, Cursor…)
> and covers layout, common tasks and the verification table. Keep the two in step.

---

## Rules

Each line is a rule; the file in parentheses has the why, the history and the exact commands.

**Paths and shell** (`docs/reference/shell-and-path.md`)
- Homebrew paths use `$BREW_PREFIX`, never `/opt/homebrew` or `/usr/local`; never `$HOMEBREW_BREW_FILE`. Home paths use `$HOME` or `~`. A literal home path (`/Users/` plus a name) or a hostname in any tracked file except `docs/**` and `HANDOFF.md` fails CI's R3 check on every Unix leg. Write `/Users/<account>/`.
- Agent shells get GNU coreutils first on PATH (`date -j` fails; use `date -u -d …` or `/bin/date`), but `sed` stays BSD (`sed -i ''`, or `gsed -i`).
- Machine-local values go in untracked files: `~/env.sh` (shell, sourced last), `~/.gitconfig.local` (git identity), `~/.ssh/config` (host aliases), `~/env.ps1` (Windows).
- After any third-party installer that edits shell config, `git diff` and fix hardcoded paths. `~/.config/zsh/.zshrc` is a link into this repo, so a machine-specific line goes to `~/env.sh`.
- Lazy loaders follow the `_load_X` pattern (copy an existing one; `command <tool>` after loading). `zsh -i -c exit` stays under 300 ms. A global npm CLI needs no nvm shim.
- uv and Claude Code come from their vendor installers into `~/.local/bin`, not the Brewfile (`UV_NO_MODIFY_PATH=1` is required). `zshrc` re-sources `zshenv` after `brew shellenv`; don't remove it.
- Node version lives in `NODE_VERSION` (`zsh/zshenv`). A new Oh My Zsh plugin also gets its `git clone` in `helpers/install_omz.sh`.

**Claude Code config** (`docs/reference/claude-code-config.md`)
- `claude/settings.json` is copy-seeded, never linked. Agents can't write `~/.claude/settings.json`; give David the exact command to run with `!`. Record live changes with `dot drift` and `helpers/install_claude_settings.sh --capture`. A tracked change an existing machine needs (a removed hook, a new key) goes into `helpers/migrate_claude_settings.py`, which David runs. Windows seeds `windows/claude-settings.json`; keep shared keys in step.
- No `allowedTools` key, ever: it silently overrides `permissions.allow`. `Write(path)` rules are inert (use `Edit(path)`). A `*` in a `Bash(...)` rule goes only after the subcommand.
- Don't register a hook in `settings.json` until its file is on `master` (the hook links into this working tree).
- The auto-mode classifier also blocks secret-store writes, credential materialization and unattended-agent instructions; hand those to David.

**Repo mechanics**
- Never `./install` from a worktree, never launch nvim there, never `git submodule deinit` there. Removing an Orca worktree takes the cleanup and then Force delete (`docs/reference/orca-worktrees.md`).
- The main checkout is what this Mac runs: zsh, nvim, tmux and the Claude statusline are linked into it. Branch work that changes them goes in a worktree (`wt new`), not a branch checked out in the main checkout, or it's live before review (#256, 2026-10-28).
- No heredocs in `bin/dot`; its Python lives in `bin/lib/*.py` (`docs/reference/tooling.md`).
- A new state-mutating helper gets the `DOTFILES_DRY_RUN` guard, and `./install --dry-run` stays mutation-free (`docs/reference/tooling.md`).
- Keep the nvim install's snapshot/restore/verify; don't collapse it into one `Lazy! restore`. Minimum Neovim is 0.12 (`docs/reference/neovim.md`).
- This repo is public: don't name David's employer or describe his work agents. gitleaks runs on every commit, and its version is pinned in three places (`docs/reference/secret-hygiene.md`).
- Topgrade from an agent shell has no TTY, so a cask's sudo fails. Touch ID for sudo is a manual root step (`docs/reference/tooling.md`).
- `topgrade/topgrade.toml` skips steps via `[misc] disable` with exact variant names; `vim` stays disabled.
- Windows: adding or removing a link in `install.ps1` means updating CI's `EXPECTED_LINKS`; never run `python3` in a Windows install step (`docs/reference/windows.md`).
- The hal overnight pilot runner (VIL-396) lives in the private repo `villavicencio/hal-pilot`, cloned on hal as `david` at `~/Projects/hal-pilot`, not here (VIL-515).
- The `atlas`/`axiom`/`syd` functions and their Orca tabs: `docs/reference/hermes-commands.md`. hal's server profile: `docs/reference/install-and-server.md`. WSL and the Linux git overlay: `docs/reference/wsl-linux.md`. Work Mac setup: `docs/reference/work-mac.md`.

**Tickets, branches and review** (`docs/reference/review-and-merge.md`)
- Issues live in Linear (project Dotfiles, team key VIL); use `/ticket`. Never create GitHub issues.
- Behavior and config changes go on a branch (`feat/`, `fix/`, `chore/`, `docs/`, `style/`) and merge by PR. Docs, typos and handoffs can go straight to `master`. A ticket always gets its own branch, named `<type>/vil-N-<slug>` (e.g. `feat/vil-522-statusline-ticket`), so the statusline shows its id (VIL-522).
- Review is review-stack (MergeWren). It reviews each new head of a non-draft PR in 2–6 minutes. Wait for the comment for the current head (poll every 60 s, give up after 20 min):
  `gh pr view <N> --repo villavicencio/dotfiles --json headRefOid,comments --jq '.headRefOid as $h | [.comments[] | select(.body | contains("review-stack:head=" + $h))] | last | .body // "PENDING"'`
  It's merge-ready when that comment has no unwaived high or critical finding and the unresolved-threads check is empty. A `partial` or `failed` verdict, or "did not complete", means not reviewed. Don't wait for or trigger CodeRabbit here.
- A docs-only PR skips the install matrix but not the review.

## Structure

```
brew/           Brewfile for all Homebrew packages and casks; Brewfile.server for the server profile
btop/           btop system monitor config
docs/           Compound-engineering pipeline artifacts:
                - docs/brainstorms/  Requirements docs from /ce-brainstorm
                - docs/ideation/     Idea-survival outputs from /ce-ideate
                - docs/plans/        Implementation plans from /ce-plan
                - docs/solutions/    documented solutions to past problems (bugs, best practices, workflow patterns), organized by category with YAML frontmatter (module, tags, problem_type)
                Also: docs/agents/ (cross-project agent procedures) and docs/reference/
                (this repo's long write-ups, moved out of CLAUDE.md)
ci/             CI assets (Dockerfile for install-matrix's linux leg, PSScriptAnalyzer settings for its windows leg,
                server-profile-checks.sh for its macos-server leg; cleanup-merged-branch-checks.sh
                and op-agent-checks.sh, run by hand, not in CI)
git/            gitconfig, gitignore, gitattributes, gitconfig.linux (Linux overlay — see
                docs/reference/wsl-linux.md)
helpers/        Bash scripts called by the install pipeline
iterm/          iTerm2 preferences (exported plist, includes Shift+Enter key mapping)
lazygit/        lazygit config
npm/            npm global package list (npm-requirements.txt)
nvim/           Neovim config (NvChad v2.5; the whole dir is linked as ~/.config/nvim,
                %LOCALAPPDATA%\nvim on Windows). Plugins pinned in lazy-lock.json
starship/       Starship prompt config (command_timeout is a global top-level key)
windows/        Windows layer, applied by install.ps1 at the repo root (NOT Dotbot):
  packages.json           winget package list — the Brewfile counterpart
  gitconfig               overrides chained after git/gitconfig by the ~/.gitconfig stub
  powershell/profile.ps1  PowerShell 7 profile — the zshrc + alias.sh counterpart
  terminal/dotfiles.json  Windows Terminal fragment — the iTerm dynamic-profile counterpart
  claude-settings.json    hook-free Claude Code settings, copy-seeded to ~/.claude/settings.json
  tweaks.ps1              system settings (mouse, Game Bar, Game Mode, GPU scheduling, time sync,
                          Terminal default profile) — the `defaults write` counterpart;
                          a separate opt-in step, NOT run by install.ps1
  install_nvim.ps1        nvim plugin bootstrap — the helpers/install_nvim.sh counterpart
bin/            Repo CLI — bin/dot, bin/wt (one worktree per parallel session,
                docs/agents/parallel-sessions.md), and bin/op-agent (1Password for agents,
                docs/agents/1password.md); all symlinked into ~/.local/bin
  lib/*.py      Python helpers for doctor/bench. Real files, NOT heredocs — see
                docs/reference/tooling.md
  lib/cleanup-merged-branch.sh  the merged-branch cleanup function (docs/agents/code-review.md)
orca.yaml       Orca's setup script for each new worktree (docs/reference/orca-worktrees.md)
.worktreeinclude  gitignored files copied into new worktrees (claude --worktree, wt new, orca.yaml)
tmux/           tmux config
topgrade/       Topgrade system updater config
vale/           Vale prose linter config
zsh/
  zshenv        Environment variables, PATH, BREW_PREFIX — sourced early
  zshrc         Shell config, plugins, lazy loaders
  alias.sh      Aliases
  functions.sh  Functions (also sources zsh/functions/*.sh)
  functions/    Individual function files (man_colorful, mkdir_and_cd, etc.)
claude/
  CLAUDE.md              Global Claude Code instructions (symlinked to ~/.claude/CLAUDE.md)
  settings.json          Claude Code settings — plugins, allowed tools (COPY-SEEDED to ~/.claude/settings.json, never symlinked)
  statusline-command.sh  Statusline script (symlinked to ~/.claude/statusline-command.sh)
```

Note: the `/handoff`, `/pickup`, and `/review-claudemd` slash commands now live in an
external Claude Code plugin, not this repo. The only repo-local command is
`.claude/commands/ticket.md` (a hidden `.claude/` dir for working *in* this repo).

---

## Things intentionally left as-is

- `MYSQL_BIN="/usr/local/mysql/bin"` — MySQL PKG installer uses this path on both architectures, it is not a Homebrew path.
- `git/gitconfig` `core.pager = vim -` — intentional preference; vim is the pager for `log`/etc. (Note: `git diff`/`git show` deliberately route through **delta** via the `[pager]` overrides — `core.pager` staying `vim -` is by design, not an oversight.) This is the Mac preference only: Linux hosts get `less -FRX` from `git/gitconfig.linux` (VIL-146).
- The tmux session restoration block in `zshrc` — guarded to only run outside tmux and only in iTerm2.
- GCM credential helper entries in `git/gitconfig` — auto-generated by Git Credential Manager, commit separately from other work.
- **Linux Dotbot layer + helper branches** (`dotbot-conf/linux.yaml`, the `uname`-guarded locale step in `dotbot-conf/base.yaml`, `case Linux)` in `./install`, `uname` guards in `helpers/*`) — preserved after the VPS was decommissioned (2026-05-21) and in active use again since 2026-09-24 for WSL Ubuntu on the gaming PC (`docs/reference/wsl-linux.md`). The VPS-specific runbook stays at `docs/solutions/cross-machine/vps-dotfiles-target.md`.

## Forge Identity
forge-project-key: dotfiles
