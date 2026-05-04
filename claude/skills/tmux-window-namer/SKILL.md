---
name: tmux-window-namer
description: Rename and colorize tmux windows with a glyph and curated palette. Use when the user wants to style a tmux tab, pick an emoji or Nerd Font icon for a window, offer variations on a window name, or change a tab's colors. Triggers on phrases like "name this window", "rename window N", "color this tab", "give this tab an icon", "suggest tab names".
allowed-tools: Bash(tmux *), Bash(jq *), Bash(cat *), Bash(ls *), Bash(basename *), Bash(git *), Read
---

# tmux-window-namer

Style tmux windows with a glyph, a title, and a glyph color drawn from a
curated palette. Title text always uses default tmux colors (dim on inactive
tabs, bright on active) — only the glyph carries palette color. Persists
the result across tmux server restarts via a JSON sidecar read by a
`client-attached` hook.

## When the user invokes you

Figure out which of these three modes applies:

| Mode | Trigger | Action |
|---|---|---|
| **Suggest** | "name this window", "suggest tab names", "rename window 3" (no specifics) | Predict context → offer 10 variations → user picks → apply |
| **Direct** | "rename window 2 to   Backend in ocean" (has glyph + title + palette) | Skip suggestions, apply immediately |
| **Tweak** | "make window 3 use the forest palette instead" (existing styling, partial change) | Read current options → modify only what's asked → apply |

## Step 1 — Resolve the target window

User may specify:

- Nothing → default to **current window** (no `-t` flag)
- An index: "window 2" → `-t :2` (**note the leading colon** — see below)
- A fuzzy name: "the Dataworks tab", "the Eagle one" → search `tmux list-windows -a`

### tmux target-syntax gotcha

**Never use `-t N` (bare number) with `set-option -w` or `rename-window`.**
A bare number can be silently interpreted as "the current window" by tmux
when the literal string "N" doesn't match a window name. You will end up
modifying the wrong tab.

Always use one of these explicit forms:

- `-t :N` — window at index N in the current session (leading colon is required)
- `-t <session>:N` — window at index N in a specific session
- `-t @ID` — window by its stable ID (e.g., `@3`), which you can get from
  `tmux list-windows -a -F '#{session_name}:#{window_id} #{window_name}'`

When resolving a user-specified index in the skill, **always** prefix it
with `:` before passing it to tmux.

List windows to resolve fuzzy names or confirm target:

```bash
tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'
```

If fuzzy match is ambiguous, ask the user which one they meant before proceeding.

## Step 2 — Gather context for prediction (Suggest mode only)

Run these in **one parallel batch** to minimize latency:

```bash
# Core tmux facts
tmux display-message -p -t "$target" '#{pane_current_command}|#{pane_current_path}|#{window_name}'

# Project marker sniffs (only if pane_current_path is a dir we can read)
ls -1a "<pane_current_path>" 2>/dev/null | head -30

# Git context if it's a repo
cd "<pane_current_path>" 2>/dev/null && git remote -v 2>/dev/null | head -1
cd "<pane_current_path>" 2>/dev/null && git branch --show-current 2>/dev/null
```

From these, synthesize a **one-line prediction** of what the window is
about. Examples:

- `pane_current_command=claude path=.../dotfiles` → "Claude Code session in the dotfiles repo"
- `pane_current_command=nvim path=.../every-site` + `Gemfile` + `app/` → "Rails backend for the Every site"
- `pane_current_command=psql` → "postgres client"
- `pane_current_command=btop` → "system monitor"

## Step 3 — Pick glyph + palette candidates

Read the references:

- `references/palettes.md` — the **only** palettes you may use. Never invent hex codes.
- `references/glyphs.md` — curated glyph categories.

Based on the prediction, select:

- **5 candidate glyphs** — favor the categories that match context (e.g., `code` + `shell` for a dev window, `data` + `ops` for a DB/infra window). Mix emoji and Nerd Font icons.
- **2 candidate palettes** — pick the two palettes whose vibe tags best match the context.

## Step 4 — Present variations via **live preview** on the actual tab

**Important:** the Claude Code TUI cannot render Nerd Font PUA glyphs or
ANSI colors in chat or in `AskUserQuestion` previews. The only place where
both render correctly is the **actual tmux tab**, which uses the user's
terminal font. So the skill presents variations by **applying each one
live to the target window** and asking the user to decide.

### Visual stand-ins for the wizard UI

The Claude Code TUI and `AskUserQuestion` previews can't render:
- Nerd Font PUA glyphs (they come out blank)
- ANSI 24-bit colors (stripped)

They **can** render:
- Standard emojis (⚙️ 🍎 💻 🏠 🔥 etc.)
- Colored square emojis as rough palette indicators: 🟧 ember, 🟦 sky,
  🟨 sunset, 🟩 forest, 🟥 rose, 🟪 lilac, ⬛ smoke, ⬜ neutral-subdued

So in the wizard: use an **emoji stand-in** for the Nerd Font glyph and
**colored squares** for the palette colors. The actual tmux tab will show
the real Nerd Font glyph and real hex colors, which the user sees alongside
the wizard — that's the true preview.

Stand-in map for common glyphs:

| Nerd Font | Codepoint | Emoji stand-in |
|---|---|---|
| nf-fa-cog          | `\uf013` | ⚙️  |
| nf-fa-apple        | `\uf179` | 🍎 |
| nf-fa-terminal     | `\uf120` | 💻 |
| nf-fa-wrench       | `\uf0ad` | 🔧 |
| nf-fa-home         | `\uf015` | 🏠 |
| nf-fa-database     | `\uf1c0` | 🗄️  |
| nf-fa-globe        | `\uf0ac` | 🌐 |
| nf-fa-book         | `\uf02d` | 📖 |
| nf-fa-cloud        | `\uf0c2` | ☁️  |
| nf-fa-rocket       | `\uf135` | 🚀 |
| nf-fa-flask        | `\uf0c3` | 🧪 |
| nf-fa-user         | `\uf007` | 👤 |
| nf-fa-heart        | `\uf004` | ❤️  |
| nf-fa-lightbulb_o  | `\uf0eb` | 💡 |

### Iteration flow

1. **Snapshot** the window's current state (if any) so it can be restored:
   ```bash
   orig_glyph=$(tmux show-options -wv -t "$target" @win_glyph 2>/dev/null || true)
   orig_gc=$(tmux show-options -wv -t "$target" @win_glyph_color 2>/dev/null || true)
   orig_name=$(tmux display-message -p -t "$target" '#{window_name}')
   ```

2. **Generate 4 candidate variations** (glyph × palette) as an internal
   list. These are not shown in chat — they are applied in sequence.

3. For each candidate, loop:
   - Apply the candidate to the window (rename + set options).
   - Ask the user via `AskUserQuestion`. Each option **must include a
     `preview` field** with a monospace block showing the stand-in glyph,
     colored squares for the palette, and the hex codes. Example preview:
     ```
     ⚙️  Dotfiles

     glyph:       nf-fa-cog (⚙️)
     palette:     ember 🟧
     glyph_color: #D97757
     ```
   - Options:
     - "Keep this one"
     - "Try the next variation"
     - "Cancel and restore" (reverts to snapshot)
   - In the question text, name the candidate plainly:
     `"Variation 2/4: {glyph_name} in {palette}. Check your tab."`
   - **Header** (the chip at the top of the card) should be a short
     **neutral** label like `Tab style` or `Variation 2`. Do **not** use
     action-implying phrases like "Keep or next?" — the header is not
     interactive and that wording confuses users into thinking it is.
   - If "Keep" → go to Step 5 (persist).
   - If "Try next" → apply the next candidate, re-ask.
   - If "Show me the full list" → print a plain-text numbered list of all
     remaining candidates (glyph name + palette + hex) so the user
     can jump to a specific one by number in chat. Wait for reply, jump there.
   - If user gives a custom tweak in "Other" → apply and re-ask.

4. If the user exhausts all candidates without choosing, **restore** the
   snapshot and ask if they want a new round with different palettes/glyphs.

### Candidate generation

Pick **4 strong variations** that cover visual variety:

- 2 different glyphs × 2 different palettes.
- Bias toward Nerd Font glyphs from `references/glyphs.md`. One emoji is fine
  if a strong one fits the context.

### Glyph selection — prefer Nerd Fonts

The user's terminal renders a Nerd Font, so **bias toward Nerd Font glyphs**
from `references/glyphs.md`. Mix in 1 emoji for variety if a strong one
matches the context, but 3 of the 4 primary candidates should be Nerd Font
icons.

## Step 5 — Apply the chosen variation

**Important:** The Claude Code Bash tool strips private-use-area (PUA)
characters — most Nerd Font glyphs live in this range — from command-line
arguments. To reliably set a Nerd Font glyph on a tmux option, invoke
`tmux set-option` via `python3` with the glyph written as a `\uXXXX` escape:

```bash
python3 -c "
import subprocess
glyph='\uFXXX'  # resolve codepoint from references/glyphs.md
target='<target>'  # e.g. '' for current, ':2' for window 2
subprocess.run(['tmux','rename-window','-t',target,'<title>'], check=True)
subprocess.run(['tmux','set-option','-w','-t',target,'@win_glyph',glyph], check=True)
subprocess.run(['tmux','set-option','-w','-t',target,'@win_glyph_color','<glyph_color>'], check=True)
"
```

Emojis (standard Unicode, outside PUA) can be passed directly in bash, but
for uniform reliability **always use the python wrapper** for the glyph.

After applying, persist to the sidecar (this is safe to run in plain bash
because `bash` passes argv through without stripping):

```bash
session=$(tmux display-message -p -t "$target" '#{session_name}')
title=$(tmux display-message -p -t "$target" '#{window_name}')
glyph=$(tmux show-options -wv -t "$target" @win_glyph)
glyph_color=$(tmux show-options -wv -t "$target" @win_glyph_color)

bash "$HOME/.config/tmux/scripts/save-window-meta.sh" \
  "$session" "$title" "$glyph" "$glyph_color"
```

Confirm visually: "Applied. Window <target> is now <glyph> <title> in <palette>."

## Direct mode shortcut

If the user's request already specifies glyph + title + palette (or enough
of them), skip Steps 2–4. Resolve the palette name to its hex (`references/palettes.md`),
fill any blanks with sensible defaults, apply via Step 5.

Example: "rename window 2 to   Backend in ocean" → glyph ``,
title "Backend", palette ocean (`#56B6C2`).

## Tweak mode

Read current state before modifying:

```bash
tmux show-options -wv -t "$target" @win_glyph 2>/dev/null
tmux show-options -wv -t "$target" @win_glyph_color 2>/dev/null
tmux display-message -p -t "$target" '#{window_name}'
```

Change only what the user asked for. Persist the full tuple (Step 5's save
script rewrites the whole entry, so pass all values).

## Constraints

- **Only use hex codes from `references/palettes.md`.** Never improvise.
- Prefer glyphs from `references/glyphs.md` but feel free to pick any emoji
  or Nerd Font glyph that genuinely fits the context.
- Keep titles short (1–3 words). Long titles get truncated in narrow panes.
- Respect existing user preferences: if a window already has a 🦞 glyph and
  the user asks for "a different color", keep the lobster.
- Never touch windows other than the resolved target.
- If the user runs this outside tmux, say so and exit — there's nothing to rename.
