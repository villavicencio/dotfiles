---
title: "Homebrew 7's `brew shellenv` prepends PATH directly, so a Homebrew `claude` shadows the native install in nested shells"
date: 2026-10-08
category: runtime-errors
tags:
  - zsh
  - path
  - homebrew
  - claude-code
  - path_helper
severity: Medium
component: "zsh/zshrc, bin/dot"
problem_type: "PATH order silently undone after zshenv"
module: "zsh"
related_solutions:
  - "docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md: an intermittent symptom that depended on the inherited environment"
---

# Homebrew 7's `brew shellenv` prepends PATH directly, so a Homebrew `claude` shadows the native install in nested shells

## Symptom

Claude Code showed "update available". `claude update` refused because the install was managed
by Homebrew, even though the session in use was the native install.

Two copies were present:

| Path | Version | Source |
|---|---|---|
| `~/.local/bin/claude` | 2.1.293 | native installer (`helpers/install_claude_code.sh`) |
| `/opt/homebrew/bin/claude` | 2.1.291 | `claude-code@latest` cask, installed by hand on 2026-09-22 (zsh history) and kept updated by topgrade |

The repo never installs the cask: the Brewfile has no Claude entry, and #38 removed the cask.
What failed was the PATH order meant to make the native copy win.

## Cause

`zsh/zshenv` puts `~/bin` and `~/.local/bin` ahead of Homebrew. Before `zshrc` finishes, two
things undo that:

1. **`brew shellenv`.** `zshrc` filtered out its `eval … path_helper` line. Homebrew 7.0.8 no
   longer emits one; it prepends with `export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"`,
   which the filter didn't match. Because PATH is `typeset -U`, the new first entry wins.
2. **`path_helper` in `/etc/zprofile`**, in login shells (every iTerm tab). It moves `/etc/paths`
   to the front, so `/bin/ls` beat gnubin and `/usr/bin/curl` beat the keg-only curl. That was
   already fixed for hal in `zsh/zprofile.server`, but not on desk Macs.

The problem was intermittent because `zshrc` also sourced `~/.local/bin/env`, an installer's
script from May 2025 (mislabeled "Rustup env"). It prepends `~/.local/share/../bin`, the same
directory spelled differently, so `typeset -U` doesn't de-duplicate it.

- In a fresh iTerm tab, that spelling landed first and the native `claude` won.
- In any nested shell (tmux, herdr panes, the agent's Bash tool), the spelling was already in
  the inherited PATH, so the script skipped it and Homebrew won.

The same accident decided `node`: Hermes links Node 26 into `~/.local/bin`, so top-level tabs
ran Node 26 while nested shells ran nvm's Node 24.

## Fix

- `zshrc` runs `brew shellenv` unfiltered, then re-sources `$ZDOTDIR/.zshenv`. zshenv only
  prepends and PATH is unique, so this restores its order. It's the approach
  `zprofile.server` already used for hal.
- The `~/.local/bin/env` source line is gone. zshenv already provides `~/.local/bin`, and the
  aliased spelling was what made the bug intermittent.
- `dot doctor` (desk Macs) fails when `command -v claude` doesn't resolve to the same file as
  `~/.local/bin/claude`. Its shadowing scan counts distinct real files, so one binary reached
  through two spellings no longer warns.
- Removed the cask: `brew uninstall --cask claude-code@latest`.

Verified in a clean-env login shell: `claude`, `ls` (gnubin), `curl` (keg) and `git` (Homebrew)
resolve to their intended copies. `dot bench` median went from 183 ms to 193 ms (budget 300 ms); the re-source costs one
`uname -m` fork.

## Not covered

Non-interactive login shells (`zsh -l -c …`, including the herdr pane template) don't read
`zshrc`, so they keep `path_helper`'s order (`/usr/bin` before `~/.local/bin` and Homebrew). The
desk `$ZDOTDIR/.zprofile` is OrbStack's regular file, not a repo link. Fixing those shells means
owning that file on desk Macs too, the way the server profile does.

## How to check

```bash
dot doctor                                   # "claude resolves to the native install"
zsh -i -c 'whence -a claude'                 # ~/.local/bin/claude first
/opt/homebrew/bin/brew shellenv zsh | grep PATH   # see what shellenv emits today
```
