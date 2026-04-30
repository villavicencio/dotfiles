---
title: "Python f-string `}}}}` collapses to `}}` — silently breaks tmux format strings"
date: 2026-04-29
category: code-quality
tags:
  - python
  - fstring
  - tmux
  - format-strings
  - silent-bug
severity: Medium
component: "Python f-strings used to wrap tmux format strings or any string format containing literal `{` / `}` characters"
symptoms:
  - Python f-string replacement writes fewer closing braces than the source contained
  - tmux active window pill renders only `4:` instead of `4: <glyph> <name>` after a wrap-with-pill edit
  - tmux config reload silently succeeds; bad format string just produces truncated output
  - `}}}}#W` in source string becomes `}}#W` in output, breaking N levels of `#{?...}` ternary nesting at once
problem_type: language_quirk
module: tmux-config-tooling
---

## Summary

Python f-strings interpret `}}` as a single literal `}`, the same way
`{{` produces a literal `{`. This is by design (it's the f-string
escape rule), but it becomes a silent bug when wrapping any string
that already contains runs of literal `}` characters. Specifically,
**tmux format strings that close N levels of `#{?...}` ternaries with
`}}}}#W` get truncated to `}}#W` if you build the replacement using an
f-string** — silently dropping two ternary closers and breaking the
format.

The bug is hard to spot because:
1. Python doesn't error.
2. tmux's `source-file` doesn't error on a syntactically valid format
   string with mismatched ternary nesting — it just produces wrong
   output.
3. The truncated format renders *something* (e.g., the index `4:`)
   so the tab still appears on the bar, just with content missing.

## Confirmed reproduction (2026-04-29)

Wrapping `tmux/tmux.display.conf`'s active window pill format with new
cap glyphs and a closing `#[fg=...,bg=default]` segment via:

```python
old_close = '}}}}#W "'                                # regular string — 4 braces
new_close = f'}}}}#W #[fg=#2563EB#,bg=default]{cap_r} "'   # f-string — 2 braces!
src = src.replace(old_close, new_close)
```

The match against `old_close` succeeded (4 literal braces in source).
The replacement wrote 2 braces. The active tab rendered as just `4:`
because two of the four `#{?...}` ternaries were no longer closed and
tmux truncated everything after that point.

The same bug bit a second time later in the same session, on the
ghost-pill wrap of the inactive window format — proof that this is a
real foot-gun, not a one-off slip.

## Root cause

f-string brace-escape rule:

| Source | Renders as |
|--------|-----------|
| `f"{{"` | `{` |
| `f"}}"` | `}` |
| `f"{{{{"` | `{{` |
| `f"}}}}"` | `}}` |
| `f"}}}}}}}}"` | `}}}}` |

Each `}}` in an f-string emits one literal `}`. So `}}}}` (4 chars in
source) emits `}}` (2 chars output). To emit 4 literal `}`s from an
f-string you need `}}}}}}}}` (8 chars in source).

Regular strings (no `f` prefix) don't have this rule — `'}}}}` is 4
literal characters as written. That asymmetry is what produces the
silent failure: the *match* string is regular (4 braces in, 4 braces
match), the *replacement* string is f-prefixed (4 braces in, 2 braces
out).

## Fix

Three options, in order of preference:

### 1. Build the replacement as a regular string + concat

```python
cap_r = chr(0xE0B4)
new_close = '}}}}#W #[fg=#2563EB#,bg=default]' + cap_r + ' "'
# 4 literal braces, no f-string magic
```

This is the least surprising — keeps the brace count visible at the
point of definition.

### 2. If you need f-string interpolation, escape every brace

```python
new_close = f'}}}}}}}}#W #[fg=#2563EB#,bg=default]{cap_r} "'
# 8 source braces → 4 output braces
```

Reads badly; easy to miscount; recommend only when you really need
f-string features for other reasons.

### 3. Use a `.format()` call on a non-f-string

```python
new_close = '}}}}#W #[fg=#2563EB#,bg=default]{}}'.format(cap_r)
# Wait, .format() ALSO has the brace-escape rule
```

`.format()` has the same gotcha. So this isn't actually a fix —
included only to flag that you can't dodge the rule by switching to
`.format()`.

## Verification

After any Python-driven edit to a tmux format string, **always** count
brace runs on the result before reloading tmux:

```bash
sed -n '<line>p' tmux/tmux.display.conf | grep -oE '\}+' | tail -1
# Expect: a brace run that closes every #{?...} you opened
# tmux ternaries close in matching depth: 4 nested #{?...} → }}}}#W
```

If the count is wrong, the format will render truncated. If it's
right, reload with `tmux source-file ~/.config/tmux/tmux.conf` and
confirm visually.

## Key takeaway

When wrapping any string that contains runs of literal `}` characters
— tmux format strings, format-spec mini-languages, JSON-with-braces —
**don't use f-strings for the wrapping operation.** Use a regular
string with `+` concatenation if you need to splice in computed
values. The f-string brace-escape rule is correct Python, but it's
catastrophic against grammars that depend on exact brace counts.
