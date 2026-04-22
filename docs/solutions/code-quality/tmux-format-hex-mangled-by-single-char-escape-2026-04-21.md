---
title: "tmux format: bare hex color inside #{?...} ternary silently mangled by single-char escapes"
date: 2026-04-21
category: code-quality
tags:
  - tmux
  - format-strings
  - status-line
  - escaping
  - hex-colors
  - ternary
  - gotcha
severity: Low
component: "tmux format-string parser; tmux/tmux.display.conf status-left block"
symptoms:
  - tmux status-line pill renders with no background or foreground color after adding a conditional (#{?...}) around bg/fg
  - No error on `tmux source-file`; the pill is just colorless
  - `tmux display-message -p '<string>'` shows the expanded style attribute with a truncated hex (e.g. `fg=*FFFFF` instead of `fg=#FFFFFF`)
  - Only hex colors whose second character is `F`, `D`, `S`, `H`, etc. trip the bug — colors starting with other chars look fine
problem_type: ui_bug
module: tmux-config
---

## Summary

While wiring a conditional session-pill color into `tmux/tmux.display.conf`
(make `VPS` sage green and `LOCAL` blue via `#{?#{==:#S,vps},...,...}`), the
pill rendered **colorless** after `tmux source-file`. The ternary itself was
fine and the style attribute `#[...]` was fine — but the hex color inside a
ternary branch got its leading character consumed by tmux's single-char format
escapes (`#F` = window flags, `#D` = pane id, `#S` = session name, `#H` = host,
etc.), so `#FFFFFF` became `*FFFFF` before the style engine parsed it. The
style engine silently dropped the invalid color, leaving the pill unstyled.

Fix: **double-escape every `#` in hex colors inside ternary branches** (`##FFFFFF`).
One expansion pass turns `##` into a literal `#`, yielding a valid hex color
for the style engine.

## Root cause

tmux format strings are expanded once before the style engine (`#[...]`) parses
attributes. During that expansion, single-char escapes like `#S`, `#H`, `#D`,
`#F`, `#T`, `#I`, `#P`, `#W` are resolved inline — **including inside ternary
branches**.

`#FFFFFF` starts with `#F`, which is the documented window-flags escape
(rendering as `*` for the active window, `-` for last, etc., or empty). So
the parser treats the hex color as `#F` (escape) + `FFFFF` (literal), mangling
the value to `*FFFFF` before the style engine ever sees it as a color.

The documented escapes `##` → `#`, `#,` → literal `,`, and `#}` → literal `}`
are in `man tmux`, but the interaction with single-char format escapes inside
**ternary branches** is implicit — the man page doesn't call it out.

## Diagnosis

`tmux display-message -p '<string>'` is the authoritative diagnostic. It
expands the format string and returns the post-expansion text before the style
engine consumes it. The bug reveals itself immediately:

```bash
# Reproduce the mangling
tmux display-message -p \
  '#[bg=#{?#{==:#S,vps},#98C379,#2563EB}#,fg=#{?#{==:#S,vps},#031B21,#FFFFFF}#,bold] PILL #[default]'
# -> #[bg=#2563EB,fg=*FFFFF,bold] PILL #[default]
#                      ^^^^^^^ mangled — #F consumed as window-flags escape

# Confirm the fix with ##-escaped hex
tmux display-message -p \
  '#[bg=#{?#{==:#S,vps},##98C379,##2563EB}#,fg=#{?#{==:#S,vps},##031B21,##FFFFFF}#,bold] PILL #[default]'
# -> #[bg=#2563EB,fg=#FFFFFF,bold] PILL #[default]
#    clean — style engine will render this correctly
```

`#2563EB` survived because `#2` isn't a format escape. `#98C379` would
actually survive too (`#9` isn't an escape either), so bugs like this can
lurk partially — only the hex literals starting with a letter that collides
with an escape are visibly broken. This makes the failure mode intermittent-
looking across a set of conditional colors.

## Solution

In `tmux/tmux.display.conf` (around the `set -g status-left` block), any hex
color placed inside a `#{?...}` ternary branch must be written with `##`:

```tmux
# WRONG — bare hex inside the ternary; #F/#D/#S collisions consume chars
#[bg=#{?#{==:#S,vps},#98C379,#2563EB}#,fg=#{?#{==:#S,vps},#031B21,#FFFFFF}#,bold]

# RIGHT — ## in every hex color inside the ternary
#[bg=#{?#{==:#S,vps},##98C379,##2563EB}#,fg=#{?#{==:#S,vps},##031B21,##FFFFFF}#,bold]
```

The fix shipped in commit `ba18518` on master, along with an inline comment in
the config block documenting the `##` rule for the next editor.

## Why this works

`##` is tmux's documented escape for a literal `#`. The first format-expansion
pass rewrites `##FFFFFF` → `#FFFFFF`. At that point the ternary has already
resolved, so the outer `#[...]` attribute block now contains a well-formed
hex color string. The style engine parses `#FFFFFF` as white and applies it.
No further expansion pass runs over the resolved color, so there's no second
chance for `#F` to collide with the window-flags escape.

Colors **outside** a ternary (e.g., `#[bg=#2563EB,fg=#FFFFFF,bold]` written
literally) do not need `##` — the style engine consumes them directly without
going through an extra expansion pass. The rule is specifically for hex
colors whose text passes through `#{?...}` branch resolution.

## Prevention

1. **Every hex color inside a `#{?...}` ternary must be `##RRGGBB`, not `#RRGGBB`.**
   Covers `#{?cond,A,B}` where `A` or `B` contains a literal hex color, and any
   `#[bg=...,fg=...]` whose color value is produced by a ternary.

2. **Add an inline comment** next to any conditional-color block in a tmux
   config. The current `tmux/tmux.display.conf` has:

   > Hex colors inside a `#{?...}` ternary MUST use `##` (e.g. `##FFFFFF`) rather than a
   > bare `#` (`#FFFFFF`). Letters F, D, S, H, etc. are single-char format escapes
   > (`#F` = window flags, `#D` = pane id, `#S` = session name, …), and when a ternary
   > branch contains a bare hex color like `#FFFFFF` the parser consumes the leading
   > `#F` and mangles the color to `*FFFFF`. Escaping as `##FFFFFF` emits a literal `#`
   > after one expansion pass, which the style engine then reads as a hex color.

3. **Diagnostic shortcut.** When a tmux pill or segment suddenly renders
   colorless after a config change, suspect hex-in-ternary escape first. Run
   `tmux display-message -p '<format-string>'` on the offending block to see
   the expanded output; a mangled hex (e.g. `*FFFFF`) is the smoking gun.

4. **Full list of letters to watch.** The single-char format escapes that
   collide with hex digits or hex-compatible letters are: `#F` (flags),
   `#D` (pane id), `#S` (session), `#H` (host short), `#T` (pane title),
   `#I` (window index), `#P` (pane index), `#W` (window name). Any hex color
   starting with those letters after `#` is a candidate for silent mangling.

## Related

- [`claude-code-bash-tool-strips-pua-glyphs.md`](./claude-code-bash-tool-strips-pua-glyphs.md)
  — same meta-pattern: a parser silently consumes a character class before
  the literal payload reaches its consumer. Different parser (Claude Code
  Bash/Write argv), different char class (Unicode PUA), but the mental
  model is identical.
- [`tmux-set-option-bare-index-target-gotcha.md`](./tmux-set-option-bare-index-target-gotcha.md)
  — another tmux-config gotcha with a silent wrong-target failure mode. Same
  class of "command ran, exit 0, wrong effect" bug; adjacent file territory
  (both concern tmux configuration of the same subsystem).
- [`../runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md`](../runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md)
  — touches the neighboring `window-status-format` ternary in the same
  `tmux/tmux.display.conf` file. Different failure mode (async race on
  `@claude_status`), but the glyph-rendering ternary architecture in that
  doc is the same structural pattern used in the status-left pill that
  triggered this bug.
