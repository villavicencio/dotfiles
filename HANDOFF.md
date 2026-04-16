# HANDOFF — 2026-04-15, evening (session 2)

## What We Built

### Shipped to master (1 commit this session)

- **`5128f6a` — Remove repo-specific `/ticket` command, enable telemetry for 1h cache.** Two changes in one commit:
  1. Deleted `claude/commands/ticket.md` — was hardcoded to `villavicencio/dataworks-website` with the wrong repo, wrong project ID (`PVT_kwHOAA0r6c4BRJW-` instead of `PVT_kwHOAA0r6c4BRdxZ`), and dataworks-specific labels/Figma refs. Too project-specific for a global slash command. Removed rather than fixed — use `gh issue create` directly when needed.
  2. Added `env.CLAUDE_CODE_ENABLE_TELEMETRY: "1"` to `claude/settings.json` to upgrade OAuth prompt cache TTL from 5 minutes to 1 hour. Takes effect on next session (not the current one). Trade-off: sends anonymized usage telemetry (session metadata, tool use counts, token counts — not prompt content) to Anthropic.
  3. Updated `CLAUDE.md` — removed "ticket" from the commands list (line 40) and the `/ticket` reference from the project board section (line 178).

## Decisions Made

- **`/ticket` removed entirely, not fixed.** The command was 112 lines of dataworks-website-specific workflow (labels, Figma references, project board mutation). Fixing it for dotfiles would still leave a command that's too project-specific for a global config. The right pattern is `gh issue create` directly, or a project-local command definition if a project needs one.
- **Telemetry enabled via `settings.json` env block, not shell env.** `claude/settings.json` is symlinked to `~/.claude/settings.json` and version-controlled. This makes the setting portable across machines (except work Mac where `CLAUDE_CODE_USE_VERTEX=1` means OAuth caching doesn't apply anyway). Alternative was adding to `zsh/zshenv` — rejected because it's a Claude Code setting, not a shell setting.

## What Didn't Work

Nothing failed this session — both changes were straightforward.

## What's Next

Priority-ordered (carried forward from previous session where still relevant):

1. **Cross-machine sync test on the work Mac.** Run `./install` on the FedEx Mac to verify Dotbot v1.24.1 bump, the OS-detect wrapper, and all fixes from the previous session (SC2218 hoist, deprecated taps, osx/ removal) plus this session's settings.json change behave identically. Acceptance: no symlink changes, idempotent second run, Brewfile step completes without deprecated-tap errors.
2. **VPS sync.** Master is now 4 commits ahead of the last VPS sync. When ready: `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true` → review step summary → `-f dry_run=false`.
3. **OAuth secret rotation reminder — 2027-04-14.** Runbook documents the procedure.
4. **Optional follow-ups** (no tickets yet):
   - Sidecar rename cleanup for orphaned entries in `~/.config/tmux/window-meta.json`.
   - Investigate VPS OOM regression (7 OOM events in past 24h, RestartCount: 7, memory at 73% of cgroup ceiling). This belongs to the openclaw project, not dotfiles.

## Gotchas & Watch-outs

- **`claude/settings.json` accumulates per-session permission grants.** If you see a huge `permissions.allow` block in `git diff`, do NOT commit it. Restore with `git checkout -- claude/settings.json`. This will happen every time permissions are granted during a session.
- **Telemetry setting takes effect next session.** The current session was initialized without it. Don't expect 1h cache until you start a new session.
- **Work Mac telemetry caveat.** `CLAUDE_CODE_USE_VERTEX=1` on the work Mac routes through Vertex, not OAuth. The telemetry-for-cache trade-off is OAuth-specific. The env var in settings.json is harmless on the work Mac (telemetry still sends, but cache TTL is governed by Vertex's own rules).
- **VPS health was degraded last session.** 7 OOM events in 24h, RestartCount: 7, memory.current at 73% of cgroup ceiling. Not addressed (out of scope for dotfiles). If next pickup is on openclaw, investigate first.
