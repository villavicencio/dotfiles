# Curated Palettes (One Dark harmonized)

These are the **only** colors the tmux-window-namer skill may use. Never
generate freeform hex codes — pick from this list so the status bar stays
visually coherent with the rest of the One Dark theme.

Each palette has a **primary** hex (used for glyph and/or title) and a
set of **vibe tags** to guide matching against predicted window context.

| Name   | Primary   | Vibe tags |
|--------|-----------|-----------|
| ember  | `#D97757` | warm, active, AI, Claude, creative, writing |
| ocean  | `#56B6C2` | data, API, infra, cool, sync, pipelines |
| sunset | `#E5C07B` | attention, docs, warning-adjacent, notes, journaling |
| forest | `#98C379` | growth, backend, go, success, green-field, gardens |
| rose   | `#C98389` | alert, personal, design, love, art |
| lilac  | `#C678DD` | ML, analysis, research, dreams, magic |
| sky    | `#7DACD3` | frontend, web, default-plus, calm, cloud |
| smoke  | `#4B5263` | background, archival, idle, monitoring, quiet |

## Pairing recipe for title vs. glyph

For a given palette with primary hex **H**, the skill should offer two pairings:

1. **Monochrome** — both glyph and title use H. Bold, confident.
   - `glyph_color = H`
   - `title_color = H`

2. **Subdued** — colored glyph, neutral title. Easier to read at a glance.
   - `glyph_color = H`
   - `title_color = #ABB2BF` (default One Dark foreground)

Alternate between these two pairings across the 10 variations so the user
sees both options for each palette choice.

## Neutrals (for fallback or "default look")

These are reserved for the skill to use as the `title_color` in subdued
variants — never as the primary glyph color:

- `#ABB2BF` — default foreground
- `#4B5263` — dim gray (same as inactive tab default)
