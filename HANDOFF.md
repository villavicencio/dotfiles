# HANDOFF — 2026-07-15 (PST)

Overnight execution of the **Dotfiles 10x roadmap**
(`docs/plans/2026-07-14-001-chore-10x-roadmap-execution-plan.md`) is complete. Opus 4.8 (1M) ran
the 19-packet queue under a Codex adversarial-review gate (`gpt-5.6-sol`). Full per-packet detail
is in **`docs/plans/2026-07-14-001-run-log.md`**. Master ends **green + clean @ `8a0d19c`**.

## Outcome — 19 packets

| Disposition | Count | Packets |
|---|---|---|
| **Merged** (CI-green, review-approved) | **19 (all)** | P0-1..P0-5, P1-1..P1-4, P2-1..P2-8, P3-1, P3-2 |

**The entire 19-packet roadmap is merged.** Both parked drafts (#108 iTerm, #109 fonts) were
rebased onto post-run master and merged; P2-2 (layered dotbot configs) landed once they cleared.
Merged PRs: #100, #102–#119. Highlights: bash-3.2 OMZ install fixed (P0-1); CI asserts install
outcomes + a weekly cron/failure-notifier (P0-2, P2-5); tmux spinner pkill anchor (P0-3); Brewfile
curated + drift reporter (P1-3); 189 MB `fonts/` → Homebrew casks (P1-2); PII-free iTerm Dynamic
Profile (P1-1); zsh/tmux/alias dead-config sweeps (P2-3, P2-4, P2-8); truth-pass docs + LICENSE +
INDEX (P2-6); new **`dot` CLI** + read-only `doctor` (P2-1); **`AGENTS.md`** (P3-2);
`claude/settings.json` hygiene (P2-7); live **NvChad v2.5 nvim** config adopted (P3-1); install
manifests split into **layered `dotbot-conf/`** (P2-2). Startup held under budget (237 ms median).
Follow-up issue: #101 (P0-1 staging-swap).

## Open — the only things left are two manual machine migrations (see checklist)

Nothing in the repo is pending. Two one-time, backup-first migrations remain on the personal Mac:
the **iTerm** profile swap (#108) and the **nvim** `~/.config/nvim` symlink swap (#118). The
settings.json step is a **no-op** — do not symlink it (it would strip your Otty hooks); your live
file is fine as-is. Both migrations are detailed in the checklist below.

## Morning checklist (machine-side; nothing was mutated overnight except noted)

- [x] **P2-7 settings hygiene — NO ACTION on the personal Mac.** Do **not** symlink the repo
      `claude/settings.json` here: your live `~/.claude/settings.json` carries machine-local **Otty
      hooks** (on all 6 events) that the shared baseline can't hold (your work Mac has no Otty), and
      Claude Code has no user-level `*.local` layer. P2-7's real deliverable — a clean *tracked*
      baseline for fresh machines — already shipped in the repo. Your live file is fine as-is. If you
      ever want the minor tidy (drop the `curl`/`ssh` auto-allow rules while keeping Otty + your
      pins): `jq '.allowedTools -= ["Bash(curl -fsSL*)","Bash(curl -s*)","Bash(ssh root@openclaw-prod*)"]'`.
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
