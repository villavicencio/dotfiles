# HANDOFF — 2026-07-17 (PST)

The **Dotfiles 10x roadmap** (19 packets from the 2026-07-14 audit,
`docs/plans/2026-07-14-001-chore-10x-roadmap-execution-plan.md`) is **100% merged**. An overnight
Opus-4.8 run cleared most of the queue under a Codex `gpt-5.6-sol` adversarial-review gate; this
session finished the tail the run had parked/deferred — the two draft PRs (#108 iTerm, #109 fonts),
the nvim adoption (P3-1), and the layered-config refactor (P2-2). Per-packet detail is in
**`docs/plans/2026-07-14-001-run-log.md`**. Master is **green + clean**; the roadmap work ended at
`4327df5` (HEAD has since moved to `eda8927` from your separate Obsidian vault-standard commits —
not part of this arc).

## What We Built

All 19 packets merged (PRs #100, #102–#119). This session's four:

- **#108 `feat(iterm)` — PII-free Dynamic Profile.** Rebased the parked P1-1 onto post-run master
  (reconciled `install.conf.yaml` + the CI post-apply `action.yml` R3 PII scan). Deletes the
  3,702-line prefs plist (leaked usernames + a corporate hostname), ships a PII-free
  `iterm/profile-dynamic.json` + generator + `restore-iterm-app-prefs.sh --migrate`. Also pruned
  `~/Movies`,`Music`,`Pictures` from the pre-apply `$HOME`-delta assertion (a macOS-runner flake).
- **#109 `feat(fonts)` — Nerd Fonts via casks.** Rebased P1-2; `git rm` the 189 MB tracked `fonts/`
  + `install_fonts.sh`, adds `font-{fira-code,jetbrains-mono}-nerd-font` casks + a transactional
  `migrate_legacy_fonts.sh`. Review caught a stale `AGENTS.md` fonts-helper reference (fixed).
- **#118 `feat(nvim)` — adopt live NvChad v2.5 (Option A).** The plan's premise was wrong (the live
  config was a maintained v2.5 setup, not a fossil); adopted it as-is into `nvim/` (27 plugins pinned
  in `lazy-lock.json`), rewrote `install_nvim.sh` (version-guard ≥0.11, per-plugin commit
  verification, fail-closed). Removed the dead v1.0 `nvim/custom` overlay.
- **#119 `refactor(install)` — layered dotbot configs.** Split the two monolith manifests into
  `dotbot-conf/{base,darwin,linux}.yaml`; the `install` wrapper runs base then platform. Gated on
  **proven dry-run equivalence** (byte-identical Would-create set on both platforms). Helper cleanups
  (dry-run guards, `install_tmux` XDG-cache log, `chsh` SHELL-guard); `bin/dot` doctor/check parse
  all three configs.

Roadmap highlights overall: bash-3.2 OMZ install fixed (0/4→4/4, P0-1); outcome-asserting CI +
weekly cron/notifier (P0-2, P2-5); new **`dot` CLI** + read-only `doctor` (P2-1); **`AGENTS.md`**
tool-neutral brief (P3-2); `claude/settings.json` hygiene (P2-7). Startup 240→**220 ms** median;
tracked tree ~232 MB → **~1.0 MB**.

## Decisions Made

- **nvim = Option A (adopt as-is), not the plan's from-scratch rewrite.** The live config is
  maintained and modern; rebuilding from the dead overlay would have regressed it. Keeps the
  NvChad/NvChad plugin import — "self-contained" in the *tracked + reproducible* sense.
- **`claude/settings.json` on the personal Mac = leave it alone (no symlink).** The live file carries
  machine-local **Otty hooks** the shared baseline can't hold, and Claude Code has **no user-level
  `*.local` layer**. P2-7's real deliverable (a clean *tracked* baseline for fresh machines) already
  shipped; nothing to apply here.
- **P2-2 equivalence gate:** compared normalized `Would create` sets pre/post rather than trusting the
  refactor. The wrapper preserves both the old default (best-effort: both layers run) and
  `-x`/`--exit-on-failure` (fail-fast: skip platform if base fails).
- **Parked PRs → rebase, don't recreate.** Took the clean/new files wholesale, hand-reconciled only
  the conflicting shared files, re-verified + re-reviewed each before merge.

## What Didn't Work

- **Symlinking the settings.json baseline** would strip the live Otty integration — ruled out (see above).
- **Committing before launching the Codex review** — its `--scope working-tree` then sees an empty diff
  and returns a vacuous approve. Always review the **staged-uncommitted** diff.
- **The P2-2 wrapper's first two cuts** both regressed: `set -e` skipped the platform layer on a benign
  base failure (broke best-effort), then exact `-x` matching missed clustered/abbreviated flags. Both
  caught by the gate and fixed.

## What's Next

Nothing is pending in the repo. Two one-time, **backup-first** machine migrations remain (personal Mac):

1. **iTerm (#108):** `git pull` → `./install` → quit iTerm2 → `helpers/restore-iterm-app-prefs.sh --migrate`
   → relaunch → Preferences ▸ Profiles ▸ select **Dotfiles** ▸ set default. Verify Shift+Enter + fonts.
2. **nvim (#118):** quit nvim →
   ```sh
   cd ~/Projects/Personal/dotfiles && git pull
   cp -R ~/.config/nvim ~/.config/nvim.backup-2026-07-17   # backup (do not delete yet)
   rm -rf ~/.config/nvim && ./install                      # Dotbot symlinks ~/.config/nvim -> repo nvim/
   readlink ~/.config/nvim                                  # must print .../dotfiles/nvim
   nvim --headless "+Lazy! restore" +qa && nvim +checkhealth
   ```
   `~/.local/share/nvim` (plugin data) is untouched, so it's seamless. Delete the backup once happy.
3. Optional tidy: drop the `curl`/`ssh` auto-allow rules from your live settings (keeps Otty + pins):
   `jq '.allowedTools -= ["Bash(curl -fsSL*)","Bash(curl -s*)","Bash(ssh root@openclaw-prod*)"]'`.
4. Whenever: `rm -rf ~/.config/zsh/ohmyzsh` (inert P0-1-test leftover; real OMZ is `~/.oh-my-zsh`).

## Gotchas & Watch-outs

- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (tool-managed; #97→#99).
- **`zsh/zshenv` must stay POSIX-safe** — it is `.`-sourced by `dash`/`bash` during `./install`;
  zsh-only syntax (`${var:A:h}`) is a fatal "bad substitution" there (P2-3 lesson).
- **`~/.claude/settings.json` on this Mac is a decoupled regular file with machine-local Otty hooks —
  don't symlink the repo baseline over it** (Claude Code has no user-level `*.local` layer). The
  tracked `claude/settings.json` is the clean shared baseline for *fresh* machines only.
- **nvim + iTerm write back into tracked files at runtime** (`:Lazy update` rewrites `lazy-lock.json`;
  the NvChad theme picker `<leader>th` rewrites `nvim/lua/chadrc.lua`) — expected churn once the nvim
  symlink is live. `nvim/README.md` has the `skip-worktree` tip for theme flips.
- **Install path is now layered** (`dotbot-conf/base.yaml` → platform layer); `./install --dry-run`
  must stay mutation-free — verify with the recipe in `CLAUDE.md`/`AGENTS.md` after a Dotbot bump.
- **Verify tooling:** `dot doctor` (read-only health), `dot check` (mirrors CI static checks),
  `dot bench` (startup vs 300 ms). `AGENTS.md` is the tool-neutral repo brief.
- **Codex review gate:** launch on **staged-uncommitted** changes; no backticks/`$@` in the focus
  string (they trip the shell). Reserve full exhaustiveness for security/correctness code.

## External items (carried, unchanged from 2026-07-07)

Foreman naming, domain buys, Ship Sigma calculator, Dec 11 redirect-flip calendar event.
