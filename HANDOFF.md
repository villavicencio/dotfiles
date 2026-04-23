# HANDOFF — 2026-04-23 (same-session continuation of 2026-04-22 work)

## What We Built

### Shipped to master (2 direct-push commits, pushed to origin)

**`00cd6bf` — drop needless backslash in statusline tildify.** `claude/statusline-command.sh:9` was rendering `\~/Projects/...` with a literal backslash because PR #45's tildify used `\~` as the replacement (only the delimiter needs escaping in parameter expansion, tilde doesn't). Caught visually in a screenshot during earlier architecture discussion. One-char change, immediately visible improvement on every Claude Code statusline render.

**`07c974e` — enable fullscreen TUI mode.** `claude/settings.json` — your pre-existing `"tui": "fullscreen"` line, uncommitted since at least session start. Settled the dangling diff.

### Attempted and reverted — issue #46 ccusage statusline work

Built a working prototype on `feat/ccusage-statusline` (branch now deleted). Rewrite sourced block/proj/remaining from `ccusage blocks --json --active --token-limit max --offline` via an async-refreshed on-disk cache (30s TTL, lockfile to prevent overlapping refreshes). Render pattern: `cwd |  branch | Opus 4.7 | blk 17%→64% · 3h27m | ctx 42%` with color on `max(current, projected)`.

Reverted after concluding the complexity wasn't justified — documented in detail in the #46 closing comment. Summary:
- ccusage cold-scan is 8–15s, not the ~300ms I assumed. Async refresh works but means the first render after each stale window has no block segment.
- `--token-limit max` is ccusage's "historical personal peak," not the Anthropic MAX plan ceiling — no flag exists for plan-ceiling %.
- Existing Claude sessions went blank after the rewrite (even after `claude --continue`). Script worked correctly when invoked directly; root cause not identified. Silently breaking existing sessions for a nicety is a bad trade.

Branch deleted, `ccusage` uninstalled from Homebrew, `/tmp/ccusage-block-*` cleaned up, issue #46 closed with permanent rationale.

### Ideation session (no artifact written)

Ran `/ce:ideate` open-ended. 4 parallel agents, 40 raw candidates → 6 survivors after adversarial filtering:
1. Claude Code hook SDK (`claude/hooks/lib/sentinel.sh`)
2. Compound the solutions corpus (critical patterns index + runtime-assertion companion pipeline)
3. Declarative machine identity (`machine.toml` → generators for env.sh/gitconfig.local/etc.)
4. tmux config linter (`helpers/lint_tmux.sh`)
5. Single-source config registry (OMZ + NVM shims)
6. `./install doctor` subcommand

You dropped the set before writing the artifact. Nothing preserved on disk. Surfaces are documented in this handoff for posterity; if revisited, `/ce:ideate` from scratch will re-ground against whatever the repo looks like.

## Decisions Made

- **Reverted ccusage integration entirely rather than iterate.** The combination of "8-15s cold scan doesn't fit sub-second hooks," "`--token-limit max` ≠ plan ceiling," and "existing sessions went blank with no root cause" crossed the bar for "this is adding more complexity than value." Issue #46 closed with the investigation captured so the ground isn't re-trod.
- **Labeling arrow `blk X%→Y%` beats slash `blk X%/Y%`.** The slash read ambiguously as a fraction; the arrow reads "heading from X to Y." Never shipped because of revert, but the conclusion holds for any future block-style segment.
- **Branch truncation at 20 chars with `…`** is the right balance — no-op for short branches, keeps long feature-branch statuslines under 100 chars. Never shipped.
- **Never sync `~/.claude/*` to VPS.** Came up during ideation; rejected as "partially covered by existing install-linux.conf.yaml exclusion design — agent workloads on VPS aren't near-term pressure." Captured here so it doesn't get re-proposed.
- **Stripping `(1M context)` from model display** never shipped but was correct — the ctx% segment already communicates window usage; the `(1M)` is duplicative noise.
- **6 ideation survivors not preserved** per your call. No `docs/ideation/` artifact created. If you want any of the six without re-running ideation, names above are the reminder.

## What Didn't Work

- **`ccusage statusline` subcommand for percentages.** Silently accepts `--token-limit max` but still renders dollars only. No way to get block-% out of the statusline subcommand.
- **`jq fromdateiso8601` on ccusage endTime.** Rejected the `.NNNZ` millisecond suffix with "does not match format." Workaround: `.endTime | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601`. Small reusable nugget for any modern-API ISO-8601 parsing.
- **`--since today` to shrink ccusage scan window.** Broke `tokenLimitStatus` (returned null or wrong values) because it needs full history to compute the historical-max denominator. No date-range shortcut available.
- **Synchronous cache-miss path for ccusage.** First idea was "cache for 2s, block on miss." 8-15s per miss blocks Claude's render loop. Had to pivot to async background refresh with stale-cache serving.
- **`npx -y ccusage@latest` per invocation.** Adds 300-800ms cold-start on every statusline render. Homebrew install was the right answer (native binary at `$BREW_PREFIX/bin/ccusage`).
- **`--config` subcommand on ccusage 18.0.11.** Doesn't exist despite `--config <file>` flag appearing in help. No per-user TOML config path.

## What's Next

Prioritized:

1. **Nothing ticket-scoped is in flight.** Board is clean, no open PRs, no pending Forge tickets in `dotfiles/pending/`. You're in a zero-inbox state for this project.
2. **Six ideation candidates exist in this conversation only** (see "What We Built" above). If any look interesting tomorrow, re-run `/ce:ideate` to ground against current state rather than rely on recall.
3. **OpenClaw MCP-reaper leak + Syncthing healthcheck** — carry-forward from 2026-04-21, not dotfiles-scoped. Routes to openclaw-forge sessions.

## Gotchas & Watch-outs

- **Claude Code statusline edits can blank existing sessions.** Observed on 2026-04-23 after rewriting `claude/statusline-command.sh`: pre-existing sessions rendered blank statusline even after `claude --continue`. Script worked correctly when invoked directly with matching stdin (verified via manual echo-pipe). Root cause not identified. **Before shipping any future statusline change, test from a brand-new `claude` invocation in a fresh terminal — don't trust `--continue`.** Also worth replacing the script with a known-good one-liner (`printf "HELLO"`) to isolate Claude vs script if the behavior recurs.
- **`ccusage` is not suitable for sub-second hooks.** Cold scan is 8-15s because it reads all JSONL transcripts on every invocation. Built-in `ccusage statusline` has its own 1s cache (0.3s cached calls) but only renders dollars, not percentages. Any future ccusage-in-hot-path attempt needs async refresh architecture from the start.
- **`ccusage --token-limit max` means "historical personal peak," not "Anthropic plan ceiling."** The docs don't clearly label this. Plan-ceiling % is not available via any ccusage flag at 18.0.11. Weekly all-models % is not available via any stable official interface.
- **`jq fromdateiso8601` rejects millisecond-suffixed ISO-8601.** Any timestamp from a modern API that looks like `2026-04-23T21:00:00.000Z` needs `sub("\\.[0-9]+Z$"; "Z")` stripping before parsing. Small nugget, reusable across the repo for any jq ISO-8601 parse.
- **Carry-forward from prior sessions** (still valid): `##`-escape rule for hex colors in `#{?...}` ternaries; `tmux display-message -p '<format>'` as the canonical diagnostic; straight-to-master pushes do NOT auto-trigger `sync-vps.yml` (use `gh workflow run sync-vps.yml -f host=openclaw-prod -f dry_run=false`); `/handoff` skill stale-render risk if skill file edited mid-session.
- **`"tui": "fullscreen"` is now committed.** If future settings.json changes introduce a different tui value, review the diff carefully — this line is the default now and silent overrides will be easy to miss.
