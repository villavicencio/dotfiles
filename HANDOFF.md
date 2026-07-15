# HANDOFF — 2026-07-15 (PST)

Overnight execution of the **Dotfiles 10x roadmap**
(`docs/plans/2026-07-14-001-chore-10x-roadmap-execution-plan.md`) is complete. Opus 4.8 (1M) ran
the 19-packet queue under a Codex adversarial-review gate (`gpt-5.6-sol`). Full per-packet detail
is in **`docs/plans/2026-07-14-001-run-log.md`**. Master ends **green + clean @ `8a0d19c`**.

## Outcome — 19 packets

| Disposition | Count | Packets |
|---|---|---|
| **Merged** (CI-green, review-approved) | 15 | P0-1..P0-5, P1-3, P1-4, P2-6, P2-3, P2-4, P2-8, P2-5, P2-1, P3-2, P2-7 |
| **Parked** — draft PR, machine-affecting | 2 | P1-1 (#108 iTerm), P1-2 (#109 fonts) |
| **Parked** — stale premise, needs decision | 1 | P3-1 (nvim) |
| **Deferred** — blocked by parked P1-1/P1-2 | 1 | P2-2 (dotbot layered configs) |

Merged PRs: #100, #102–#107, #110–#117. Highlights: bash-3.2 OMZ install fixed (P0-1); CI now
asserts install outcomes + a weekly cron/failure-notifier (P0-2, P2-5); tmux spinner pkill anchor
(P0-3); Brewfile curated + read-only drift reporter (P1-3); zsh/tmux/alias dead-config sweeps
(P2-3, P2-4, P2-8); truth-pass docs + LICENSE + solutions INDEX (P2-6); new **`dot` CLI** with a
read-only `doctor` (P2-1); **`AGENTS.md`** tool-neutral brief (P3-2); `claude/settings.json`
hygiene (P2-7). Startup held under budget (237 ms median). Follow-up issue: #101 (P0-1 staging-swap).

## Open decisions / needs you

1. **P3-1 (nvim) — the plan's premise was wrong; I did not build it.** The plan assumed the live
   `~/.config/nvim` is a "2022 NvChad fossil" and the repo `nvim/custom` is the active overlay.
   Reality (investigated, not modified): the live config is a **maintained NvChad v2.5** lazy.nvim
   setup (`lazy-lock.json` updated 2026-07-11), **not** git-tracked, and the repo `nvim/custom`
   overlay is symlinked into it but **never imported** (dead). Building P3-1 as written would shelve
   your working editor and replace it with a config reconstructed from the *dead v1.0 overlay* — a
   regression + data-loss risk. **Your call:** (A) adopt the live v2.5 config into the repo as-is
   (track it, pin the existing lockfile, fix `install` to link it); (B) true from-scratch rewrite
   (bigger — and port from the *live v2.5* plugin set, not the old overlay); or (C) leave nvim out.
   Secondary real bug either way: on a fresh machine `install_nvim.sh` clones NvChad HEAD and links
   the v1.0-incompatible overlay → fresh-machine editor is broken.
2. **Parked draft PRs #108 (iTerm) & #109 (fonts)** — both machine-affecting, want your review +
   the one-time manual migration on each Mac (see run-log "Morning-checklist additions").
3. **P2-2 (dotbot layered configs) deferred** — it restructures `install.conf.yaml`, which #108/#109
   also modify; it should run *after* those two are merged or closed.

## Morning checklist (machine-side; nothing was mutated overnight except noted)

- [ ] **Apply P2-7 settings hygiene on the personal Mac** (currently INERT — see gotcha below):
      back up → remove → `./install` → verify. It's a manual step because `./install` won't clobber
      the live regular file.
- [ ] **#108 iTerm** (if merging): iTerm2 **quit** → `helpers/restore-iterm-app-prefs.sh --migrate`
      → relaunch → Preferences → Profiles → select **Dotfiles** → mark default.
- [ ] **#109 fonts** (if merging): both Nerd Font casks were force-installed during P1-2 verification
      (`font-jetbrains-mono-nerd-font`, `font-fira-code-nerd-font` @3.4.0); old manual Nerd Font
      files remain orphaned in `~/Library/Fonts` (harmless; `migrate_legacy_fonts.sh` handles the
      collision on a fresh `./install`). Visually confirm tmux pill glyphs + starship symbols.
- [ ] **P3-1 nvim** — decide A/B/C above before any nvim restructure.
- [ ] **Stray dir (safe to delete, not deleted — data-safety):** `~/.config/zsh/ohmyzsh` — inert OMZ
      clone created 2026-07-14 by the P0-1 acceptance test's ZDOTDIR leak. Real OMZ is `~/.oh-my-zsh`.
      `rm -rf ~/.config/zsh/ohmyzsh` when convenient.

## Gotchas & watch-outs (durable)

- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (tool-managed; #97→#99).
- **`zsh/zshenv` must stay POSIX-safe** — it is `.`-sourced by `dash`/`bash` during `./install`;
  zsh-only syntax (`${var:A:h}`) is a fatal "bad substitution" there (P2-3 lesson).
- **`claude/settings.json` is now the shared cross-machine baseline** (P2-7): pins, two dead
  marketplaces, and host-specific `curl`/`ssh` auto-allow rules removed. Claude Code has **no
  user-level `*.local` override layer** (`settings.local.json` is project-scoped only), so
  per-machine user settings live on that machine's own `~/.claude/settings.json`, uncommitted.
- **P2-7 is INERT on the personal Mac until migrated.** The live `~/.claude/settings.json` is a
  **regular file** (decoupled). Dotbot links `relink: true` with **no `force`**, so `./install`
  won't overwrite it. To apply (**do not auto-delete — live user data**): `cp ~/.claude/settings.json
  ~/.claude/settings.json.bak` → remove it → `./install` → verify (`readlink ~/.claude/settings.json`;
  `jq '.model // "gone"' ~/.claude/settings.json`). A fresh session then sees more prompts, by design.
- **Verify tooling:** `dot doctor` (read-only health), `dot check` (mirrors CI static checks),
  `dot bench` (startup vs 300 ms). `AGENTS.md` is the tool-neutral repo brief.
- **Codex review gate:** launch on **staged-uncommitted** changes (`--scope working-tree`); a review
  run after commit sees an empty diff and returns a vacuous approve.

## External items (carried, unchanged from 2026-07-07)

Foreman naming, domain buys, Ship Sigma calculator, Dec 11 redirect-flip calendar event.
