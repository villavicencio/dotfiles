---
module: tmux
date: 2026-05-01
problem_type: best_practice
component: tooling
severity: low
applies_when:
  - "Designing tmux status-bar chrome (pills, gaps, separators) on iTerm2 with window transparency enabled"
  - "Trying to fake sub-row vertical spacing using Unicode half-block or block-element glyphs (U+2580 ▀, U+2584 ▄, U+2581 ▁, U+2594 ▔)"
  - "Stacking nested tmux instances (outer + inner via SSH) where status bars touch and a visual gap is desired"
  - "Diagnosing why pill rounded caps look brighter or more saturated than the pill body in a transparent terminal"
tags:
  - tmux
  - iterm
  - terminal
  - rendering
  - transparency
  - status-bar
  - unicode
related_components:
  - development_workflow
---

# iTerm transparency only blends backgrounds — foreground glyphs render opaque

## Context

While polishing the nested-tmux status bars (outer Mac tmux + inner VPS tmux via SSH), the goal was to shrink the visual gap between the two bars to roughly half a row — close enough to read as a single grouping, but not flush. The natural lever is `set -g status 2` plus a `status-format[1]` filler row, which gives a full-row gap; the attempted half-row trick was to fill that filler row with U+2580 (`▀`) glyphs coloured to extend the bar's tone, betting that iTerm window transparency would let the lower half of each cell show through. It produced a solid opaque stripe instead, prompting the rule below.

## Guidance

In a transparent terminal, you can only choose **integer-row gaps**: 0 rows (`status 1`), 1 row (`status 2` with a blank `status-format[1]`), 2 rows, and so on. Sub-row gaps achieved by half-block glyphs (`▀ ▄ ▔ ▁`) do not work — the glyph is a foreground draw and is rendered fully opaque, so any "transparent half" of the cell is in fact a coloured half plus an opaque half, i.e. a visible shelf.

The same mechanism produces a corollary artifact: **rounded pill caps** (e.g. U+E0B6 / U+E0B4 drawn as `fg=pill-color, bg=default`) appear brighter and more saturated than the pill body when transparency is on, because the cap is an opaque fg glyph while the body is bg-tinted and gets blended with the desktop behind. If you need sub-row texture or perfectly cap-matched pills, the only fix is to disable iTerm window transparency — there is no terminal-side workaround.

## Why This Matters

Terminals render in a fixed cell grid where each cell has an integer row height; you cannot address half a cell. Per cell the renderer composites two layers: a background fill, then a foreground glyph drawn on top of it. iTerm's window transparency multiplies only the background-fill alpha against the window-behind; the foreground glyph rasterises at full opacity onto the already-blended background. So a half-block glyph like `▀` doesn't expose terminal transparency in its lower half — its lower half is simply the cell's bg colour (which *is* transparent), while its upper half is the fg colour painted opaquely on top. The "half" in the glyph is a foreground/background split inside one fully-opaque draw, not a transparency split. Any UI that relies on a fg glyph to feel "lighter" or "partially see-through" will fail for the same reason.

## When to Apply

Reach for this rule whenever someone proposes:

- "Use `▀`/`▄`/`▔`/`▁` to make a half-row gap / thin separator / sub-cell texture in a terminal status bar"
- "Why do my pill caps look brighter than the pill body in iTerm?" (or the same pattern in WezTerm / Alacritty / Kitty with window opacity < 1.0)
- "Can we make this status line *almost* blend into the next one?"
- Any "subtle ghost row / faded divider" idea in a terminal UI under window transparency
- Cross-checking before adjusting `tmux/tmux.display.conf`'s status row count or cap glyphs

If the surrounding terminal has transparency enabled, assume any fg-glyph trick will read as opaque and adjust the design.

## Examples

**Bad** — half-block filler row, intended as a "half gap", actually a solid shelf:

```tmux
# tmux/tmux.display.conf
set -g status 2
set -g status-position bottom
# Attempt: extend bar tone into the upper half of the filler row,
# let lower half show desktop through iTerm transparency.
set -g status-format[1] "#[fg=#3E4451,bg=default]▀▀▀▀▀▀▀▀▀▀▀▀▀▀…"
```

Result with iTerm transparency on: a solid `#3E4451` horizontal stripe across the full window width — every `▀` is an opaque fg draw.

**Good** — pick an integer-row gap and accept it:

```tmux
# tmux/tmux.display.conf
# Full-row gap (clean, transparency-safe):
set -g status 2
set -g status-format[1] " "

# Or zero gap:
set -g status 1
```

**Corollary — rounded pill caps under transparency:**

```tmux
# Pill body has a transparency-blended background; caps are opaque fg
# glyphs. Under iTerm transparency the caps read as brighter / more
# saturated than the body. Options:
#   1. Disable iTerm window transparency (only true fix)
#   2. Drop the rounded caps and use a flat block
#   3. Accept the mismatch as an aesthetic tax of transparency
set -g status-left "#[fg=#5FAFFF,bg=default]#[fg=#000,bg=#5FAFFF] session #[fg=#5FAFFF,bg=default]"
```

## Related

- [`docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md`](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md) — different layer, similar "what looks like a font/render bug isn't" pattern. PUA glyphs get stripped *before* they ever reach the file (Bash argv / Edit / Write filtering); this learning is about glyphs that are correctly written but rendered opaquely by the terminal.
