# HANDOFF — 2026-04-15, evening

## What We Built

### Shipped to master (3 commits this session)

- **`bd65cf0` (PR #26 merged) — Fix SC2218 in `helpers/install_tmux.sh`.** Hoisted `log_message()` and `handle_error()` definitions above their first use at line 17. Previously, a failed `touch "$LOG_FILE"` would emit `handle_error: command not found` (exit 127) and silently continue because the script doesn't use `set -e`. Now aborts cleanly via `handle_error`. `log_message` hoisted first because `handle_error` calls it. Verified: `shellcheck -x` clean, `bash -n` clean, `./install` idempotent on personal Mac. Closes #23.
- **`994d1c8` (PR #29 merged) — Remove deprecated `homebrew/bundle` and `homebrew/services` taps from `brew/Brewfile`.** Both taps were deprecated by Homebrew; declaring them caused hard errors: `brew bundle` failed → `install_packages.sh` failed → Dotbot reported "Some commands were not successfully executed." Two-line delete. Verified: `./install` now reports `brew bundle complete! 101 Brewfile dependencies now installed.` Closes #27.
- **`5287a0d` (PR #30 merged) — Delete stale `osx/install.sh`.** Pre-Dotbot-era bootstrap script, last touched 2022-02-08, unreferenced by anything in the current install pipeline. Also carried four deprecated Homebrew tap declarations. Whole `osx/` directory removed (it was the only file). Recoverable from git history. Closes #28.

### Tickets filed this session

- **villavicencio/dotfiles#25** — "Enable Claude Code remote control by default in every new session." Filed from Forge pending ticket. Resolved immediately: one-time `/config` → "Enable Remote Control for all sessions" → `true`. Setting persists in `~/.claude.json` (not `~/.claude/settings.json`). Work Mac excluded — `CLAUDE_CODE_USE_VERTEX` blocks Remote Control. Closed.
- **villavicencio/dotfiles#27** — "Remove deprecated homebrew/bundle and homebrew/services taps from Brewfile." Surfaced during `./install` testing of PR #26. Closed via PR #29.
- **villavicencio/dotfiles#28** — "Decide fate of stale osx/install.sh." Surfaced during scope-check for #27. Decision: delete. Closed via PR #30.

### All four issues from this session are closed

| # | Title | Resolution |
|---|---|---|
| #23 | SC2218 hoist in install_tmux.sh | PR #26 merged |
| #25 | Enable Claude Code remote control | `/config` toggle, no code change |
| #27 | Remove deprecated Brewfile taps | PR #29 merged |
| #28 | Remove stale osx/install.sh | PR #30 merged |

## Decisions Made

- **`remoteControlAtStartup` lives in `~/.claude.json`, NOT `~/.claude/settings.json`.** Discovered by grepping the Claude Code binary (v2.1.92). The `/config` toggle writes to the global user config, not the symlinked settings file. This means it cannot be version-controlled via dotfiles — it's a one-time per-machine toggle. Decided: just run `/config` once per machine rather than engineering a helper script to jq-patch `~/.claude.json` during `./install`. The helper approach was evaluated and rejected as overengineering for a 5-second one-time action.
- **Remote Control does not work with Vertex/Bedrock/Foundry routing.** The docs are explicit: "Remote Control requires claude.ai authentication and does not work with third-party providers." Work Mac has `CLAUDE_CODE_USE_VERTEX=1`. Setting the toggle globally is harmless (it doesn't crash session startup — just doesn't register the remote session), but should not be relied upon on the work Mac.
- **`osx/install.sh` deleted, not revived.** 4+ years without a change, nothing references it, and the current Dotbot + helpers pipeline is the documented and tested path. Recovery from git history is trivial if ever needed.
- **Accumulated permission grants in `claude/settings.json` should NOT be committed.** The `/config` command wrote a large `permissions.allow` block containing per-session ad-hoc allows. These are machine-specific and ephemeral. Caught during the `git status` for PR #30 and restored via `git checkout --`.

## What Didn't Work

- **Binary introspection of Claude Code to find the settings key was messy.** The Mach-O binary contains minified JS with heavy bundled dependencies (Azure SDK, Node.js internals, etc.). `strings | grep` returned massive amounts of noise. Eventually found `remoteControlAtStartup` via `awk` with narrow context windows around "Enable Remote Control" matches. Viable but took ~10 attempts to get clean output — the persisted-output system kept saving truncated previews of the wrong buffer. For future reference: dump strings to a temp file first, then awk with narrow substr windows.
- **The `claude-code-guide` agent claimed "No dotfiles/settings.json key exists for this."** This was directionally correct (the key doesn't live in settings.json) but the reasoning was wrong — the agent didn't know where `/config` actually writes. The binary grep was more reliable than the agent for this specific question.

## What's Next

Priority-ordered:

1. **Cross-machine sync test on the work Mac.** Run `./install` on the FedEx Mac to verify Dotbot v1.24.1 bump, the new OS-detect wrapper, and all three fixes from this session (SC2218 hoist, deprecated taps, osx/ removal) behave identically. Acceptance: no symlink changes, idempotent second run, Brewfile step completes without deprecated-tap errors.
2. **Regular VPS sync cadence.** Master now has 3 new commits since the last VPS sync. When ready: `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true` → review step summary → `-f dry_run=false`.
3. **Fix `claude/commands/ticket.md`** — still copy-pasted from the dataworks-website config (wrong repo `villavicencio/dataworks-website`, wrong project ID `PVT_kwHOAA0r6c4BRJW-`). Should point to `villavicencio/dotfiles` and project ID `PVT_kwHOAA0r6c4BRdxZ`. Workaround this session: used `gh issue create` directly.
4. **OAuth secret rotation reminder — 2027-04-14.** Runbook documents the procedure.
5. **Optional follow-ups** (no tickets yet):
   - Sidecar rename cleanup for orphaned entries in `~/.config/tmux/window-meta.json`.
   - Investigate VPS OOM regression (7 OOM events in past 24h, RestartCount: 7, memory at 73% of cgroup ceiling). This belongs to the openclaw project, not dotfiles.

## Gotchas & Watch-outs

- **`claude/settings.json` accumulates per-session permission grants.** If you see a huge `permissions.allow` block in `git diff`, do NOT commit it. Restore with `git checkout -- claude/settings.json`. This will happen every time `/config` is run or permissions are granted during a session.
- **`remoteControlAtStartup` is in `~/.claude.json`, not `~/.claude/settings.json`.** If someone asks "why isn't Remote Control in the dotfiles settings?", this is why — it's in a different config file that contains per-machine state and shouldn't be version-controlled.
- **VPS health was degraded at session start.** 7 OOM events in 24h, RestartCount: 7, memory.current at 73% of cgroup ceiling. Not addressed this session (out of scope for dotfiles). If next pickup is on openclaw, investigate first.
- **Dotbot v1.24.1 is quieter by default.** Verify idempotency by diffing `find ~/.config ~/.claude -type l`, not by log-line counting.
- **Don't use `tailscale up --advertise-tags=` for initial tag assignment.** Admin-assign from UI instead. See `docs/solutions/cross-machine/tailscale-tag-acl-ssh-failure-modes.md`.
- **`chsh` fails during `./install`** on personal Mac (password prompt in non-interactive context). Harmless — shell is already zsh. Pre-existing, not worth fixing.
