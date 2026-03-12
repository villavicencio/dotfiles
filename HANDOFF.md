# Handoff: Dotfiles Configuration

## Goal

Comprehensive cleanup, modernization, and cross-machine parity of the zsh dotfiles config managing two Macs (personal macOS Tahoe M-series, work macOS Sequoia M-series) via Dotbot.

## Current Progress

### Session 1: Zsh Config Audit (19/19 tickets closed)

All issues resolved and merged to master. See `docs/solutions/code-quality/zsh-configuration-audit-19-issues.md` for full details.

- **Bugs:** Fixed doubled PATH, undefined CARGO_HOME, duplicate RVM PATH entry, removed bash-only history variables.
- **Performance:** Removed unreachable brew lazy loader, lazy-loaded NVM (~200-400ms saved), guarded tmux restoration, removed double compinit.
- **Duplicates:** Deleted options.sh, removed duplicate LANG and PYENV_ROOT exports.
- **Cleanup:** Consolidated PAGER, FZF/RVM lazy loaders, removed hardcoded TERM, dead code.
- **Tooling:** Replaced Kymsu with Topgrade. Created GitHub Project board and `/ticket` command.

### Session 2: Work Mac Sync & Cross-Machine Fixes

Work Mac synced and several issues resolved. See `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md` for full details.

- **gcloud SDK:** Corporate SSL interception broke install. Fixed by using system Python (`CLOUDSDK_PYTHON=/usr/bin/python3`).
- **Brewfile install:** `$HOMEBREW_BREW_FILE` unreliable across Homebrew versions. Changed to use `brew` directly.
- **Starship timeout:** `command_timeout` moved from per-module to global top-level setting.
- **NVM lazy loader:** Added `claude` shim so Claude Code works without running `node` first.
- **PATH dedup:** Added `typeset -U PATH` to zshenv.
- **Pyenv lazy loader:** Consolidated to `_load_pyenv` helper pattern (done by work Mac Claude).
- **gitconfig:** Committed lingering GCM credential helper changes.
- **pkgconf:** x86_64 bottle on arm64 Mac — `brew reinstall pkgconf` on work Mac.
- **_brew_services:** Missing completion file regenerated via `brew services`.

### Workspace State

Clean. All changes committed and pushed to origin/master.

## What Worked

- **Branch-per-ticket workflow**: Clean history, easy to review
- **Test before commit**: User verified each change with `exec zsh` before committing
- **Topgrade** as Kymsu replacement: auto-detects installed package managers, zero config needed
- **System Python for corporate SSL**: `CLOUDSDK_PYTHON=/usr/bin/python3` bypasses corporate CA issues
- **`~/env.sh` for machine-specific overrides**: Keeps corporate config out of the repo

## What Didn't Work

- **Worktree agents for code changes**: Agents in isolated worktrees couldn't run `git commit` due to bash permission restrictions.
- **`$HOMEBREW_BREW_FILE`**: Not reliably set by `brew shellenv` — use `brew` directly.
- **`REQUESTS_CA_BUNDLE` / `SSL_CERT_FILE` for gcloud**: gcloud SDK ignores these, uses bundled Python SSL.
- **`pip3 install certifi`**: PEP 668 blocks system-wide pip installs on Homebrew Python.

## Next Steps

1. **Periodic audit**: Use the checklist in `docs/solutions/code-quality/zsh-configuration-audit-19-issues.md`
2. **Work Mac sync checklist**: Use the checklist in `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md`
3. **NVM shim maintenance**: When adding new npm global CLIs, add them to the lazy loader shim list in zshrc
4. **Corporate CA bundle**: Consider building a combined CA bundle (`~/.config/ssl/combined-ca-bundle.pem`) for broader tool coverage on work Mac

## SOPs (saved in memory)

- Always create a new branch when picking up a ticket
- Always ask user to test before committing
- Close GitHub issues as part of the commit/merge workflow
