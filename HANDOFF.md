# HANDOFF — 2026-07-15 (PST)

Overnight execution of the **Dotfiles 10x roadmap**
(`docs/plans/2026-07-14-001-chore-10x-roadmap-execution-plan.md`) is complete. Opus 4.8 (1M) ran
the 19-packet queue under a Codex adversarial-review gate (`gpt-5.6-sol`). Full per-packet detail
is in **`docs/plans/2026-07-14-001-run-log.md`**. Master ends **green + clean @ `8a0d19c`**.

## Outcome — 19 packets

| Disposition | Count | Packets |
|---|---|---|
| **Merged** (CI-green, review-approved) | 18 | P0-1..P0-5, P1-1..P1-4, P2-1, P2-3..P2-8, P3-1, P3-2 |
| **Ready** — unblocked, not yet started | 1 | P2-2 (dotbot layered configs) |

All 18 roadmap packets except P2-2 are merged; both parked drafts (#108 iTerm, #109 fonts) were
rebased onto post-run master and merged. Merged PRs: #100, #102–#118. Highlights: bash-3.2 OMZ install fixed (P0-1); CI now
asserts install outcomes + a weekly cron/failure-notifier (P0-2, P2-5); tmux spinner pkill anchor
(P0-3); Brewfile curated + read-only drift reporter (P1-3); zsh/tmux/alias dead-config sweeps
(P2-3, P2-4, P2-8); truth-pass docs + LICENSE + solutions INDEX (P2-6); new **`dot` CLI** with a
read-only `doctor` (P2-1); **`AGENTS.md`** tool-neutral brief (P3-2); `claude/settings.json`
hygiene (P2-7). Startup held under budget (237 ms median). Follow-up issue: #101 (P0-1 staging-swap).

## Open decisions / needs you

1. **P3-1 (nvim) — RESOLVED via Option A (PR #118, merged `fa7c96b`).** The repo now tracks your
   live NvChad v2.5 config (`nvim/`, 27 plugins pinned in `lazy-lock.json`); the dead v1.0 overlay
   is gone and `install_nvim.sh` bootstraps + verifies the pinned set (no NvChad clone). The **only
   remaining step is the one-time machine migration** to swap your live `~/.config/nvim` real dir
   for the repo symlink — it's manual + backup-first (see the checklist below); merging the PR did
   not touch your live config.
2. **#108 (iTerm) — MERGED** (`4df9003`). One manual step left: the iTerm migration (checklist
   below). **#109 (fonts) — MERGED** (`4b412e1`); glyphs confirmed rendering from the casks, so
   **no machine step pending** — the 189 MB tracked `fonts/` is gone from the working tree.
3. **P2-2 (dotbot layered configs) — now UNBLOCKED** (its blockers #108/#109 merged). It's the
   one remaining roadmap packet: restructure `install.conf.yaml` into layered
   `dotbot-conf/{base,darwin,linux}.yaml` + a per-layer wrapper.

## Morning checklist (machine-side; nothing was mutated overnight except noted)

- [ ] **Apply P2-7 settings hygiene on the personal Mac** (currently INERT — see gotcha below):
      back up → remove → `./install` → verify. It's a manual step because `./install` won't clobber
      the live regular file.
- [ ] **#108 iTerm migration** (MERGED — one-time per Mac). `git pull` first, then `./install`
      (creates the Dynamic Profile link), then: **quit iTerm2** →
      `helpers/restore-iterm-app-prefs.sh --migrate` (disables the leaky custom-prefs-folder mode,
      backs the old plist up *outside* the repo) → relaunch iTerm2 → Preferences ▸ Profiles ▸
      select **Dotfiles** ▸ mark default. Verify Shift+Enter + fonts still work.
- [x] **#109 fonts — DONE** (merged; glyphs confirmed rendering from the casks). Both Nerd Font
      casks (`font-jetbrains-mono-nerd-font`, `font-fira-code-nerd-font`) are installed; old manual
      Nerd Font files remain orphaned in `~/Library/Fonts` (harmless — `migrate_legacy_fonts.sh`
      moves them aside on a fresh `./install`; delete them by hand whenever you like).
- [ ] **P3-1 nvim migration** (one-time per Mac; adopts the now-tracked config). Quit nvim, then:
      ```sh
      cd ~/Projects/Personal/dotfiles && git pull            # get the tracked nvim/
      cp -R ~/.config/nvim ~/.config/nvim.backup-2026-07-15  # backup (never deleted by the agent)
      rm -rf ~/.config/nvim                                  # remove the real dir so Dotbot can link
      ./install                                              # creates ~/.config/nvim -> repo nvim/
      readlink ~/.config/nvim                                # must print .../dotfiles/nvim
      nvim --headless "+Lazy! restore" +qa                   # pin plugins to lazy-lock.json
      nvim +checkhealth                                      # confirm lsp/lazy clean
      ```
      Then open nvim normally. `~/.local/share/nvim` (plugin data) is untouched, so it's seamless.
      Once happy, `rm -rf ~/.config/nvim.backup-2026-07-15`. Note: `:Lazy update` and the theme
      picker (`<leader>th`) write back into the tracked `nvim/` files — expected churn; commit the
      lockfile bumps you want (`nvim/README.md` has the `skip-worktree` tip for chadrc theme flips).
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
