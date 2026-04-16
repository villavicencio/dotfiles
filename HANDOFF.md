# HANDOFF — 2026-04-16 (session 1)

## What We Built

### Shipped to master (1 commit this session)

- **`8c17d6b` — Remove `CLAUDE_CODE_ENABLE_TELEMETRY=1` from `claude/settings.json`.** Supersedes `5128f6a` from the previous session, which had added the flag under the (now disproven) belief that it upgraded the OAuth prompt cache TTL from 5min to 1h.
  - **Empirical disproof:** 41 pre-`5128f6a` sessions across 5 projects (openclaw, dataworks-website, dotfiles, Gooner, a top-level misc one) showed 0 writes to the 5m cache tier and 121M writes to the 1h tier — 100.0% 1h on every historical main-thread session. 1h is the Claude Code OAuth default in 2.1.111, not a reward for telemetry opt-in.
  - **Post-removal verification:** fresh session after the flag was removed ran 61 turns at 100.0% 1h tier. Flag removal had zero effect on cache behavior.
  - **What the flag actually is:** a gatekeeper for OpenTelemetry export. No-op without `OTEL_*` companion vars (`OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`), which this repo does not set. No Anthropic Console dashboard exists for Claude Code CLI.
  - Full methodology + jq inspection recipes + prevention checklist in `docs/solutions/code-quality/claude-code-telemetry-flag-does-not-affect-cache-ttl.md`.
  - Forge project memory note corrected on openclaw-prod (`workspace-forge/projects/dotfiles/context.md`).
  - Local auto-memory updated: `memory/claude_code_cache_inspection.md` holds the jq recipes and empirical finding.

## Decisions Made

- **Remove the flag rather than repurpose it.** Keeping `CLAUDE_CODE_ENABLE_TELEMETRY=1` as a "future-proof gate in case we set up OTel later" was rejected — dead config is a trust hazard and the next reader will assume it's load-bearing. If/when a local OTel collector is stood up, the flag can return alongside the companion vars that make it meaningful.
- **New HANDOFF instead of editing the old one.** Last session's handoff documented the flag being added "for 1h cache" as fact; rewriting history in place would be misleading. This handoff replaces it cleanly — the prior commit message and the solution doc preserve the full story.
- **Compound doc emphasizes method, not just fix.** The more durable lesson isn't "remove telemetry" — it's "claims of the form *knob X causes runtime behavior Y* must be proven from runtime data before being documented as fact." That framing is the hedge against a repeat.

## What Didn't Work

- **The original 5128f6a commit was based on an unverified claim.** A plausible-sounding trade-off narrative ("tell Anthropic more about your usage → they let your cache live longer") was accepted into a commit message, a handoff, a Forge note, and a pickup briefing — all before anyone ran a `jq` over `~/.claude/projects/*/**.jsonl` to check. Everything after the first misstep compounded the error.
- **Two `claude-code-guide` subagents disagreed about whether 1h cache was on.** The disagreement alone should have been a signal. Doc-derived subagent answers are not a substitute for transcript inspection when the question is about observable runtime behavior.

## What's Next

Carried forward from the previous session (still relevant):

1. **Cross-machine sync test on the work Mac.** Run `./install` on the FedEx Mac to verify the Dotbot v1.24.1 bump, the OS-detect wrapper, and all fixes from the last three sessions (SC2218 hoist, deprecated taps, osx/ removal, settings.json env-block removal) behave identically. Acceptance: no symlink changes, idempotent second run, Brewfile step completes without deprecated-tap errors.
2. **VPS sync.** Master is now multiple commits ahead of the last VPS sync (including `5128f6a`, `689811d`, `8c17d6b`). When ready: `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true` → review step summary → `-f dry_run=false`.
3. **OAuth secret rotation reminder — 2027-04-14.** Runbook in `docs/solutions/cross-machine/vps-dotfiles-target.md` has the procedure.
4. **Optional follow-ups** (no tickets yet):
   - Sidecar rename cleanup for orphaned entries in `~/.config/tmux/window-meta.json`.
   - Self-hosted OTel collector for Claude Code usage dashboards. Would resurrect a reason to set `CLAUDE_CODE_ENABLE_TELEMETRY=1` alongside the companion vars. Scope: a Prometheus+Grafana stack or similar, per-session token/cache-hit-rate views.
   - VPS OOM regression (out of scope for dotfiles; belongs to openclaw).

## Gotchas & Watch-outs

- **`claude/settings.json` accumulates per-session permission grants.** If you see a bloated `permissions.allow` block in `git diff`, do NOT commit it. Restore with `git checkout -- claude/settings.json`.
- **1h cache is on by default — don't re-enable telemetry "for the cache."** If the urge returns, re-read `docs/solutions/code-quality/claude-code-telemetry-flag-does-not-affect-cache-ttl.md` first. The flag is only worth setting if you've also stood up an OTel backend.
- **Work Mac runs through Vertex (`CLAUDE_CODE_USE_VERTEX=1`).** Cache-tier behavior is governed by Vertex there, not OAuth. The analysis in this handoff is OAuth-specific.
- **VPS health may still be degraded.** Last openclaw session recorded 7 OOM events in 24h, RestartCount: 7, memory.current at 73% of cgroup ceiling. Not addressed (out of scope for dotfiles). If next pickup is on openclaw, investigate first.
