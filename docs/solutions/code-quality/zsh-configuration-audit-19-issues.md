---
title: "Zsh Configuration Audit: 19 Issues Resolved Across Dotfiles"
date: 2026-03-11
category: code-quality
tags:
  - zsh
  - dotfiles
  - performance
  - bug-fix
  - code-hygiene
  - cross-platform
severity: High
component: "zsh shell configuration (zshenv, zshrc, alias.sh, options.sh, functions/)"
symptoms:
  - PATH environment variable doubled on every login
  - CARGO_HOME undefined, resolving CARGO_BIN to /bin
  - Bash-only history variables having no effect in zsh
  - NVM sourced eagerly causing 200-400ms startup delay
  - Brew shellenv sourced eagerly making lazy loader unreachable
  - Compinit run twice (manual + OMZ)
  - Hardcoded TERM=xterm-256color breaking tmux
  - Tmux session restoration adding ~1s delay per shell start
  - FZF and RVM lazy loaders with duplicated function definitions
related_issues:
  - "GitHub #1-#19 on villavicencio/dotfiles"
  - "Kymsu replaced with Topgrade (system updater)"
status: Resolved
scope:
  - zsh/zshenv
  - zsh/zshrc
  - zsh/alias.sh
  - zsh/options.sh
  - zsh/functions/
  - brew/Brewfile
  - helpers/install_kymsu.sh (deleted)
  - topgrade/topgrade.toml (added)
---

# Zsh Configuration Audit: 19 Issues Resolved

## Context

A comprehensive audit of a dotfiles repo managing two Macs (personal macOS Tahoe M-series, work macOS Sequoia M-series) via Dotbot. The zsh config had accumulated 19 issues from organic growth without regular auditing, spanning bugs, performance problems, and code hygiene.

## Root Cause

The issues fell into six categories:

1. **PATH manipulation error**: `${PATH:+:${PATH}}:$PATH` doubled the entire PATH on every login
2. **Undefined variable fallback**: `$CARGO_HOME` never set, so `CARGO_BIN` resolved to `/bin`
3. **Bash-isms in zsh**: `HISTFILESIZE`, `HISTTIMEFORMAT`, `HISTCONTROL`, `HISTIGNORE` are bash-only
4. **Eager/lazy loader conflict**: Eager `brew shellenv` made the lazy loader unreachable; NVM sourced eagerly (~200-400ms)
5. **Duplicate declarations**: Same exports and setopts in both zshenv and zshrc
6. **Copy-pasted code**: FZF (45 lines) and RVM (50 lines) lazy loaders were near-identical repeated functions

## Solution

### Bugs (Issues #1-#4)

| Issue | Fix |
|-------|-----|
| PATH doubled every login | Removed trailing `:$PATH` from expansion |
| CARGO_BIN = `/bin` | Changed to `$HOME/.cargo/bin` directly |
| Duplicate RVM in PATH | Removed redundant literal `$HOME/.rvm/bin` |
| Bash-only history vars | Removed all 4, added `SAVEHIST=$HISTSIZE` |

### Performance (Issues #5-#6, #14-#15)

| Issue | Fix | Impact |
|-------|-----|--------|
| Eager brew shellenv + dead lazy loader | Removed unreachable lazy loader | Cleaner code |
| NVM eager load (~200-400ms) | Lazy loader with PATH shim | Major startup improvement |
| Tmux restoration `sleep 1s` every shell | Guarded with `$TMUX` and `$TERM_PROGRAM` checks | -1s for non-tmux shells |
| Double compinit | Removed manual, let OMZ handle it | Faster startup |

### Duplicates (Issues #7-#9, #12)

| Issue | Fix |
|-------|-----|
| Duplicate setopts in options.sh + zshrc | Deleted options.sh entirely |
| Duplicate LANG export | Removed from zshrc, kept in zshenv |
| Duplicate PYENV_ROOT | Already clean in committed code |

### Cleanup (Issues #10-#11, #13, #16-#19)

| Issue | Fix |
|-------|-----|
| PAGER=most conflicting with man_colorful | Dropped most, consolidated on less |
| Tilde in NODE_REPL_HISTORY_FILE | Changed to `$HOME` |
| Hardcoded TERM=xterm-256color | Removed (let terminal set it) |
| FZF lazy loader verbose | 45 lines to 13 via `_load_fzf` helper |
| RVM lazy loader verbose | 50 lines to 12 via `_load_rvm` helper |
| No-op tmux lazy loader | Removed (wrapped `command tmux` with no deferred init) |
| Dead commented-out source lines | Removed |

### Bonus: Kymsu to Topgrade

Replaced the archived Kymsu system updater with Topgrade. Added `topgrade.toml` config to skip JetBrains IDEs (not installed) and system RubyGems (macOS Ruby 2.6 too old).

## Code Examples

### PATH doubling fix

```bash
# Before (doubles PATH every login)
export PATH="...:${PATH:+:${PATH}}:$PATH"

# After (correct)
export PATH="...:${HOME}/perl5/bin${PATH:+:${PATH}}"
```

### NVM lazy loading pattern

```bash
# Before: eager load (~200-400ms per shell)
source "$NVM_DIR/nvm.sh"
nvm alias default stable >/dev/null 2>&1
nvm use default >/dev/null 2>&1

# After: lazy load (~0ms, defers until first use)
DEFAULT_NODE_PATH="$(ls -d "$NVM_DIR/versions/node"/v* 2>/dev/null | tail -1)/bin"
[[ -d "$DEFAULT_NODE_PATH" ]] && export PATH="$DEFAULT_NODE_PATH:$PATH"
unset DEFAULT_NODE_PATH

_load_nvm() {
  unset -f _load_nvm nvm node npm npx
  source "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _load_nvm; nvm "$@"; }
node() { _load_nvm; node "$@"; }
npm()  { _load_nvm; npm "$@"; }
npx()  { _load_nvm; npx "$@"; }
```

### Lazy loader consolidation pattern

```bash
# Before: 5 copy-pasted functions (~50 lines)
rvm()    { unset -f rvm ruby gem rake bundle; source ...; rvm "$@"; }
ruby()   { unset -f rvm ruby gem rake bundle; source ...; ruby "$@"; }
gem()    { unset -f rvm ruby gem rake bundle; source ...; gem "$@"; }
# ... repeated for rake, bundle

# After: shared helper (~12 lines)
_load_rvm() {
  unset -f _load_rvm rvm ruby gem rake bundle
  source "$HOME/.rvm/scripts/rvm"
}
rvm()    { _load_rvm; rvm "$@"; }
ruby()   { _load_rvm; ruby "$@"; }
gem()    { _load_rvm; gem "$@"; }
rake()   { _load_rvm; rake "$@"; }
bundle() { _load_rvm; bundle "$@"; }
```

## Prevention Strategies

### PATH Construction
- Assemble PATH once in `zshenv` only — never append/prepend in multiple files
- Use `typeset -U PATH` to auto-deduplicate
- Verify with `echo $PATH | tr ':' '\n' | sort | uniq -d`

### Shell-Specific Variables
- Grep for bash-only constructs before committing: `HISTFILESIZE`, `HISTCONTROL`, `HISTIGNORE`, `HISTTIMEFORMAT`
- Zsh equivalents: `SAVEHIST`, `setopt HIST_IGNORE_DUPS`, `setopt HIST_IGNORE_SPACE`, `setopt EXTENDED_HISTORY`

### Lazy Loading
- Never mix eager and lazy init for the same tool
- One `_load_*` helper per tool, one-liner wrappers for each command
- Test lazy loaders actually defer: `time zsh -i -c exit`

### Duplicate Prevention
- Strict file responsibility: `zshenv` for env vars/PATH, `zshrc` for interactive options
- Audit: `grep -h "^export" zsh/zshenv zsh/zshrc | awk -F= '{print $1}' | sort | uniq -d`

### Hardcoded Values
- Never hardcode `/Users/<username>/` — use `$HOME`
- Never hardcode `/opt/homebrew/` or `/usr/local/` — use `$BREW_PREFIX`
- Don't set `TERM` — let the terminal emulator handle it

## Audit Checklist

Run periodically or after major refactors:

- [ ] `echo $PATH | tr ':' '\n' | sort | uniq -d` — no duplicates
- [ ] `grep -rn "^export" zsh/zshenv zsh/zshrc` — no duplicate keys across files
- [ ] `grep -rn "^setopt" zsh/` — each setopt appears exactly once
- [ ] Each lazy loader has no competing eager init
- [ ] No hardcoded `/Users/dvillavicencio/` in any config file
- [ ] No hardcoded `/opt/homebrew/` or `/usr/local/` (except documented exceptions like `MYSQL_BIN`)
- [ ] `time zsh -i -c exit` — startup under 300ms
- [ ] `zsh -i -c exit 2>&1` — no warnings or errors
- [ ] `./install` runs clean on a fresh checkout

## Commits

| SHA | Description |
|-----|-------------|
| `9e4c411` | Fix doubled PATH and duplicate RVM entry |
| `1d18e23` | Fix undefined CARGO_HOME |
| `6a1f229` | Remove bash-only history vars, add SAVEHIST |
| `cd3d996` | Remove unreachable brew lazy loader |
| `83968b9` | Lazy-load NVM |
| `7039dd9` | Remove duplicate setopts / delete options.sh |
| `fe5e389` | Remove duplicate LANG (first pass) |
| `0c4114e` | Reconcile pager config |
| `9064da5` | Tilde to $HOME consistency |
| `431d01d` | Remove remaining duplicate LANG |
| `d225fda` | Remove hardcoded TERM |
| `995278f` | Guard tmux session restoration |
| `8a25ace` | Remove double compinit |
| `6921b31` | Consolidate FZF lazy loader |
| `5cba499` | Consolidate RVM lazy loader |
| `450d022` | Remove no-op tmux lazy loader + dead source lines |
| `ea311b8` | Replace Kymsu with Topgrade |
| `975880d` | Add Topgrade config |
| `f61d854` | Skip system RubyGems in Topgrade |
