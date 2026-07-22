# HANDOFF — 2026-07-22 (PST)

**Steady state.** The 10x roadmap (19 packets, all merged — see
`docs/plans/2026-07-14-001-run-log.md` for per-packet detail) is fully closed out, and this
session verified the last machine-side follow-ups from the 2026-07-17 handoff are complete.
Master is green + clean, no open PRs, nothing pending in the repo.

## What This Session Did

Short verification + tidy session (2026-07-22):

- **Verified iTerm migration (#108) done** — `~/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json`
  symlinks to `iterm/profile-dynamic.json`, and the default bookmark GUID matches the Dotfiles
  profile (`DFA17E00-…`). Nothing left to do.
- **Verified nvim migration (#118) done** — `~/.config/nvim` → repo `nvim/`, NVIM v0.12.4 launches
  clean headless, no `lazy-lock.json` churn. Backup dir already cleaned up.
- **`~/.config/zsh/ohmyzsh` leftover** — already gone.
- **Settings tidy applied** — removed the three auto-allow rules from live `~/.claude/settings.json`
  `allowedTools` (`Bash(curl -fsSL*)`, `Bash(curl -s*)`, `Bash(ssh root@openclaw-prod*)`; 20 → 17
  entries). Otty hooks, plugins, pins all untouched; JSON validated. Note: a Bash-level rewrite of
  that file was blocked by the permission classifier — the Edit tool on the file is the sanctioned
  path (via the `update-config` skill).

## What's Next

**Nothing pending.** No repo work, no machine migrations, no parked PRs. Next session starts
fresh — board tickets (https://github.com/users/villavicencio/projects/2) or new work.

## Gotchas & Watch-outs (durable)

- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (tool-managed; #97→#99).
- **`zsh/zshenv` must stay POSIX-safe** — `.`-sourced by `dash`/`bash` during `./install`;
  zsh-only syntax is a fatal "bad substitution" there.
- **`~/.claude/settings.json` on this Mac is a decoupled regular file with machine-local Otty
  hooks — never symlink the repo baseline over it.** The tracked `claude/settings.json` is the
  clean shared baseline for *fresh* machines only.
- **nvim + iTerm write back into tracked files at runtime** (`:Lazy update` → `lazy-lock.json`;
  NvChad theme picker `<leader>th` → `nvim/lua/chadrc.lua`) — expected churn now the symlink is
  live. `nvim/README.md` has the `skip-worktree` tip for theme flips.
- **Install path is layered** (`dotbot-conf/base.yaml` → platform layer); `./install --dry-run`
  must stay mutation-free — verify with the recipe in `CLAUDE.md`/`AGENTS.md` after a Dotbot bump.
- **Verify tooling:** `dot doctor` (read-only health), `dot check` (mirrors CI static checks),
  `dot bench` (startup vs 300 ms). `AGENTS.md` is the tool-neutral repo brief.
- **Codex review gate:** launch on **staged-uncommitted** changes; no backticks/`$@` in the focus
  string.

## External items (carried, unchanged from 2026-07-07)

Foreman naming, domain buys, Ship Sigma calculator, Dec 11 redirect-flip calendar event.
