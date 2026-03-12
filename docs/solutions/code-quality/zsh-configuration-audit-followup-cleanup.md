---
title: "Zsh config audit follow-up: gcloud path fix, pyenv consolidation, PATH deduplication"
date: 2026-03-12
category: code-quality
tags:
  - zsh
  - shell-configuration
  - dotfiles
  - path-management
  - lazy-loading
problem_type: code-quality
component: zsh dotfiles (zshrc, zshenv)
symptoms:
  - Hardcoded /Users/dvillavicencio/ paths in gcloud SDK sourcing
  - Verbose pyenv lazy loader with duplicated wrapper functions
  - Potential PATH duplication without typeset -U
related:
  - docs/solutions/code-quality/zsh-configuration-audit-19-issues.md
  - https://github.com/users/villavicencio/projects/2
---

# Zsh Configuration Audit Follow-up Cleanup

Follow-up to the [19-issue zsh config audit](zsh-configuration-audit-19-issues.md), addressing remaining items from the HANDOFF.md next steps.

## Fixes Applied

### 1. Google Cloud SDK Path Convention Violation

**Root cause:** Google Cloud SDK installer auto-appends lines to shell config with hardcoded absolute paths (`/Users/dvillavicencio/Downloads/ll/google-cloud-sdk/`), violating the repo convention of always using `$HOME`.

**Solution:**

Relocated SDK and updated zshrc:

```bash
mv ~/Downloads/ll/google-cloud-sdk ~/.google-cloud-sdk
```

```zsh
# Google Cloud SDK (optional)
[[ -f "$HOME/.google-cloud-sdk/path.zsh.inc" ]] && source "$HOME/.google-cloud-sdk/path.zsh.inc"
[[ -f "$HOME/.google-cloud-sdk/completion.zsh.inc" ]] && source "$HOME/.google-cloud-sdk/completion.zsh.inc"
```

Uses `$HOME`, the standard `[[ -f ... ]] && source` guard pattern, and a stable install location.

### 2. Pyenv Lazy Loader Consolidation

**Root cause:** Pyenv lazy loader used 36 lines with 3 separate functions (`pyenv`, `python`, `pip`) each duplicating `command -v pyenv` checks and `eval "$(command pyenv init ...)"` calls. Inconsistent with FZF/RVM/NVM lazy loaders.

**Solution:**

```zsh
# Lazy load pyenv
if command -v pyenv 1>/dev/null 2>&1; then
  _load_pyenv() {
    unset -f _load_pyenv pyenv python pip
    eval "$(command pyenv init -)"
    eval "$(command pyenv init --path)"
  }
  pyenv()  { _load_pyenv; pyenv "$@"; }
  python() { _load_pyenv; python "$@"; }
  pip()    { _load_pyenv; pip "$@"; }
fi
```

36 lines to 10 lines. Matches the `_load_X` helper pattern used by all other lazy loaders.

### 3. PATH Auto-Deduplication

**Root cause:** No mechanism to prevent duplicate PATH entries from nested shells, tmux sessions, or repeated sourcing.

**Solution:** Added to `zsh/zshenv` before PATH construction:

```zsh
typeset -U PATH
```

Built-in zsh feature, zero overhead, silently drops duplicate entries.

### 4. iTerm2 Shift+Enter Key Mapping

**Root cause:** iTerm2 doesn't distinguish Shift+Enter from Enter by default. Claude Code CLI needs Shift+Enter for multi-line input.

**Solution:** Added key mapping in iTerm2 (Settings > Profiles > Keys > Key Mappings): Shift+Enter sends `\n`. Committed the updated plist.

## Prevention Checklist for New Shell Config Additions

- [ ] Using `$HOME` instead of `/Users/<username>/`?
- [ ] Using `$BREW_PREFIX` instead of `/opt/homebrew/` or `/usr/local/`?
- [ ] Lazy loader follows `_load_X` helper + shim pattern?
- [ ] Lazy loader `unset -f` removes all functions it creates?
- [ ] Shims forward arguments with `"$@"`?
- [ ] Existence guards use `[[ -f ... ]]` (not `[ -f ... ]`)?
- [ ] Right file? (zshenv for env/PATH, zshrc for interactive)
- [ ] No PATH duplicates? `echo $PATH | tr ':' '\n' | sort | uniq -d`
- [ ] Tested with `exec zsh`?
- [ ] Run `git diff` and reviewed for hardcoded paths?

## Quick Reference: Lazy Loader Template

```zsh
# Lazy load TOOLNAME
if [[ -s "$HOME/.tool/init.sh" ]]; then
  _load_toolname() {
    unset -f _load_toolname tool cmd1 cmd2
    source "$HOME/.tool/init.sh"
  }
  tool() { _load_toolname; tool "$@"; }
  cmd1() { _load_toolname; cmd1 "$@"; }
  cmd2() { _load_toolname; cmd2 "$@"; }
fi
```

## Quick Reference: Optional Integration

```zsh
# Tool Name (optional)
[[ -f "$HOME/.tool/integration.sh" ]] && source "$HOME/.tool/integration.sh"
```

## Commits

| Hash | Message |
|------|---------|
| 9d4a34f | Add Google Cloud SDK sourcing with portable $HOME path |
| 2c058a0 | Update iTerm2 preferences including Shift+Enter key mapping |
| b8b0529 | Consolidate pyenv lazy loader to match FZF/RVM/NVM pattern |
| 36246b0 | Add typeset -U PATH to auto-deduplicate PATH entries |
