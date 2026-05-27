---
title: "printf \\xHH hex escapes are not POSIX — dash prints them literally; use octal"
date: 2026-05-27
category: docs/solutions/code-quality/
module: claude
problem_type: runtime_error
component: tooling
symptoms:
  - "Powerline git-branch glyph renders as a literal backslash-x escape string in the Claude Code statusline on Linux hosts"
  - "Same statusline script renders the glyph correctly on macOS, so the bug is invisible during local testing"
  - "grep/sed find-and-replace silently no-ops while reporting the escape is already fixed"
root_cause: wrong_api
resolution_type: code_fix
severity: low
tags: [printf, posix-shell, dash, shell-portability, statusline, octal-escape, powerline, gnu-sed]
---

# printf `\xHH` hex escapes are not POSIX — dash prints them literally; use octal

## Problem

The Claude Code statusline script (`claude/statusline-command.sh`) encoded the Powerline branch glyph **U+E0A0** with a `printf` hex escape (`\xee\x82\xa0`). Hex escapes are a bash/coreutils extension, not POSIX — so under dash (which is `/bin/sh` on Linux hosts), `printf` emitted the literal text `\xee\x82\xa0` instead of the glyph.

## Symptoms

- Statusline shows the literal 12-character string `\xee\x82\xa0` immediately before the git branch name, e.g. `\xee\x82\xa0 master`, instead of the Powerline branch glyph.
- Reproduces only on Linux hosts (e.g. an agent box where `/bin/sh` → dash); **invisible on the Mac**, where `/bin/sh` → bash and the glyph renders correctly.
- Host-dependent: identical script, identical `settings.json` invocation (`sh "$HOME/.claude/statusline-command.sh"`) — the only difference is the `/bin/sh` binary's `printf` behavior.

## What Didn't Work

The first attempt to patch the live file on the Linux host used shell find-and-replace and **silently did nothing** — it reported "already fixed" while the file still plainly contained the broken escape:

```sh
# Printed "NO_HEX_ESCAPE" even though the file still contained \xee\x82\xa0
grep -q "\\xee\\x82\\xa0" "$f" && sed -i "s/\\xee\\x82\\xa0/.../" "$f" || echo "NO_HEX_ESCAPE"
```

Two compounding causes:

1. **bash double-quotes collapse `\\x` → `\x`** before `grep`/`sed` ever see the argument. The tools received the pattern `\xee\x82\xa0`, not the literal backslash-x text that is actually in the file.
2. **GNU grep and GNU sed interpret `\xHH` in a pattern as the byte `0xHH` itself**, not as the literal characters `\`, `x`, `e`, `e`. The pattern therefore searched for the *rendered glyph bytes* `ee 82 a0` — which are **not** in the file (the file holds the literal ASCII text `\xee\x82\xa0`). Nothing matched, `sed` was a silent no-op, and `grep -q` returned false, so the script branched to the "already fixed" path.

Net effect: a regex tool whose own `\x` semantics are the exact thing being debugged is the wrong tool to fix it with.

## Solution

Switch the escape from non-POSIX hex to **POSIX octal**. Octal `\356\202\240` == hex `ee 82 a0` == UTF-8 for U+E0A0.

```sh
# claude/statusline-command.sh, BEFORE
printf " \033[2m|\033[0m ${branch_color}\xee\x82\xa0 %s\033[0m" "$branch"

# AFTER
printf " \033[2m|\033[0m ${branch_color}\356\202\240 %s\033[0m" "$branch"
```

Committed as `de51edc`.

To patch the escape text **in place on a Linux host**, use a literal-string replace that no regex engine ever touches — single-quoted (bash leaves backslashes intact) with Python raw strings (`r"..."`, so Python doesn't interpret `\x` either):

```sh
python3 -c 'import sys;p=sys.argv[1];s=open(p).read();o=r"\xee\x82\xa0";n=r"\356\202\240";print("PATCHED" if o in s else "NOT_FOUND");open(p,"w").write(s.replace(o,n))' ~/.claude/statusline-command.sh
```

This does a byte-for-byte literal substring match (`o in s`) and prints `PATCHED`/`NOT_FOUND` so the result is never silently swallowed.

## Why This Works

- **POSIX `printf` defines only octal `\ooo`** for arbitrary byte values. Hex `\xHH` and Unicode `\uXXXX` are **non-POSIX extensions** added by bash and GNU coreutils. dash implements `printf` strictly to spec, so it honors `\356` but passes `\x...` and `\u...` through literally.
- **`/bin/sh` is not the same binary everywhere.** On macOS, `/bin/sh` is bash (POSIX mode, but it keeps bash's `printf` builtin, which supports `\xHH`), so the bug never surfaced. On Debian/Ubuntu-family Linux, `/bin/sh` is a symlink to dash. Because the statusline is invoked as `sh "$HOME/.claude/statusline-command.sh"`, the active `/bin/sh` identity — not the shebang — determines `printf` behavior, and it differs per host. Octal works in **all three** (`/bin/sh`, dash, bash), making it the only portable choice.
- **GNU `grep`/`sed` treat `\xHH` in a pattern as the literal byte `0xHH`.** A pattern meant to find the *text* `\xee\x82\xa0` instead matches the rendered glyph bytes — which were not in the file — explaining the silent no-op in the failed-fix attempt. The escape syntax being debugged and the regex engine's escape syntax collided.

## Prevention

- **For any non-ASCII byte in a `#!/bin/sh` script or a script invoked via `sh ...`, use octal `\ooo` escapes** in `printf`. Never `\xHH` (bash/coreutils only) and never `\uXXXX` (even less portable).
- **Test sh-invoked scripts under dash, not just the Mac's `/bin/sh`.** A quick portability check before committing any byte-level escape:
  ```sh
  for s in dash bash sh; do printf "%s: " "$s"; $s -c 'printf "\356\202\240"' | xxd | head -1; done
  # all three must emit: ee82a0
  ```
- **When find-and-replacing literal escape text on Linux, avoid `grep`/`sed`** — their `\x` is a byte escape and will misfire on the exact strings you are editing. Prefer a literal-string replace: Python with raw strings (above), or `perl -i -pe 'BEGIN{$o=quotemeta(q{\xee\x82\xa0})} s/$o/\\356\\202\\240/g'` where `quotemeta` neutralizes regex metacharacters.
- **Make replace operations self-verifying** — print `PATCHED`/`NOT_FOUND` (or check the exit status of a literal match) so a no-op match can never masquerade as "already fixed."
- **Annotate intentional octal escapes in source** (as the script now does in the comment above the `printf`) so a future editor does not "helpfully" revert them to the more readable-looking `\x` form and silently reintroduce the dash bug.

## Related

- `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` — sibling gotcha at a *different layer*: the Claude Code Bash/Write/Edit tools strip PUA glyphs (U+E000–U+F8FF) from argv and file writes, so the literal glyph cannot be embedded in source either. That doc covers the editing-tool workaround (`\uXXXX` in Python source / file-format-native escapes); this doc covers the shell-`printf` portability layer. Both must be satisfied to get a Powerline glyph from edited source onto a Linux statusline.
- `docs/solutions/code-quality/tmux-format-hex-mangled-by-single-char-escape-2026-04-21.md` — same family of "an escape parser silently consumes characters before the consumer sees them" in tmux's format-string engine.
- Fix commit: `de51edc` (`fix(statusline): octal escape for branch glyph so dash renders it`).
