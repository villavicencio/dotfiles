---
title: "`brew shellenv` clobbers user-scope PATH priority via a nested `path_helper` eval"
date: 2026-04-18
category: code-quality
tags:
  - zsh
  - path
  - homebrew
  - brew-shellenv
  - path_helper
  - macos
  - debugging
severity: Medium
component: "zsh/zshenv, zsh/zshrc, /opt/homebrew/bin/brew shellenv, /usr/libexec/path_helper"
symptoms:
  - "`command -v claude` returns `/opt/homebrew/bin/claude` (stale Homebrew cask) even after reordering `zshenv` PATH to put `~/.local/bin` before `$BREW_BIN`"
  - "Non-interactive `zsh -c` shows the corrected PATH ordering; interactive `zsh -i -c` reverts it with Homebrew paths back at positions 2–3"
  - "No `export PATH=` line is visible in `brew shellenv`'s output, yet PATH gets rebuilt with Homebrew at the front on every interactive shell startup"
  - "Anthropic's native `claude` installer symlinks `~/.local/bin/claude → ~/.local/share/claude/versions/<latest>`, but shells resolve to the Homebrew binary anyway, leaving the user on a stale cask version"
problem_type: shell_config / path_ordering
module: shell-init
related_solutions:
  - "docs/solutions/code-quality/zsh-configuration-audit-19-issues.md — broader zsh audit from earlier"
  - "docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md — unrelated PATH-adjacent Claude Code quirk"
---

# `brew shellenv` clobbers user-scope PATH priority via a nested `path_helper` eval

## Symptom

You edit `zsh/zshenv` to put user-scope bins before Homebrew:

```zsh
export PATH="$LOCAL_BIN:$LOCAL_SHARE_BIN:$BREW_CURL:$BREW_BIN:$BREW_SBIN:..."
```

In a fresh subshell (`zsh -c`), this works: `command -v claude` resolves to `~/.local/bin/claude`. Great.

But in **interactive** shells (`zsh -i -c`, or just opening a new terminal pane), the ordering is silently reversed:

```
$ zsh -i -c 'echo $PATH | tr : "\n" | head -6'
/Users/you/.antigravity/antigravity/bin
/opt/homebrew/bin          ← back to position 2
/opt/homebrew/sbin
/Users/you/.pyenv/bin
/Users/you/bin
/Users/you/.local/bin      ← pushed down to 6
```

And the obvious first-fix doesn't work:

```zsh
# zshrc line that seems like the only PATH-toucher for Homebrew:
eval "$("$BREW_PREFIX/bin/brew" shellenv | grep -v '^export PATH=')"
```

You diff `brew shellenv`'s output — no `^export PATH=` line exists. Your grep is a no-op. But the effect is real: interactive shells still clobber PATH.

## Root cause: nested evals hiding behind `path_helper`

`brew shellenv` emits this line among its exports:

```
eval "$(/usr/bin/env PATH_HELPER_ROOT='/opt/homebrew' /usr/libexec/path_helper -s)"
```

`/usr/libexec/path_helper -s` is a macOS utility that:
1. Reads `/etc/paths` and all files under `/etc/paths.d/`
2. Prepends `$PATH_HELPER_ROOT/bin:$PATH_HELPER_ROOT/sbin` to the system defaults
3. **Outputs a complete `PATH="..."; export PATH;` statement on stdout**

When the outer `eval` in `brew shellenv` consumes that stdout, it runs the inner `PATH=...; export PATH;` — fully replacing whatever PATH was, with Homebrew paths at the front.

**The PATH clobbering is therefore two evals deep** (`eval ← brew shellenv output ← path_helper output`), which is why a regex like `^export PATH=` against `brew shellenv`'s own output matches nothing. The `export PATH=` statement never appears in the output you see — it's inside a subprocess whose stdout is eval'd.

## The fix

Filter the `path_helper` eval line itself from `brew shellenv`'s output, before passing it to the outer eval:

```zsh
# zsh/zshrc
if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
  eval "$("$BREW_PREFIX/bin/brew" shellenv | grep -vE '^eval .*path_helper')"
fi
```

Everything else `brew shellenv` sets — `HOMEBREW_PREFIX`, `HOMEBREW_CELLAR`, `HOMEBREW_REPOSITORY`, `FPATH`, `MANPATH`, `INFOPATH` — is preserved. Only the PATH reconstruction is suppressed, which is exactly what you want when `zshenv` has already set PATH deliberately.

Verified after the fix:

```
$ zsh -i -c 'command -v claude; md5 -q $(command -v claude)'
/Users/you/.local/bin/claude
a98e42936d677697d779078b9abdb1fa   ← the auto-updated 2.1.114, not the stale Homebrew 2.1.98
```

## Debugging recipe for PATH-reorder mysteries

When interactive PATH doesn't match what your `zshenv` / `zshrc` looks like it should produce, and the obvious `export PATH=` lines are nowhere, trace across shell-init stages:

```zsh
/bin/zsh << 'EOF'
source ~/.config/zsh/.zshenv
echo "=== After zshenv ===" && echo $PATH | tr ":" "\n" | head -5

PREV_PATH="$PATH"
trace_line() {
  if [[ "$PATH" != "$PREV_PATH" ]]; then
    echo "  PATH CHANGED after: $1"
    echo "    new head: $(echo $PATH | tr ":" "\n" | head -3 | tr "\n" " ")"
    PREV_PATH="$PATH"
  fi
}

# Source zshrc block by block, calling trace_line after each
source ~/.oh-my-zsh/oh-my-zsh.sh; trace_line "oh-my-zsh"
eval "$(brew shellenv)"; trace_line "brew shellenv"
eval "$(pyenv init -)"; trace_line "pyenv init -"
# ... etc
EOF
```

Watch which step mutates PATH. Then `diff` the exact output of each eval'd command to find the culprit:

```bash
brew shellenv                        # stdout → what outer eval sees
brew shellenv | sh -c 'set -x; bash' # expand each export
/usr/libexec/path_helper -s          # inner eval stdout
```

The `eval $(...)` pattern is often worth one more level of expansion before dismissing a suspect.

## Prevention

- **Assume `eval $(tool)` can hide nested evals.** When suppressing some effect of such a line, do not regex-match the *outer* tool's output alone; verify what the eval actually executes by running the stdout through a shell trace.
- **Prefer `path_helper`-free alternatives when possible.** If you only need `HOMEBREW_PREFIX` and friends, set them explicitly:
  ```zsh
  export HOMEBREW_PREFIX="$BREW_PREFIX"
  export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
  export HOMEBREW_REPOSITORY="$BREW_PREFIX"
  ```
  …and skip `brew shellenv` entirely. This is the cleanest long-term fix but loses `FPATH`/`MANPATH`/`INFOPATH` auto-setup. Tradeoff depending on what you actually use.
- **Run `./install --dry-run` on a fresh $HOME when modifying shell init.** Catches regressions like "PATH lost Homebrew entirely" that only surface on new machines.

## Reproduction (from the 2026-04-18 session)

1. PR #36 reordered `zshenv:65` PATH: `$LOCAL_BIN:$LOCAL_SHARE_BIN:$BREW_*:…` (user-scope first).
2. Verified in `zsh -c`: `command -v claude` → `~/.local/bin/claude`. Looked fixed.
3. User ran `exec zsh` in a new project dir, launched `claude`. Banner reported `Claude Code v2.1.98` — still the stale Homebrew cask, not the auto-updated 2.1.114.
4. Traced across shell-init stages, first attempt filtered `^export PATH=` from `brew shellenv` output — no effect. The line being filtered didn't exist.
5. Inspected raw `brew shellenv` output, spotted `eval "$(… path_helper -s)"`. That nested eval was the actual PATH replacer.
6. PR #37 updated the filter to `grep -vE '^eval .*path_helper'`. Verified interactive shell now resolves `claude` to the 2.1.114 symlink.

Net effect: two PRs to fix one symptom, because the first fix addressed the visible layer and the second addressed the hidden one. The lesson is the nested-eval debugging discipline, not the specific `path_helper` quirk.
