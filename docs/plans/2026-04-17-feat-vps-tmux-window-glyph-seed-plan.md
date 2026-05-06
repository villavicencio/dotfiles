---
title: Add VPS tmux window glyph seed
type: feat
status: completed
date: 2026-04-17
origin: docs/brainstorms/2026-04-17-vps-tmux-glyph-treatment-brainstorm.md
---

# Add VPS tmux window glyph seed ✨

## Overview

Give the VPS's inner tmux status bar the same colored-glyph treatment
the Mac's outer tmux already has. The tmux-side machinery (glyph
ternary in `window-status-format`, `restore-window-meta.sh`
client-attached hook, both meta scripts) is already deployed on the
VPS via `install-linux.conf.yaml`; what's missing is data. This plan
adds a committed seed file `tmux/window-meta.linux.json` and a
Linux-only Dotbot symlink pointing `~/.config/tmux/window-meta.json`
at it. Zero new code. Darwin install untouched.

(See brainstorm:
`docs/brainstorms/2026-04-17-vps-tmux-glyph-treatment-brainstorm.md`)

## Problem Statement / Motivation

When SSHed into `openclaw-prod` from a local tmux, the nested VPS
tmux renders `main 1: ops 2: logs 3: openclaw 4: tui` — plain text —
while the outer local bar renders glyph-prefixed colored tabs
(`✦ Home`, `🌐 Work`, etc.). Visual parity across the two status
bars is the goal. Collapsing the nested bar is **out of scope**
(confirmed during brainstorm — user answered "Match the glyph +
palette style").

The outer Mac tmux gets its glyphs because the `tmux-window-namer`
Claude skill writes to `~/.config/tmux/window-meta.json` interactively
during Mac-side sessions. The VPS has no equivalent skill invocation,
so `@win_glyph` / `@win_glyph_color` user options are never set and
the ternary at `tmux/tmux.display.conf:67-68` falls through to the
no-glyph branch.

## Proposed Solution

**Approach: static seed JSON, Linux-only Dotbot symlink.** Selected
over (B) an inline `set-hook` config block and (C) making the skill
VPS-aware over SSH. The VPS window set is stable (`ops`, `logs`,
`openclaw`, `tui` are part of the operator's long-running OpenClaw
layout), which makes a declarative committed seed the natural fit.
(See brainstorm § Why This Approach.)

**Architectural win worth naming:** the `tmux-window-namer` skill
stays purely local (Mac-only, no remote-execution surface), the
tmux config stays purely declarative (session-agnostic, same file
both hosts), and Dotbot remains the sole host-aware layer. That
three-way separation is the thing to preserve as the repo grows.

### New file: `tmux/window-meta.linux.json`

```json
{
  "main": {
    "ops":      { "glyph": "⚙",  "glyph_color": "#56B6C2" },
    "logs":     { "glyph": "≡",  "glyph_color": "#4B5263" },
    "openclaw": { "glyph": "🦀", "glyph_color": "#D97757" },
    "tui":      { "glyph": "▤",  "glyph_color": "#7DACD3" }
  }
}
```

Schema matches exactly what `tmux/scripts/restore-window-meta.sh:18-22`
reads: top-level `.session.window.{glyph, glyph_color}`. Hexes taken
from `claude/skills/tmux-window-namer/references/palettes.md:12-20`
(ocean / smoke / ember / sky).

### Edit: `install-linux.conf.yaml`

Extend the existing link block at lines 80-82 (the one already
symlinking the meta scripts):

```yaml
- link:
    ~/.config/tmux/scripts/save-window-meta.sh: tmux/scripts/save-window-meta.sh
    ~/.config/tmux/scripts/restore-window-meta.sh: tmux/scripts/restore-window-meta.sh
    ~/.config/tmux/window-meta.json: tmux/window-meta.linux.json   # NEW
    ~/.config/nvim/lua/custom:
      path: nvim/custom
      create: true
```

Darwin `install.conf.yaml:69-83` is untouched — verified clean, no
existing `window-meta.json` entry there. Mac's live sidecar
continues to be written by the skill as today.

### Rendered result

Inner VPS tmux bar after reattach (matches `window-status-format` —
`#I:` renders directly against the glyph with no intervening space):

```
 main   1:⚙ ops   2:≡ logs   3:🦀 openclaw   4:▤ tui
```

## Technical Considerations

- **Schema / encoding.** Restore script (`tmux/scripts/restore-window-meta.sh:18-26`)
  uses `jq '.[$s][$w] // empty'` and guards on `[ -n "$glyph" ]` /
  `[ -n "$glyph_color" ]`, so empty-string values silently skip. Our
  seed keeps all four values non-empty. Commit with UTF-8 encoding
  (git default for `.json`).
- **Target-syntax correctness.** Restore uses
  `target="${session}:${idx}"` (line 23), i.e. session-qualified
  targeting, not a bare integer. Safe across multi-session hosts.
  (Cross-checked against the "bare integer hits current window"
  learning — not a concern here.)
- **jq on VPS.** Installed via `helpers/install_packages.sh:23`.
  Restore's missing-jq silent-no-op guard (line 13) won't trigger.
- **`relink: true` semantics.** The Linux conf sets this at line 3.
  If `~/.config/tmux/window-meta.json` exists on the VPS as a
  non-symlink, Dotbot removes it and creates the symlink. The
  brainstorm established that no skill runs on VPS and nothing
  auto-writes this path today, so there's no live state to lose.
  Preflight check included below for paranoia.
- **Hook firing.** `set-hook -g client-attached` at
  `tmux/tmux.general.conf:81` fires on every fresh attach. On a
  pre-existing persistent VPS session, the hook does **not** retro-
  actively fire — operator must detach/reattach OR run the restore
  script once manually. (See
  `docs/solutions/cross-machine/vps-dotfiles-target.md:265-268`.)
- **Dry-run guarantee.** Dotbot v1.24.1 (submodule-pinned) handles
  `--dry-run` natively for `link` directives and emits "Would create
  symlink" lines with zero filesystem mutation. No helper-script
  guards needed for this change. (See `CLAUDE.md:138-164`,
  `docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md`.)

## System-Wide Impact

### Interaction graph

`./install` on Linux → Dotbot applies `link` block → symlink at
`~/.config/tmux/window-meta.json` → next `tmux attach` fires
`client-attached` hook → `restore-window-meta.sh` reads JSON →
loops `tmux list-windows -a -F …` → for each matching entry,
`tmux set-option -w -t main:<idx> @win_glyph <g>` and
`@win_glyph_color <hex>` → `window-status-format` ternary in
`tmux/tmux.display.conf:67-68` renders colored glyph prefix on the
tab (status line refreshes within 1s because
`status-interval 1` is set in `tmux.display.conf:23`).

### Error propagation

- Malformed JSON → jq error to stderr; tmux hook completes, no
  options set, tabs render without glyph. Not fatal.
- Session-name mismatch (VPS session not `main`) → `.[$s][$w] // empty`
  returns empty, loop skips that iteration. Tab renders without glyph.
- Window-name mismatch (e.g. a new `db` window appears) → same as
  above; no error.
- Missing jq → restore script exits silently at line 13. No effect.
  Not reachable on VPS (jq installed).

### State lifecycle

- Symlink persists until next `./install` re-applies it or operator
  removes it.
- No auto-hook invokes `save-window-meta.sh`; the script is called
  only by the Mac skill with explicit CLI args. Seed file stays
  pristine on VPS. (Cross-checked with
  `grep -rn save-window-meta tmux/` during research — only the
  shebang + the skill's SKILL.md reference it.)
- If a future operator installs Claude Code on the VPS and runs the
  namer skill, `save-window-meta.sh` would write through the symlink
  to the repo file (drift). Explicitly out of scope — revisit
  approach C from the brainstorm if that future arrives.

### Integration test scenarios

1. **Dry-run preserves mutation-free guarantee on fresh HOME.** Run
   the fresh-HOME recipe from `CLAUDE.md:158-164`; expect one
   "Would create symlink" line for the new entry and the post-run
   `find | wc -l` to print `0`.
2. **VPS symlink resolves correctly post-install:**
   ```bash
   ssh root@openclaw-prod \
     'readlink ~/.config/tmux/window-meta.json'
   # expected: /root/.dotfiles/tmux/window-meta.linux.json
   ```
3. **Hook applies options on fresh attach:**
   ```bash
   ssh root@openclaw-prod '
     tmux detach-client -a 2>/dev/null
     tmux new-session -t main \; detach
     for w in ops logs openclaw tui; do
       printf "%-10s " "$w"
       tmux show-option -wv -t "main:$w" @win_glyph 2>/dev/null
     done
   '
   # expected: ⚙ ≡ 🦀 ▤ — one per line
   ```
4. **Darwin untouched:** run a Mac-side dry-run; confirm no diff
   would be produced for `~/.config/tmux/window-meta.json`.

## Acceptance Criteria

- [ ] `tmux/window-meta.linux.json` exists with the exact schema in
      Proposed Solution
- [ ] `install-linux.conf.yaml` adds exactly one new line under the
      link block at 80-88; no other edits
- [ ] `install.conf.yaml` (Darwin) has zero diff
- [ ] Dry-run against fresh `$HOME` produces zero mutations and
      emits "Would create symlink" for the new entry
- [ ] After `./install` on VPS and a fresh attach to session `main`:
      `tmux show-option -wv -t main:ops @win_glyph` prints `⚙`,
      `…main:logs` prints `≡`, `…main:openclaw` prints `🦀`,
      `…main:tui` prints `▤`
- [ ] Visual check: inner VPS tmux bar renders
      `main 1:⚙ ops 2:≡ logs 3:🦀 openclaw 4:▤ tui` with glyph
      color matching the palette hex
- [ ] Mac live `~/.config/tmux/window-meta.json` unchanged before
      and after running `./install --dry-run` on Mac

## Success Metrics

- One-time visual change: operator sees colored glyph tabs in VPS
  tmux after one `./install` + reattach cycle.
- No Mac regression: skill-driven sessions continue to write
  freely to the Mac's live sidecar.
- Rollback reversible in under a minute (one `git revert` +
  `./install`).

## Dependencies & Risks

**Dependencies:**
- Dotbot v1.24.1 (vendored submodule; already pinned)
- `jq` on VPS (installed by `helpers/install_packages.sh:23`)
- UTF-8 terminal on both endpoints (iTerm2 on Mac, SSH default UTF-8)

**Risks (ordered by likelihood × impact):**

1. **Persistent session won't auto-pick up** (medium likelihood, low
   impact). If the VPS's `main` session is already attached when
   `./install` runs, the new symlink exists but options aren't set
   until a client reattaches. Mitigation documented: `tmux detach-client -a`
   then attach, OR `bash ~/.config/tmux/scripts/restore-window-meta.sh`
   once by hand.
2. **Session-name or window-name drift** (low likelihood, low
   impact). If the VPS session is renamed away from `main` or a
   window is renamed, matching entries go unused and tabs fall back
   to no-glyph rendering. Silent, no error. Update the seed file if
   it happens.
3. **Precedent migration trigger** (process, not operational). The
   `.linux.json` suffix is fine for one file. Rule for future:
   **the second host-scoped state file is the moment to migrate
   both into `hosts/<os>/`** — not now.
4. **Hypothetical write-through drift** (very low likelihood,
   medium impact if it occurs). If Claude Code is later installed
   on VPS and someone runs the namer skill there, `save-window-meta.sh`
   writes through the symlink and mutates the committed repo file.
   Mitigation: don't install the skill on VPS; if the need arises,
   this is the trigger to revisit Approach C from the brainstorm.

**Rollback:** `git revert <sha>` → `./install` on VPS → symlink
removed; next reattach leaves `@win_glyph` options set from the
previous session (they persist in the tmux server until server
restart, which is the desired quiet rollback — nothing user-visible
regresses until reattach forces a redraw). For a hard reset:
`ssh root@openclaw-prod 'for w in ops logs openclaw tui; do tmux set-option -uw -t main:$w @win_glyph; tmux set-option -uw -t main:$w @win_glyph_color; done'`.

## Implementation Steps (execution order)

1. Write `tmux/window-meta.linux.json` with the JSON above.
2. Edit `install-linux.conf.yaml`: add
   `~/.config/tmux/window-meta.json: tmux/window-meta.linux.json`
   to the existing link block (line 82 area).
3. Validate JSON locally: `jq . tmux/window-meta.linux.json`.
4. Dry-run against fresh HOME (Integration test 1 above). Confirm
   zero mutations.
5. Ask user to test before committing (per user preference).
6. Commit. Conventional title:
   `feat: seed VPS tmux window glyph metadata`.
7. Push. Trigger VPS sync with dry-run first:
   `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true`.
   Review Actions step summary.
8. Re-run with `-f dry_run=false` when summary looks clean.
9. SSH to VPS, run Integration tests 2 and 3 above.
10. Visually verify the inner status bar after reattach.
11. Close any related GitHub issue (per user workflow memory).

## Sources & References

### Origin

- **Brainstorm:** `docs/brainstorms/2026-04-17-vps-tmux-glyph-treatment-brainstorm.md`
  — carried forward: (a) Approach A over B/C (static seed vs. inline
  hook vs. SSH-aware skill), (b) locked glyph/palette mapping, (c)
  drift analysis clearing the symlink-target-pristine assumption,
  (d) the brainstorm's single open question (host-level vs.
  in-container tmux) resolved by research — host-level, runs as
  root from `/root/.dotfiles` per
  `docs/solutions/cross-machine/vps-dotfiles-target.md:56,181`.

### Internal code references

- `tmux/scripts/restore-window-meta.sh:12-26` — JSON schema, no-op
  guards, target syntax
- `tmux/scripts/save-window-meta.sh` — confirmed no auto-hook
  invocation (grep over tmux/ returned only docstring references)
- `tmux/tmux.display.conf:23,67-68` — `status-interval 1`, glyph
  ternary in `window-status-format`
- `tmux/tmux.general.conf:81` — `client-attached` hook wiring
- `install-linux.conf.yaml:80-88` — the link block to extend
- `install.conf.yaml:69-83` — Darwin block, verified unchanged
- `claude/skills/tmux-window-namer/references/palettes.md:12-20` —
  palette hex source of truth
- `helpers/install_packages.sh:23` — `jq` install confirmation

### Institutional learnings

- `docs/solutions/cross-machine/vps-dotfiles-target.md` — VPS runs
  tmux on host, `./install` invocation pattern, persistent-session
  caveat (lines 265-268), dry-run verification recipe (309-312)
- `docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md`
  — confirms native `--dry-run` support is in v1.24.1

### Conventions (CLAUDE.md)

- `CLAUDE.md:119-132` — tmux-window-namer skill architecture,
  palette discipline, JSON sidecar contract
- `CLAUDE.md:138-164` — `--dry-run` guarantees and verification
  recipe
