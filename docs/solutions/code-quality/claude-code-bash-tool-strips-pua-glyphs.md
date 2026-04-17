---
title: "Claude Code Bash AND Write tools strip Nerd Font PUA glyphs"
date: 2026-04-08
updated: 2026-04-17
category: code-quality
tags:
  - claude-code
  - tmux
  - nerd-font
  - bash-tool
  - write-tool
  - workaround
severity: Medium
component: "Claude Code Bash tool (argv), Claude Code Write tool (file content); tmux user options; committed JSON seed files; claude/skills/tmux-window-namer/SKILL.md"
symptoms:
  - Nerd Font glyphs (U+E000–U+F8FF, plus supplementary PUA U+F0000–U+FFFFD and U+100000–U+10FFFD) silently disappear from Bash tool command arguments
  - tmux user options set via the Bash tool end up with empty string values instead of glyphs
  - Files written via the Write tool containing PUA glyphs land on disk with the glyphs stripped — surrounding ASCII and standard-plane Unicode (emojis) remain intact
  - Committed JSON seed files (e.g., `tmux/window-meta.linux.json`) contain `"glyph": ""` after a Write-tool write, even though the source prompt included the literal glyph
  - Emojis (outside PUA range) pass through fine in both tools, making the issue intermittent-looking
problem_type: tool_limitation
module: claude-code-hooks
---

## Summary

Both the Claude Code **Bash tool** (in command-line arguments) and the
**Write tool** (in the `content` parameter) strip characters in the
Unicode Private Use Area (U+E000–U+F8FF, plus supplementary PUA planes
U+F0000–U+FFFFD and U+100000–U+10FFFD) before passing them to the
underlying shell or file write. This affects all Nerd Font glyphs
(e.g., `` U+F013 nf-fa-cog, `` U+E7BA nf-md-web, and Material
Design Icons in the supplementary plane like `` U+F129B). The tool
completes without error, but the glyph is silently dropped — leaving
empty strings in tmux options, environment variables, or files.

Emojis (outside PUA, in ranges like U+1F300–U+1F9FF) pass through
both tools fine, which makes the issue look intermittent if you're
testing with a mix of emojis and Nerd Font icons.

**Confirmed reproduction (2026-04-17):** A committed JSON seed file
`tmux/window-meta.linux.json` was written via the Write tool with
`"glyph": ""` where `` is the literal U+EE0D. On disk, the value
landed as `"glyph": ""` (empty). Python codepoint check on the
bytes confirmed the char was missing. Same char in a JSON `\uXXXX`
escape survived intact.

## Root Cause

The Claude Code TUI's Bash tool implementation filters out PUA-range
characters from the command string before passing it to the shell. This
is likely a sanitization measure, since PUA characters have no standard
rendering and could cause display issues in the TUI's output.

## Fix — per target

### Live tmux options / environment / argv-bound targets

Route through `python3 -c`, using `\uXXXX` (BMP) or `\U000XXXXX`
(supplementary plane) escape sequences in Python string literals.
Python's string escapes are processed by the Python interpreter, not
by the Bash tool's argument parser, so PUA characters survive intact.

```bash
# WRONG — glyph is silently stripped
tmux set-option -w -t :2 @win_glyph ''

# RIGHT — glyph passes through via Python string escape
python3 -c "import subprocess; subprocess.run(['tmux','set-option','-w','-t',':2','@win_glyph','\uf013'], check=True)"

# RIGHT — supplementary-plane glyph (e.g., Material Design Icons)
python3 -c "import subprocess; subprocess.run(['tmux','set-option','-w','-t',':2','@win_glyph','\U000F129B'], check=True)"
```

### Committed files (JSON seeds, shell scripts, configs)

**Never put literal PUA characters inside a Write-tool `content`
argument.** Use the file format's native escape syntax so the file
contains only ASCII at rest and the escape is decoded at parse time:

- **JSON files:** use `"\uXXXX"` (BMP) or `"\uD83D\uDE00"`-style
  surrogate pair for supplementary plane. jq, Python's `json`, and
  every JSON parser in existence decode this correctly.
  ```json
  // WRONG — Write tool strips the  leaving an empty string
  { "glyph": "" }
  // RIGHT — JSON native \uXXXX escape, pure ASCII in the Write argument
  { "glyph": "\uee0d" }
  ```
- **Bash/zsh scripts:** use `$'\uee0d'` ANSI-C quoting or
  `printf '\xee\x... '` for on-disk output. For POSIX-portable:
  write via `python3 -c 'import sys; sys.stdout.buffer.write(...)'`
  redirected to the file.
- **Python source files:** use `"\uXXXX"` or `"\U000XXXXX"` literals.

### Verification (always do this)

After any write that should contain a PUA char, verify the codepoint
landed correctly:

```bash
python3 -c "
import json
with open('path/to/file') as f: d = json.load(f)
g = d['some']['path']['glyph']
print(f'len={len(g)}  codepoints={[hex(ord(c)) for c in g]}')
"
# expect: len=1 (or 2 if intentional trailing space), codepoints=[0xee0d, ...]
```

## Related issue this same day

Writing the seed file via a `python3 <<'PY' ... json.dump(...)` heredoc
and then **reformatting** it with the Write tool stripped the PUA back
out. The lesson: if your pipeline has multiple steps, the constraint
applies at every Write-tool boundary. The heredoc-Python path is safe;
the Write-tool path is not. Mixed pipelines need JSON escapes
end-to-end if they touch Write.

## Key Takeaway

Before today (2026-04-17) this was framed as a Bash-tool-only issue.
The Write tool has the same filter in its `content` parameter. Treat
**both** as PUA-hostile. Concrete rules:

1. Never put a literal PUA glyph in a Bash-tool argv.
2. Never put a literal PUA glyph in a Write-tool `content` argument.
3. For argv targets → `python3 -c` with `\uXXXX` escapes.
4. For committed files → use the file format's native unicode escape
   (`\uXXXX` in JSON, `$'\uXXXX'` in bash scripts, etc.). Keep the
   Write argument pure ASCII.
5. Always verify on disk with a codepoint read-back; symptom is
   silent, so automated verification is the only reliable signal.
