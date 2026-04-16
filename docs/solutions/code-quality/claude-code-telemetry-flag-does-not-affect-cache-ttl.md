---
title: "CLAUDE_CODE_ENABLE_TELEMETRY does not upgrade OAuth prompt cache TTL — 1h is the default"
date: 2026-04-16
category: code-quality
tags:
  - claude-code
  - settings
  - prompt-cache
  - telemetry
  - empirical-verification
severity: Low
component: "claude/settings.json env block; Claude Code OAuth prompt caching"
symptoms:
  - A previous commit added `CLAUDE_CODE_ENABLE_TELEMETRY=1` to `claude/settings.json` with the commit message "enable telemetry for 1h cache"
  - HANDOFF notes, Forge project memory, and `/pickup` briefings all asserted that the flag upgrades the OAuth prompt cache from 5-minute TTL to 1-hour TTL
  - The underlying claim was never empirically verified — it was propagated across three docs and two sessions as fact
  - One subagent contradicted the claim ("1h cache is off; you need `ENABLE_PROMPT_CACHING_1H=1`"); another agreed after inspecting actual transcripts ("1h is already on")
  - Trust in the settings.json `env` block's purpose was degraded across sessions
problem_type: api_misunderstanding
module: claude-code-settings
status: Resolved
---

## Summary

`CLAUDE_CODE_ENABLE_TELEMETRY=1` does **not** control Claude Code's OAuth prompt-cache TTL. It is a gatekeeper for OpenTelemetry export that is a no-op without `OTEL_*` companion env vars. The 1-hour prompt-cache TTL is the Claude Code OAuth **default** in version 2.1.111 — it was already active in every historical main-thread session, including 41 sessions that started before the telemetry flag was ever committed.

The fix for the current repo is to drop the `env` block from `claude/settings.json`. The bigger lesson is: **configuration claims about observable runtime behavior must be proven from runtime data, not accepted from docs or subagents.**

## What we believed (and wrote down)

From the 2026-04-15 HANDOFF:

> `5128f6a` — enable telemetry for 1h cache. Added `env.CLAUDE_CODE_ENABLE_TELEMETRY: "1"` to `claude/settings.json` to upgrade OAuth prompt cache TTL from 5 minutes to 1 hour. Takes effect on next session.

From the Forge project memory:

> `CLAUDE_CODE_ENABLE_TELEMETRY=1` in settings.json env block upgrades OAuth prompt cache from 5-min to 1-hour TTL. Requires telemetry opt-in. No effect on Vertex/Bedrock paths.

Both statements are wrong. The flag was committed on the strength of a plausible-sounding trade-off narrative ("tell Anthropic more about your usage → they let your cache live longer") that was never checked against transcript data.

## Investigation

### Step 1 — A subagent said it wasn't even on

A `claude-code-guide` subagent, asked whether 1h cache was active, reported it was off and cited `ENABLE_PROMPT_CACHING_1H=1` as the actual toggle. This contradicted the handoff. The subagent's answer was itself doc-derived, not runtime-verified.

### Step 2 — Inspect the transcripts (ground truth)

Claude Code writes every API turn's `message.usage` into per-session JSONL files at `~/.claude/projects/<slug>/<session-id>.jsonl`. Inside `cache_creation`, two fields distinguish the cache tier used for the write:

- `ephemeral_5m_input_tokens` — tokens written to the 5-minute cache
- `ephemeral_1h_input_tokens` — tokens written to the 1-hour cache

A non-zero value in one and zero in the other tells you definitively which tier was active for that turn.

**Single-session probe:**
```bash
jq -r 'select(.message.usage.cache_creation) |
  [.timestamp,
   .message.usage.cache_creation.ephemeral_5m_input_tokens,
   .message.usage.cache_creation.ephemeral_1h_input_tokens,
   .message.usage.cache_read_input_tokens] | @tsv' \
  ~/.claude/projects/<slug>/<session-id>.jsonl
```

Current session showed `5m=0` consistently, `1h` non-zero on every turn. 1h cache is on right now.

### Step 3 — Prove the flag is not the cause

If telemetry *caused* 1h cache, then sessions that initialized before the telemetry commit should show 5m-only writes. The telemetry commit landed at `2026-04-15T20:59:59-07:00`. Aggregating every transcript JSONL whose earliest timestamp is before that cutoff:

| Project            | Pre-telemetry sessions | 5m writes | 1h writes    | Reads         | pct_1h |
|--------------------|-----------------------:|----------:|-------------:|--------------:|-------:|
| dataworks-website  |                      6 |         0 |   21,012,753 | 1,501,219,299 | 100.0% |
| openclaw           |                     23 |         0 |   40,013,709 | 1,749,993,390 | 100.0% |
| dotfiles           |                      5 |         0 |   14,564,730 |   411,181,756 | 100.0% |
| Gooner             |                      6 |         0 |   45,854,586 |   929,157,459 | 100.0% |

**41 pre-telemetry sessions. Zero writes to the 5-minute tier. 121M writes to the 1-hour tier.** Telemetry was not what turned 1h cache on. It was on the whole time.

### Step 4 — Ask what the flag actually does

A second `claude-code-guide` query (after the transcripts settled the cache question) produced the authoritative answer: `CLAUDE_CODE_ENABLE_TELEMETRY=1` alone is a no-op. It is a prerequisite gate that only fires when paired with `OTEL_*` companion vars (`OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`). Without those, Claude Code collects telemetry internally and discards it at session end. There is no Anthropic Console dashboard for Claude Code CLI usage — the observability path is self-hosted OpenTelemetry only.

## Root cause

Two distinct roots, nested:

1. **The config claim was wrong.** `CLAUDE_CODE_ENABLE_TELEMETRY=1` does not upgrade cache TTL. 1h cache is the OAuth default in Claude Code 2.1.111. The flag does nothing without an OTel backend wired up.
2. **The process that shipped the wrong claim was weaker.** A plausible trade-off narrative was accepted and documented across a commit message, a handoff, a Forge project memory entry, and a pickup briefing — without ever inspecting the JSONL transcripts that would have falsified it in one `jq` call. Claims about runtime behavior were treated as facts after being read, not after being measured.

## Working solution

### 1. Remove the flag from `claude/settings.json`

The `env` block only contained this one entry, so drop the entire block:

```diff
     }
   },
-  "env": {
-    "CLAUDE_CODE_ENABLE_TELEMETRY": "1"
-  },
   "effortLevel": "high",
```

### 2. Verify 1h cache stays on after removal

Restart Claude Code (env is read at process start). Then, after one round-trip in the new session:

```bash
# Newest transcript
ls -lt ~/.claude/projects/-Users-dvillavicencio-Projects-Personal-dotfiles/*.jsonl | head -1

# Inspect its cache tier
jq -r 'select(.message.usage.cache_creation) |
  [.timestamp,
   .message.usage.cache_creation.ephemeral_5m_input_tokens,
   .message.usage.cache_creation.ephemeral_1h_input_tokens,
   .message.usage.cache_read_input_tokens] | @tsv' \
  ~/.claude/projects/-Users-dvillavicencio-Projects-Personal-dotfiles/<NEW_SESSION_ID>.jsonl
```

Pass: 3rd column (1h) non-zero, 2nd column (5m) zero.

### 3. Correct the propagated misinformation

- Forge project memory note at `/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/workspace-forge/projects/dotfiles/context.md` — add a dated correction bullet referencing this solution.
- HANDOFF.md — next handoff should state telemetry was removed as a no-op and reference this doc.
- Local memory (`~/.claude/projects/<slug>/memory/claude_code_cache_inspection.md`) — document the jq inspection recipe with the empirical finding inline.

## Prevention

### Heuristic: measure before you document

Any claim of the form *"config knob X causes runtime behavior Y"* must be verified against a source of runtime truth before it becomes a commit message, a handoff bullet, or a project memory entry. For Claude Code, runtime truth lives in `~/.claude/projects/*/**.jsonl`. For systemd services, it's `journalctl`. For Docker, `docker inspect` + container logs. Pick the right source and inspect it.

### Checklist before committing a settings.json env-var change

1. Read the official docs for the flag (or ask a subagent that reads the docs) — don't rely on a trade-off narrative that "sounds right."
2. Identify where the behavior the flag supposedly controls is observable. Settle on one inspection command before committing.
3. Capture a before/after: the inspection output on master, then again after the change lands in a fresh session.
4. If the after-state is unchanged, the flag is not doing what you thought. Investigate before committing.

### Heuristic: subagents are not ground truth

Two `claude-code-guide` subagent calls disagreed about whether 1h cache was on. The disagreement alone should have been a signal — empirical data broke the tie. When docs and subagents conflict about *runtime* behavior, transcript data wins.

### Test sketch

For any future Claude Code settings.json change that claims a runtime effect, the minimal sanity test is two probes — one before the change takes effect, one after a fresh session has run:

```bash
# Run before, then again after restart in a fresh session; diff the tier percentages.
for dir in ~/.claude/projects/*/; do
  bash -c 'shopt -s nullglob; for f in "'"$dir"'"*.jsonl; do
    jq -r "select(.message.usage.cache_creation) |
      [.message.usage.cache_creation.ephemeral_5m_input_tokens // 0,
       .message.usage.cache_creation.ephemeral_1h_input_tokens // 0] | @tsv" "$f" 2>/dev/null
  done' | awk -v p="$(basename "$dir")" '{s5+=$1; s1+=$2} END {
      denom=s5+s1; pct=(denom>0)?s1*100/denom:0
      printf "%-70s 5m=%-10d 1h=%-10d pct_1h=%.1f%%\n", p, s5, s1, pct
  }'
done
```

If the flag actually affects cache tier, the percentages shift. If they don't, it doesn't.

## Related documentation

- `docs/solutions/code-quality/claude-code-notification-hook-false-positives.md` — another case of a Claude Code settings.json misunderstanding where a config key's semantics were assumed rather than checked.
- `docs/solutions/code-quality/claude-code-hook-stdio-detach.md` — settings.json hook execution model; relevant anytime the `env` block or hooks are edited.
- `docs/solutions/cross-machine/tailscale-tag-acl-ssh-failure-modes.md` — demonstrates the same "measure runtime state with `jq` over structured output before claiming causation" pattern, applied to Tailscale node state.
- `docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md` — a sibling case where a CLI flag's effective behavior depended on a version prerequisite; same class of "verify the flag actually does what it says."

## References

- Claude Code monitoring docs: https://code.claude.com/docs/en/monitoring-usage.md — "Telemetry is opt-in and requires explicit configuration"
- Anthropic prompt caching: cache tiers and 5m/1h TTL semantics in the messages API response `usage.cache_creation` object.
- Commit that introduced the flag: `5128f6a` (2026-04-15) — superseded by the removal on this branch.
