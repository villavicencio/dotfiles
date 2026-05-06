# Brainstorm — VPS Tmux Glyph Treatment

**Date:** 2026-04-17
**Author:** David Villavicencio
**Status:** Ready for planning

---

## What We're Building

Give the **VPS's inner tmux status bar** the same glyph + palette treatment the
Mac's outer tmux already has. When SSHed into `openclaw-prod` from a local
tmux session, the nested VPS tmux currently shows plain `1: ops | 2: logs |
3: openclaw | 4: tui` while the outer bar below shows colored glyph-prefixed
tabs (✦ Home, 🌐 Work, 🎯 Eagle, ⚙ Dotfiles). The nesting itself stays —
we want **visual parity**, not collapse.

The VPS already symlinks `tmux/tmux.conf` (including the glyph ternary in
`window-status-format`) and `restore-window-meta.sh` via
`install-linux.conf.yaml`. The ternary checks `@win_glyph` /
`@win_glyph_color` per-window user options — which are empty on the VPS
because no one has ever run the `tmux-window-namer` skill there. The machinery
is there; only the data is missing.

## Why This Approach

Chose **Approach A: static seed JSON, Linux-only symlink** over two
alternatives:

- **B — Inline `set-hook` in tmux.conf** would embed glyph data imperatively
  in shell config. Harder to scan, splits data across two spellings (tmux
  options + palette file).
- **C — Make the skill VPS-aware** via a `--remote` flag that pushes over
  SSH. Unified control plane, but huge lift for a 4-window layout that
  essentially never changes. Classic YAGNI.

**A wins** because it reuses the existing `restore-window-meta.sh` hook,
costs zero new code, and is declarative/reviewable in git. The VPS's
window set is stable (part of the OpenClaw stack), so a committed seed
fits perfectly.

Drift concern investigated and dismissed: `save-window-meta.sh` is
invoked only by the Mac skill with explicit CLI args — there's no
auto-save hook in `tmux.general.conf`. The VPS never writes back, so a
symlink to a committed seed file stays pristine.

## Key Decisions

- **Repo path:** `tmux/window-meta.linux.json` — parallels
  `install.conf.yaml` vs `install-linux.conf.yaml` naming.
- **Target path on VPS:** `~/.config/tmux/window-meta.json` via Dotbot
  symlink, added under the `- link:` block of `install-linux.conf.yaml`
  alongside the existing `save-window-meta.sh` / `restore-window-meta.sh`
  entries.
- **Mac install untouched.** `install.conf.yaml` (Darwin) does NOT symlink
  this file — Mac continues to manage its live `window-meta.json`
  directly via the skill.
- **Palette discipline:** glyph colors chosen from
  `claude/skills/tmux-window-namer/references/palettes.md` only. No
  freeform hex.
- **Session name assumption:** VPS tmux session is `main` (confirmed from
  screenshot). JSON top-level key is `"main"`.

## Window Mappings (locked)

| Window     | Glyph | Palette | Hex       |
|------------|-------|---------|-----------|
| `ops`      | ⚙    | ocean   | `#56B6C2` |
| `logs`     | ≡    | smoke   | `#4B5263` |
| `openclaw` | 🦀   | ember   | `#D97757` |
| `tui`      | ▤    | sky     | `#7DACD3` |

Rendered preview (matches `window-status-format` in `tmux.display.conf`,
which renders `#I:` directly against the glyph):
`main  1:⚙ ops  2:≡ logs  3:🦀 openclaw  4:▤ tui`.

## Acceptance Criteria

- After `./install` on openclaw-prod, attaching to the VPS tmux session
  shows glyph-prefixed tabs in the inner status bar matching the Mac
  style.
- No change to the Mac's live `~/.config/tmux/window-meta.json`
  behavior.
- `./install --dry-run` on Linux reports a "would symlink" line for the
  new file and zero mutations.
- Seed file survives window renaming: if a VPS window is renamed outside
  the seed's known keys, the tab simply falls back to the no-glyph
  branch of the ternary (same as unseeded windows today).

## Resolved Questions

- **Q:** Will the seed file drift if the VPS ever writes back?
  **A:** No. `save-window-meta.sh` is only invoked by the Mac skill with
  CLI args; no tmux hook auto-triggers it. The symlink target stays
  pristine.
- **Q:** Final glyph + color pairing per window?
  **A:** Locked in the mapping table above (⚙/ocean, ≡/smoke, 🦀/ember,
  ▤/sky).
- **Q:** What happens when a new VPS window appears?
  **A:** Falls back to no-glyph rendering (same as any unseeded window
  today). Update requires editing `tmux/window-meta.linux.json`.
  Acceptable for a stable layout.
- **Q:** Should we also de-style the VPS tmux status-left/right?
  **A:** Out of scope — user's goal is style parity on window tabs, not
  collapsing or restyling the outer bar.

## Open Questions

1. **Verify VPS tmux runs host-level, not inside a container.** This
   brainstorm assumes the VPS tmux session is the host user's tmux,
   reading `~/.config/tmux/tmux.conf` symlinked by Dotbot. Evidence
   (operator-style window layout `ops/logs/openclaw/tui`) points that
   way, but if it turns out the tmux is inside the OpenClaw container,
   the host-side symlink is invisible to it and the approach changes
   (mount the seed into the container, or adopt approach B/C).
   Resolve at the start of `/ce:plan` with `ssh root@openclaw-prod
   'tmux display -p "#{socket_path}"'` or an equivalent check.

## Out of Scope

- Changing which bars appear when nested (collapsing the VPS status
  bar, hiding the outer bar on SSH, etc.).
- Porting the `tmux-window-namer` skill to the VPS or any remote/SSH
  mode for it.
- Restyling the top agent/session header strip (that's Claude Code /
  OpenClaw UI, not tmux — different layer, different repo).

---

**Next step:** `/ce:plan` will pick up this document and turn it into an
implementation plan.
