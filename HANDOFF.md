# HANDOFF — 2026-04-20 (late morning PST, multi-day session continuation)

## What We Built

### Shipped to master (3 PRs, 3 merged, no carry-overs)

**PR #38 `cae28d3` — Native Claude Code installer replaces Homebrew cask.**
- Dropped `cask "claude-code"` from `brew/Brewfile`
- Added `helpers/install_claude_code.sh`: idempotent native-installer wrapper (`curl -fsSL https://claude.ai/install.sh | bash`). Skips if `~/.local/bin/claude` already exists, Darwin-only guard, `DOTFILES_DRY_RUN=1` preview path.
- Wired into `install.conf.yaml` shell block after `install_node.sh`.
- Drive-by fix: removed orphan `~/.claude/commands/ticket.md` symlink from `install.conf.yaml:74` (source file was deleted in `5128f6a` on 2026-04-15 but the symlink line was left behind, making `./install --dry-run` exit non-zero with "Nonexistent target" for 3 days).
- Rationale: Homebrew cask has been perpetually weeks behind upstream. This session caught it stuck on 2.1.98 while `~/.local/bin/claude` (native installer) was already on 2.1.114. PR #36/#37 from yesterday made PATH prefer `~/.local/bin`, so the cask was redundant baggage.

**PR #39 `3a2e1bf` — tmux-attention hook: spinner-cleanup race + `asking` state.**
- Race condition fix in `claude/hooks/tmux-attention.sh`: the spinner's disowned bg loop had an unconditional cleanup block that unset `@claude_status` on exit — which raced the main-thread `waiting` action's state write, producing blank tabs during permission-request holds. Bash prompts resolved <1s so the flash was invisible; AskUserQuestion holds for tens of seconds and exposed the bug fully. Fix: gate bg-loop cleanup on `[ ! -f "$sentinel" ]` — if sentinel was removed, another caller owns state; exit quietly.
- Initial hypothesis "missing `Notification` hook wire" was refuted in 30 seconds by adding 6 lines of stdin-capture diagnostic to `/tmp/claude-hooks.log`. Ground-truth: `AskUserQuestion` fires `PermissionRequest` with `tool_name=AskUserQuestion` — existing wire WAS catching it; blank-tab was downstream.
- Initial `asking` implementation used `timeout 0.3 cat | python3 json.load` to peek stdin and route `AskUserQuestion` to a distinct yellow-question-mark state while Bash permission stayed amber warning.
- Tmux config `tmux/tmux.display.conf`: new `asking` ternary branch (bright yellow `#F5C300`, U+F128 question-circle glyph) ahead of `waiting`. PUA glyph injected via `python3` heredoc to bypass Claude Code's Edit/Write PUA-stripping bug.

**PR #40 `8953ff4` — compound doc + unified `asking` routing + review-finding fixes.**
- `/ce:compound` run in full mode with session-historian: produced `docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md` (~170 lines after review fixes). Session historian recovered the 2026-04-09 hook-construction session's dead ends (`exec -a` on macOS bash 3.2, pidfile-pkill misses, Stop-only clear trigger) for the "prior sessions" section.
- Simplified routing: dropped the stdin-peek machinery entirely; every `PermissionRequest` now renders `@claude_status=asking` (yellow `\uf128`). Triggered by Image #2 user feedback showing Bash-tool-use permission prompts where the tab glyph was wrong/missing — both AskUserQuestion and Bash tool permissions are semantically "user decision needed," so one visual is clearer than two. Net -15 lines in the hook.
- Refresh of `docs/solutions/code-quality/claude-code-hook-stdio-detach.md`: added forward-pointer "See Also" section flagging that its bg-loop recipe is necessary but NOT sufficient — cleanup blocks need sentinel-gated exit.
- `CLAUDE.md` tmux tab indicator section updated to reflect the unified model.
- Review round 1 (2 findings): fixed stale `asking`-for-AskUserQuestion-only comment in `tmux/tmux.display.conf:65-66`; broadened "Fix" and "Key Takeaway" in `claude-code-notification-hook-false-positives.md` to note `AskUserQuestion` also arrives via `PermissionRequest` (distinguishable by `tool_name`).
- Review round 2 (P3 finding): fixed stale `600s` max-runtime claim at `tmux-attention.sh:32` → now reads `~5 min: 2000 iterations × 150ms`, matching the actual `max_iterations=2000` constant and CLAUDE.md's 5-minute cap.

### Operational events (not commits)

- **Branch cleanup:** audited 4 stale local branches (2 squash-merged `fix/*` branches, 2 `worktree-agent-*` ancestors of master); deleted all 4 with explicit approval. Repo is clean single-branch state.
- **Vercel plugin drift in `claude/settings.json`** observed mid-session: `enabledPlugins` gained `"vercel@claude-plugins-official": true` plus `extraKnownMarketplaces` gained a `claude-plugins-official` entry. Reverted for this PR per the established "don't commit settings-drift" rule. User has NOT decided whether to keep the Vercel plugin — the drift is still in the working directory's git status noise on next session.

## Decisions Made

- **Native Claude Code installer is authoritative over Homebrew cask.** Cask retired from Brewfile; `~/.local/bin/claude` wins PATH resolution per PR #36/#37 ordering. Claude Code's own auto-updater handles upgrades after bootstrap; helper only runs on fresh machines.
- **Linux install config untouched.** `install-linux.conf.yaml` doesn't install Claude Code — `~/.claude/*` is Darwin-only per dotfiles convention. No change needed for VPS or future Linux hosts.
- **All `PermissionRequest` events render the same `asking` visual.** Earlier design split AskUserQuestion (yellow `?`) from tool-permission (amber warning) via stdin-peek. Collapsed to one state because Bash tool permissions and structured choice prompts have identical UX intent (user is blocked on a decision). Removed ~15 lines of machinery + eliminated the stdin-parse failure mode. The tmux ternary's `waiting` branch stays in place as *reserved* state for future non-permission attention events (e.g., `Notification`, if ever wired).
- **Spinner bg-loop cleanup is now gated by exit reason.** If the sentinel was removed (requested exit), the caller owns state; bg loop exits quietly. If parent died or max-iter cap hit (unplanned exit), bg loop owns its own cleanup. This is the general pattern worth remembering: *requested exit → requester owns state; unplanned exit → worker owns cleanup.*
- **Hook-event stdin is the authoritative source for Claude Code event metadata.** `tool_name`, `tool_input`, `session_id`, `permission_mode`, `permission_suggestions`, `transcript_path` are all on the JSON line written to the hook's stdin. When future hook work needs to disambiguate sub-cases, `timeout 0.3 cat | python3 -c 'json.load(sys.stdin)...'` is the cheap safe pattern.
- **Squash-merge remains the convention.** All 3 PRs this session went through `gh pr merge --squash --delete-branch`. Net cost: multi-commit PRs (#38 had orphan-symlink-fix + feat; #40 had 3 commits) collapse to a single master commit. Separation is lost but repo history stays clean.

## What Didn't Work

- **"Missing `Notification` hook wire" hypothesis for the blank-tab symptom.** Refuted in 30 seconds by diagnostic stdin-capture — `PermissionRequest` WAS firing for AskUserQuestion with `tool_name=AskUserQuestion`. Real root cause was downstream in the bg-loop cleanup race. This is another instance of the pattern captured in the 2026-04-14 *reproduce-then-attribute* and 2026-04-16 *inspect runtime truth* learnings — diagnostic-first beats theory-first for hook/IPC bugs.
- **Initial `tool_name`-specific routing (stdin peek + `python3 json.load` to split AskUserQuestion → asking, else → waiting).** Shipped in #39. User feedback on the Bash permission UI (Image #2) made it clear both scenarios have identical UX intent; splitting them was noise. Collapsed to unconditional `asking` in #40 and removed the stdin-peek entirely. Retrospective lesson: when two states have identical UX meaning, collapse them — don't invent distinctions the user can't perceive.

## What's Next

Carry-forward + new:

1. **Vercel plugin drift in `claude/settings.json`** — uncommitted additions (`"vercel@claude-plugins-official": true` + `claude-plugins-official` marketplace). User decision needed: keep (commit separately as `chore: enable Vercel plugin`) or discard (`git restore claude/settings.json`). Will surface on next `/pickup` as git-status noise until resolved.
2. **Backfill VPS runbook** — one-liner in `docs/solutions/cross-machine/vps-dotfiles-target.md` near the sync-workflow section noting the `sync-vps.yml` dry-run semantic. Still from the 2026-04-18 handoff. Low effort.
3. **`sync-vps.yml` tailnet ping flakiness** — GH Actions' tailnet join step has failed the ping check 2+ times. Worth investigating: pin `version:` instead of `latest`, add retry, or swap to ICMP-less connectivity check.
4. **OpenClaw-gateway memory leak** — not dotfiles work, belongs in an openclaw session. Symptom-mitigation would be a pre-OOM guard cron. Causal fix needs heap profiling.
5. **Syncthing healthcheck misconfig on VPS** — probes port 8384 (admin UI hardened off); always-failing. Fix: swap to `nc -z 127.0.0.1 22000` or remove the check. Openclaw repo.
6. **OAuth secret rotation reminder** — 2027-04-14 runbook in `docs/solutions/cross-machine/vps-dotfiles-target.md`.

## Gotchas & Watch-outs

- **`~/.claude/hooks/tmux-attention.sh` is a live symlink** to the file in this repo. Any edit is immediately live for the running Claude Code session — useful for diagnostic logging (we exploited this to capture hook events in 30 seconds), but also means typos land instantly. Always `bash -n` the file after edits.
- **Hook stdin-capture diagnostic pattern is reusable.** Add `{ printf '[%s] action=%s pane=%s\n' "$(date -Iseconds)" "$action" "${TMUX_PANE:-none}"; timeout 0.3 cat 2>/dev/null || true; printf '\n---\n'; } >> /tmp/claude-hooks.log 2>/dev/null || true` to the top of the hook (after `action="${1:-}"`). Reproduce the event, `tail -200 /tmp/claude-hooks.log` or awk-parse. **Always revert before committing.** `timeout 0.3` bounds the read so manual invocations without stdin don't hang.
- **Claude Code Write/Edit strips PUA glyphs.** Use `python3` heredoc or `printf '\xef\x84\xa8'` (raw UTF-8 bytes) for Nerd Font / FA injection. Documented at `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md`.
- **`@claude_status=waiting` branch in the tmux ternary is reserved, unreachable from current code paths.** Kept as future-proofing, NOT because anything writes it. If you add a new attention hook (e.g., wire `Notification`), you could write `state="waiting"` to distinguish it visually from `asking`.
- **Squash-merges hide multi-commit structure on master.** PR #40 had 3 commits (feat, docs, fixup); master has 1 squashed commit. If you need to archaeologically find "when was the stdin-peek dropped" vs "when was the compound doc written," check the PR timeline in GitHub, not `git log`. Commit message on master covers both but doesn't separate them.
- **Session spans 3 calendar days (2026-04-18 evening → 2026-04-20 late morning PST).** Previous handoff was 2026-04-18 afternoon; we continued through to this morning's PR #40 merge. HANDOFF.md mtime may suggest "older than it is" to the next `/pickup` — the session has been live but with context-hygiene breaks.
- **`claude/settings.json` accumulates** per-session plugin/permission grants. Vercel plugin noted above is today's instance. If `git diff claude/settings.json` ever shows a growing `permissions.allow` block or new plugin entries, don't commit without explicit user intent.
- **`/ce:compound` full-mode is token-heavy.** This session ran it once with session-historian + full parallel research subagents. Worth it for durable race-pattern + empirical hook knowledge, but lightweight mode may be preferable for simpler fixes going forward.
- **`docs/solutions/runtime-errors/` is a new category directory** created this session (first entry is the tmux-attention writeup). Future runtime bugs belong here.
