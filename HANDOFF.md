# HANDOFF — 2026-04-08, late evening

## What We Built

Three related features, all shipped to master and pushed.

### 1. Claude Code tmux tab attention indicator (merged via `4c03135`)
- **New:** `claude/hooks/tmux-attention.sh` — per-window background spinner + "waiting" marker driven by Claude Code hooks, written to a window-scoped `@claude_status` tmux user option.
- **New hooks in `claude/settings.json`:** `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → spinner; `PermissionRequest` → waiting (yellow  warning glyph); `Stop` → clear.
- **Spinner:** backgrounded `nohup bash -c '…'` tagged `claude-spinner-marker-<pane>`, sentinel file at `$TMPDIR/claude-spinner-<pane>.alive`, parent-PID watch, max-iterations safety cap. Fully detached stdio so hooks don't block Claude's UI.
- **Frames:** `· ✢ ✳ ∗ ✻ ✽` in Anthropic-orange `#D97757`, 150ms cycle.
- **Format string:** `tmux/tmux.display.conf` extended with a 3-tier ternary (waiting > spinner > no icon).

### 2. `tmux-window-namer` Claude skill (merged via `4688f47`)
- **New:** `claude/skills/tmux-window-namer/SKILL.md` + `references/palettes.md` + `references/glyphs.md`. Invoked by agent description matching — user says "name this window" / "rename window 3" / "make window 2 forest" and the skill fires.
- **State model:** three new per-window user options — `@win_glyph`, `@win_glyph_color`, `@win_title_color` — read by an extended ternary in `tmux/tmux.display.conf`. Final priority: waiting > spinner > `@win_glyph` > no icon.
- **Layout:** ` #I: <icon> #W ` — glyph goes *between* the index and the title.
- **Curated palettes only** (`references/palettes.md`): ember, ocean, sunset, forest, rose, lilac, sky, smoke. Skill is instructed never to invent hex codes.
- **Persistence:** JSON sidecar `~/.config/tmux/window-meta.json`, written by `tmux/scripts/save-window-meta.sh` and re-applied on every client attach via `set-hook -g client-attached 'run-shell "$XDG_CONFIG_HOME/tmux/scripts/restore-window-meta.sh"'` in `tmux/tmux.general.conf`.
- **Wizard flow:** live-preview iteration — applies each candidate to the actual tab, asks via `AskUserQuestion` with emoji stand-ins (`⚙️` for nf-fa-cog, etc.) because the Claude Code TUI cannot render Nerd Font PUA glyphs or ANSI colors.

### 3. Two post-merge bug fixes
- **`1324b36`** — Removed the `Notification` hook from `claude/settings.json`. It was firing on every turn-end (not just permission prompts), racing with `Stop`, and leaving the yellow warning glyph stuck forever. `PermissionRequest` alone is the correct attention signal.
- **`719836a` + `c0a3a0f`** — `tmux set-option -w -t N` (bare integer target) silently resolves to the *current* window instead of window index N. Every "apply to window 2" command was actually hitting window 4. Documented in `claude/skills/tmux-window-namer/SKILL.md` Step 1 and fully captured in `docs/solutions/code-quality/tmux-set-option-bare-index-target-gotcha.md`.

### Earlier in the session (pre-branch work, `b3c9261` + `6e1df9c`)
- Improved `claude/commands/pickup.md` with a CE-artifact scan step.
- Expanded `claude/settings.json` allow-list (brew uninstall, npm list/view/uninstall, `claude *`, curl `-fsSL`).
- Committed accumulated iTerm2 plist drift.

## Decisions Made

- **Per-pane vs per-window scoping:** window-scoped for both the Claude indicator and the custom glyphs. Two Claudes in split panes of the same window will fight over `@claude_status` and `@win_*`. Explicitly accepted as v1 limitation.
- **Spinner liveness signals (defense in depth):** sentinel file (primary), parent-PID watch (fires within 150ms if Claude dies), `pkill -f claude-spinner-marker` (nuclear), 5-minute max-iterations cap. No `SessionEnd` hook exists in Claude Code, so the parent-PID watch is the only reliable way to detect a crashed session; `SessionStart → clear` handles defensive cleanup on the next launch.
- **No stdout/stderr on backgrounded spinner:** `nohup bash -c '…' </dev/null >/dev/null 2>&1 &` — critical fix for the "Claude hangs on every tool call" regression. Inheriting the hook's stdout pipe blocks Claude's reader.
- **Hook wiring final form:** `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → spinner; `PermissionRequest` → waiting; `Stop` → clear. `Notification` removed — it fires too broadly. `PostToolUse` → spinner restarts the animation after approved tool calls (no hook fires on permission-grant itself).
- **Curated palettes over freeform hex:** the skill may only use the 8 hex codes in `references/palettes.md`. Keeps the status bar coherent with One Dark.
- **Separate glyph vs title colors:** two independent `@win_*_color` options. Supports both monochrome (same color both) and subdued (colored glyph + neutral title) pairings per palette.
- **Wizard UX — live preview on the real tab, not in the picker card:** the Claude Code TUI can't render Nerd Font PUA glyphs or ANSI colors, so the real preview is the tmux tab itself. The `AskUserQuestion` card uses emoji stand-ins (`⚙️`, `🍎`, `💻`, `🏠`…) and colored-square emojis (`🟧 🟦 🟩 🟪 🟨`) as rough approximations — good enough to disambiguate options after the user has already seen the real thing on the tab.
- **Always use `-t :N` or `-t @ID`, never `-t N`:** tmux target-syntax gotcha is now a documented skill rule.
- **Glyphs must be set via `python3 -c "...\uXXXX..."`:** the Claude Code Bash tool strips PUA characters from argv. Python string literals with `\uXXXX` escapes pass through intact. Documented in the skill's Step 5.

## What Didn't Work

- **Initial `exec -a "$marker" bash -c ...` for the spinner process name:** macOS's stock `/bin/bash` (3.2) doesn't handle `exec -a` reliably. Replaced with `bash -c '…' "$marker" …` which sets `$0` to the marker and is visible to `pkill -f`.
- **Writing Nerd Font glyphs directly in Bash tool arguments:** the Claude Code Bash tool strips them. Had to route through `python3 -c` every time a glyph is written to a tmux option.
- **`exec -a` + inheriting hook pipes** caused Claude Code to freeze on every tool call — the backgrounded spinner held the hook's stdout/stderr fds open, blocking the hook reader. Fixed with `</dev/null >/dev/null 2>&1`.
- **`Notification` hook as a catch-all "attention needed" signal:** false positives at turn-end caused the yellow warning to stick forever. Removed.
- **`AskUserQuestion` with 10 previews:** caps at 4 options per question. Skill now shows 4 strong picks at a time.
- **ANSI 24-bit color escapes in chat text and `AskUserQuestion` previews:** stripped by the Claude Code TUI. Cannot be used for color previews.
- **Rendering Nerd Font PUA glyphs inside `AskUserQuestion` labels/previews:** the Claude Code TUI's built-in font doesn't map the PUA range. Glyphs come out blank. Emoji stand-ins only inside the picker.
- **`@resurrect-hook-post-restore-all`** doesn't exist — tmux-resurrect only exposes `pre-*` hooks. Used `set-hook -g client-attached` instead for idempotent window-meta restoration on every attach.
- **Bare-integer tmux targets (`-t 2`)** — silently resolved to the current window. Wasted a debug cycle trying to find a skill logic bug before isolating the target-syntax issue.

## What's Next

Nothing is blocking. Plausible follow-ups, in priority order:

1. **Cross-machine sync test.** All of today's work is on the personal Mac only. Run `./install` on the work Mac to verify Dotbot symlinks the new skill directory, tmux scripts, and Claude hook correctly. The relevant new symlinks are in `install.conf.yaml`:
   - `~/.claude/skills/tmux-window-namer → claude/skills/tmux-window-namer`
   - `~/.config/tmux/scripts/{save,restore}-window-meta.sh → tmux/scripts/…`
   - `~/.config/tmux/scripts/` was added to the `create:` list
2. **Rename cleanup in the skill.** When the skill renames a window (e.g., "Dotfiles" → "tmux"), the old sidecar entry keyed by the old name is left orphaned. Had to manually `jq del` it twice in this session. Either add a `--rename-from <old_name>` flag to `save-window-meta.sh` or have the skill remove the orphan entry as part of its apply step.
3. **Pane-scoped indicators (v2).** If splitting a tmux window with two Claudes becomes a real use case, migrate `@claude_status` and `@win_*` from window-scoped to pane-scoped and rewrite the format string to walk panes. Not urgent.
4. **Palette editor / custom palette support in the skill.** Right now the 8 palettes are hard-coded in `references/palettes.md`. A future version could read a user-extensible palette file from `$XDG_CONFIG_HOME/tmux-window-namer/palettes.json` and merge.
5. **Animated glyphs beyond the Claude spinner.** Out of scope for v1, but the infrastructure now exists to support it.

## Gotchas & Watch-outs

- **Never use bare-integer tmux targets.** `tmux set-option -w -t 2` will silently hit the current window. Use `-t :2` (leading colon, explicit index) or `-t @ID` (stable window id from `tmux list-windows -F '#{window_id}'`). Full write-up in `docs/solutions/code-quality/tmux-set-option-bare-index-target-gotcha.md`.
- **Nerd Font glyphs in tmux options must be set via python.** The Claude Code Bash tool strips private-use-area (U+E000–U+F8FF) characters from command-line args. Use `python3 -c "import subprocess; subprocess.run(['tmux','set-option','-w','-t',':N','@win_glyph','\uf013'], check=True)"`. Emojis (outside PUA) survive Bash, but use python uniformly for consistency.
- **Hooks must fully detach their background processes' stdio** or Claude Code's UI will hang. Every backgrounded subshell: `</dev/null >/dev/null 2>&1 &`.
- **Don't wire `Notification` → waiting.** It fires on every turn-end. `PermissionRequest` is the only reliable "attention needed" signal.
- **The skill's live preview IS the tmux tab.** The `AskUserQuestion` picker can only show emoji stand-ins; the real glyph and real color are on the actual tab while the picker is open. Present variations serially (apply → ask → next) rather than trying to render previews inside the picker card.
- **tmux-resurrect has no `post-restore-all` hook.** Use `set-hook -g client-attached` + an idempotent restore script.
- **`AskUserQuestion` header is not interactive.** Name it neutrally ("Variation 2", "Tab style") — don't write "Keep or next?" because it looks like a clickable tab and confuses users.
- **Spinner orphans from pre-fix versions** can leak. Detect with `pgrep -f "sleep 0.15"` and kill their bash parent. New versions (post `48bd6c6`) self-terminate via parent-PID watch + sentinel.
- **Sidecar entries become stale when a window is renamed.** `restore-window-meta.sh` is idempotent and no-ops on non-matching names, but stale entries accumulate. Clean manually with `jq 'del(.main["Old Name"])'` until the skill handles rename cleanup.

## Current tab styling (for visual reference after pickup)

- `main:1` `🦞 OpenClaw` — emoji in name, no skill styling
- `main:2` `Datawork Site` — `` (U+E7BA) in sky `#7DACD3`, subdued title
- `main:3` `🦅 Eagle` — emoji in name, no skill styling
- `main:4` `Dotfiles` — `` (nf-fa-cog, U+F013) in ember `#D97757`, monochrome
