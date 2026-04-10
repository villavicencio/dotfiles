---
title: "Claude Code Bash tool strips Nerd Font PUA glyphs from command arguments"
date: 2026-04-08
category: code-quality
tags:
  - claude-code
  - tmux
  - nerd-font
  - bash-tool
  - workaround
severity: Medium
component: "Claude Code Bash tool; tmux user options; claude/skills/tmux-window-namer/SKILL.md"
symptoms:
  - Nerd Font glyphs (U+E000–U+F8FF) silently disappear from Bash tool command arguments
  - tmux user options set via the Bash tool end up with empty string values instead of glyphs
  - Emojis (outside PUA range) pass through fine, making the issue intermittent-looking
problem_type: tool_limitation
module: claude-code-hooks
---

## Summary

The Claude Code Bash tool strips characters in the Unicode Private Use Area
(U+E000–U+F8FF) from command-line arguments before execution. This affects
all Nerd Font glyphs (e.g., `` U+F013 nf-fa-cog, `` U+E7BA nf-md-web).
The command runs without error, but the glyph value is silently dropped,
leaving an empty string where the glyph should be.

Emojis (which live outside PUA, in ranges like U+1F300–U+1F9FF) are not
affected, which makes the issue look intermittent if you're testing with
a mix of emojis and Nerd Font icons.

## Root Cause

The Claude Code TUI's Bash tool implementation filters out PUA-range
characters from the command string before passing it to the shell. This
is likely a sanitization measure, since PUA characters have no standard
rendering and could cause display issues in the TUI's output.

## Fix

Route all Nerd Font glyph writes through `python3 -c`, using `\uXXXX`
escape sequences in Python string literals. Python's string escapes are
processed by the Python interpreter, not by the Bash tool's argument
parser, so PUA characters survive intact.

```bash
# WRONG — glyph is silently stripped
tmux set-option -w -t :2 @win_glyph ''

# RIGHT — glyph passes through via Python string escape
python3 -c "import subprocess; subprocess.run(['tmux','set-option','-w','-t',':2','@win_glyph','\uf013'], check=True)"
```

For consistency, use the Python approach for all glyph writes, even if
some glyphs (like emojis) would survive the Bash tool. This avoids
having to remember which Unicode ranges are safe.

## Key Takeaway

When a Claude Code skill or hook needs to write non-ASCII characters
(especially Nerd Font glyphs) to any target — tmux options, files,
environment variables — always use `python3 -c` with `\uXXXX` escapes.
Never pass PUA characters directly through the Bash tool.
