---
title: "tmux set-option -w -t N silently hits current window instead of window index N"
date: 2026-04-08
category: code-quality
tags:
  - tmux
  - scripting
  - gotcha
  - target-syntax
  - claude-skill
severity: Medium
component: "tmux command target resolution; claude/skills/tmux-window-namer/SKILL.md"
symptoms:
  - Commands issued via `tmux set-option -w -t 2 ...` modify the currently-attached window instead of window index 2
  - A skill that claims to target a specific window appears to target the current one every time
  - Per-window user options set on "window 2" read back as the current window's values
  - Fuzzy debugging shows both `-t 2` and `-t 4` resolving to the same window
problem_type: logic_error
module: tmux-window-namer-skill
---

## Summary

While building the `tmux-window-namer` Claude Code skill, repeated attempts
to apply a glyph and colors to window index 2 silently landed on window 4
(the currently-attached window). The commands ran without error, returned
exit code 0, and reading back the options gave the values that were
actually on the wrong window — making the bug look like a skill logic
error rather than a tmux target-resolution quirk.

## Root cause

`tmux set-option -w -t N`, where `N` is a **bare integer**, is not a
reliable way to say "window at index N in the current session." tmux's
target-window resolver treats the string after `-t` as a potential window
*name* first. If no window in the current session has the literal name
"N", tmux falls back — in at least some command contexts — to the
currently-attached window instead of failing or resolving to the index.

The result: the skill's "apply to window 2" commands ran against the
caller's current window, every time. The same syntax happened to work for
`rename-window -t 2` in casual shell use because the user almost always
invokes it from the very window they want to rename, so the fallback
lands on the intended target by coincidence.

## Diagnosis

The smoking gun was this diagnostic:

```bash
tmux set-option -w -t 2 @test_marker 'W2'
tmux set-option -w -t 4 @test_marker 'W4'
tmux show-options -w -t 2 -v @test_marker   # -> W4
tmux show-options -w -t 4 -v @test_marker   # -> W4
```

Both reads returned `W4`, proving that `-t 2` and `-t 4` were resolving
to the same window (the current one). Switching to window-id targets
(`-t @3`, `-t @5`) gave the correct per-window values, confirming the
issue was purely in how the bare-integer target was being parsed.

## Working solution

Always use one of the **explicit** target forms when scripting tmux
option or rename commands:

| Form | Meaning |
|---|---|
| `-t :N`             | Window at index N in the current session (**leading colon required**) |
| `-t <session>:N`    | Window at index N in a specific session |
| `-t @ID`            | Window by its stable ID (`@1`, `@3`, …) from `tmux list-windows -a -F '#{window_id}'` |

Rewriting the skill's apply step from:

```bash
tmux set-option -w -t 2 @win_glyph "$glyph"
```

to:

```bash
tmux set-option -w -t :2 @win_glyph "$glyph"
```

immediately fixed the target resolution. Same rule applies to
`rename-window`, `kill-window`, and any other command that accepts a
`target-window`.

When the skill resolves a user-specified index, it now **always**
prepends a colon before passing it to tmux. For code that already has a
window id in hand (e.g., from `list-windows -F '#{window_id}'`), the
`@ID` form is the most robust choice and doesn't need the colon.

## Prevention

1. **Skill documentation** — `claude/skills/tmux-window-namer/SKILL.md`
   now has a prominent `⚠️ tmux target-syntax gotcha` section under
   Step 1 that forbids bare-integer targets and requires `:N` or `@ID`.
2. **Script reviews** — when reading any dotfiles shell script that
   builds a tmux target string from a user-supplied index, grep for
   `-t ` followed by a bare digit and flag it.
3. **Rule of thumb** — the only time a bare `-t N` is safe is when `N`
   is *not* a pure integer string (e.g., a session name that happens
   to start with a digit, or a window name the user chose). For indices,
   always use `:N`.
4. **Diagnostic pattern** — if a tmux script appears to apply changes
   to the wrong tab, set a unique `@marker` option on two different
   windows via the suspect target syntax and read it back via explicit
   window IDs (`-t @ID`). If both reads return the same value, the
   target syntax is the problem.

## Related

- `claude/skills/tmux-window-namer/SKILL.md` — the skill where the
  gotcha was fixed. The fix is in the "tmux target-syntax gotcha"
  subsection under Step 1.
- `tmux/tmux.display.conf` — consumes the `@win_glyph`,
  `@win_glyph_color`, `@win_title_color` window options set by the
  skill.
- `tmux/scripts/save-window-meta.sh` / `restore-window-meta.sh` —
  persistence layer that was initially suspected as the culprit before
  the target-syntax bug was isolated.

## Key commits

- `719836a` Document tmux target-syntax gotcha in window-namer skill
