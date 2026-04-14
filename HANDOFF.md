# HANDOFF — 2026-04-13, evening

## What We Built

### Bugs fixed
- **`e28293b` — Fix tmux-continuum auto-saves dying after config reload.** Root cause: `tmux source-file` overwrites `status-right`, nuking TPM's injected continuum save script. Fix: inlined `continuum_save.sh` directly into `status-right` in `tmux/tmux.display.conf`. Added belt-and-suspenders `client-attached` hook in `tmux/tmux.general.conf` that forces a resurrect save on every attach.
- **`44da9e6` — Stay in copy mode after yanking in tmux.** Bound `y` and `MouseDragEnd1Pane` to `copy-selection` (not `copy-selection-and-cancel`) in `tmux/tmux.general.conf`.

### Tickets closed
- **#21 (`3d0b344`) — Remove `@win_title_color` from tmux tab rendering.** Dropped the option entirely from `tmux.display.conf` format strings, `save-window-meta.sh`, `restore-window-meta.sh`, SKILL.md, `palettes.md`, sidecar JSON, and CLAUDE.md. Title text now always uses default tmux colors (#4B5263 inactive, #7DACD3 active). Only the glyph carries palette color.
- **#20 (`6be414b`) — Spinner replaces glyph/emoji in tmux tab while Claude is active.** Updated `claude/hooks/tmux-attention.sh` to detect and strip leading emoji from window names on `spinner`/`waiting`, save original in `@win_original_name`, restore on `clear` or when spinner loop detects Claude exited. Skill-styled windows (`@win_glyph`) already worked via the format string ternary.

### Features & config
- **`d0fa498` — Enable iTerm2 passthrough** (`allow-passthrough on`) for imgcat/OSC 1337 in tmux.
- **`a8a41e6` — Machine-local tmux config override.** Added `source-file -q $XDG_CONFIG_HOME/tmux/local.conf` to `tmux/tmux.conf`.
- **`67fe23e` — Reformat Claude Code hooks**, enable `skipDangerousModePermissionPrompt` in `claude/settings.json`.
- **`a4385cf` — Forge bridge in handoff/pickup commands.** `/handoff` can now write-back learnings to Forge workspace and brief Perry. `/pickup` reads Forge shared/project context and processes inbox/pending tickets. Gated on `forge-project-key` in CLAUDE.md.
- **`74f035a` — Registered dotfiles with Forge.** Project key `dotfiles` added to CLAUDE.md, VPS folder created at `workspace-forge/projects/dotfiles/`.

### Documentation
- **`5327c1e` — Two solution docs** in `docs/solutions/tmux/`:
  - `continuum-auto-save-dies-after-config-reload.md` (high severity)
  - `copy-mode-exits-on-yank.md` (medium severity)

## Decisions Made

- **`@win_title_color` removed entirely** (not made optional). The glyph alone carries color accent; title text uses default tmux styling so inactive tabs dim naturally. Reverses the monochrome/subdued pairing concept from prior sessions. Pairing recipe removed from `palettes.md`.
- **Emoji stripping uses Python regex** in the hook script. Standard Unicode emoji ranges only — PUA/Nerd Font glyphs live in `@win_glyph` and are handled by the format string ternary, not name manipulation.
- **Continuum fix is two-layer:** inline in `status-right` (primary) + `client-attached` hook (backup). Both kept intentionally — the hook covers edge cases where the status-right mechanism itself breaks.
- **Forge bridge is opt-in** via `forge-project-key:` in CLAUDE.md. No behavior change for projects without it.

## What Didn't Work

- **2-minute stress test was insufficient for continuum.** Default save interval is 15 minutes, so 2 minutes showed no new saves even when working correctly. Had to check `@continuum-save-last-timestamp` to confirm the script was being called but correctly waiting for the interval.
- **Closing GitHub issues via `gh issue close 21`** failed with "Could not close the issue" — but the issue was already closed (the `Closes #21` in the commit message auto-closed it). Not a real failure, just a confusing error from `gh`.

## What's Next

1. **Cross-machine sync test.** Run `./install` on the work Mac to verify Dotbot symlinks the new skill directory, tmux scripts, Claude hooks, and Forge-enabled commands.
2. **Sidecar rename cleanup.** Orphaned entries in `~/.config/tmux/window-meta.json` when windows are renamed. Needs a cleanup mechanism (hook on window rename, or periodic sweep).
3. **OSC 52 clipboard verification.** Confirmed `set-clipboard external` is set, but haven't verified end-to-end clipboard yanking through mosh to local Mac.

## Gotchas & Watch-outs

- **Never use bare-integer tmux targets** — use `-t :N` or `-t @ID`. Full write-up in `docs/solutions/code-quality/tmux-set-option-bare-index-target-gotcha.md`.
- **PUA glyphs via python only** — `python3 -c` with `\uXXXX` escapes; the Bash tool strips them.
- **Full stdio detach on hook subprocesses** — `</dev/null >/dev/null 2>&1 &` or Claude's UI freezes.
- **`PermissionRequest` only for attention signals** — never `Notification`.
- **Continuum save interval is 15 minutes by default.** Don't use a 2-minute wait to verify auto-saves are working. Check `@continuum-save-last-timestamp` instead.
- **`save-window-meta.sh` now takes 4 args** (session, window, glyph, glyph_color) — the 5th arg (`title_color`) was removed in #21. Any external callers need updating.
- **Perry is now tracking this project.** He's been onboarded on the full project context and conventions.
