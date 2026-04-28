---
title: "Claude Code hooks: contract, SessionStart in particular, and the duplicate-vs-hint design tradeoff"
date: 2026-04-27
category: best-practices
tags:
  - claude-code
  - hooks
  - session-start
  - additional-context
  - automation
  - workflow
severity: low
component: tooling
problem_type: best_practice
module: claude-code-hooks
applies_when:
  - "Adding a new hook to claude/settings.json or claude/hooks/"
  - "Designing automation that should fire at session lifecycle boundaries (start, prompt submission, tool use, permission request, stop)"
  - "Debugging why a hook ran but its effect didn't appear in the conversation"
  - "Picking between a hook and a slash command for a given automation"
  - "Auditing a hook for output-budget, latency, or reliability problems"
related_solutions:
  - "docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md — concrete prior hook bug; shows lifecycle-race risk in long-running hook scripts"
  - "docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md — adjacent harness-input pipeline filter (PUA chars stripped from Edit/Write/Bash argv); not the same surface as hooks but the same family of \"silent harness behavior\" pattern"
---

# Claude Code hooks: contract, SessionStart in particular, and the duplicate-vs-hint design tradeoff

## Context

Claude Code hooks are shell commands the harness runs in response to lifecycle events: a session starting, the user submitting a prompt, a tool being used, a permission request firing, the model stopping. Each hook event is keyed in `claude/settings.json` (symlinked to `~/.claude/settings.json` by Dotbot) under `hooks.<EventName>`. A hook can: read environment, run subprocesses, emit stdout, exit with a status. It cannot block the session, modify model behavior beyond emitting context, mutate harness state, or invoke a slash command.

This doc captures the fundamentals — the contract that holds across all hook events — plus the SessionStart-specific details surfaced while wiring up `claude/hooks/session-briefing.sh` (the auto-`/pickup` briefing). It also captures the central design tradeoff that comes up the moment you try to do anything ambitious with a hook: the **duplicate-vs-hint problem**, which has no clean solution, only a choice with explicit tradeoffs.

---

## Guidance

**The hook contract.** A Claude Code hook is a shell command with a single observable side-channel: its stdout. The harness:

1. Looks up the hook event under `hooks.<EventName>` in settings.json
2. Iterates the entries whose `matcher` field matches the current event source
3. For each matching entry, runs every command in its `hooks` array sequentially
4. Concatenates the commands' stdouts in registration order
5. Injects the concatenated stdout into the model's context — for SessionStart, into the first-turn `additionalContext`; for other events, into the corresponding contextual slot

Hook stdout can be plain text OR a JSON object with `hookSpecificOutput.additionalContext` (10,000-character cap). Plain text is recommended for simple cases — easier to debug (`bash claude/hooks/foo.sh` shows you exactly what the model will see), trivially composable, no parsing overhead.

**Hook events and their matcher source values.** Each event fires under different circumstances; the matcher narrows which sources you respond to:

| Event | Source values for matcher | What `*` matcher fires on |
|---|---|---|
| `SessionStart` | `startup`, `resume`, `clear`, `compact` | All four; pick `startup` for "fresh session only" |
| `UserPromptSubmit` | (any prompt) | Every user message |
| `PreToolUse` | (per tool name, e.g. `Bash(git*)`) | Every tool call |
| `PostToolUse` | (per tool name) | Every tool result |
| `PermissionRequest` | (any permission prompt) | Every approval ask |
| `Stop` | (session stop) | Session end |

The matcher is a settings.json field, not something the script sees at runtime. If you need different behavior per source, you must register separate hook entries with distinct matchers — the script cannot self-detect which source fired.

**SessionStart specifically.** Sources are `startup` (fresh `claude`), `resume` (`--continue` / `--resume` / `/resume`), `clear` (`/clear`), `compact` (auto- or manual-compaction). Use `startup` only when the briefing is meant to land on a session that has no prior context. Adding `clear` and `compact` is reasonable for "re-orient after a context reset" but produces noise on `resume` (where the model already has full history).

**Hooks cannot invoke slash commands.** This is the most important constraint for ambitious hook designs. Slash commands (markdown skills) are interpreted by the model, not the harness; a hook is a shell command, not a model-facing instruction. If you want a hook to "run /foo at session start," your real options are the duplicate-vs-hint tradeoff below.

**Always exit 0.** A non-zero exit doesn't fail the session start, but it pollutes harness logs and there's no observable user benefit to "the hook errored." Defensive guards on every section + `exit 0` at the end is the established pattern (see `claude/hooks/tmux-attention.sh` and `claude/hooks/session-briefing.sh`).

**Output budget.** SessionStart's 10k-char cap is a hard limit; aim for far less so other hooks (and future expansions) have headroom. Empirically: ~1.3KB is plenty for a useful briefing if you slice intelligently (HANDOFF.md title + intro + What's Next, not first-N-lines blindly).

**Latency budget.** The hook blocks the user's first prompt until it returns. Under ~500ms is invisible; over ~1s is a perceptible stall. SSH calls, gh API calls, and anything else network-dependent should NOT run in a SessionStart hook unless cached and stale-tolerant. The target this doc's hook achieves: ~60ms on a warm filesystem in the dotfiles repo.

---

## Why This Matters

Hooks are a sharp tool with a confusing failure mode: they can succeed silently while doing nothing useful. The script exits 0, settings.json parses, the matcher matches — and the model's first-turn context is unchanged because the script's stdout was empty, or got truncated past 10k, or got swallowed by a misconfigured matcher. Without explicit verification (asking the model "what did you see in your first-turn context?"), you have no signal that the hook is doing what you think it's doing.

Three failure modes worth internalizing:

1. **Silent stdout loss.** Hook scripts that print to stderr (or to an absolute path, or to a logfile) emit nothing to the model. The harness only reads stdout. `set -e` + a misbehaving subprocess can produce a 0-byte stdout while the script "ran fine."
2. **Matcher too broad.** `matcher: "*"` on SessionStart fires on every source — including `resume`, where the briefing duplicates context the model already has. Symptom: the model gets the same briefing twice on `--continue`. Fix: narrow to `startup`.
3. **Output cap silently truncates.** The 10k cap applies to the concatenation of all SessionStart hooks' stdouts. Adding a hook that emits 9KB without checking the existing total can clip a sibling hook's output. There is no harness warning.

The broader point: **a hook is a pure function from event to stdout.** Treat it that way. Test it as a shell function (`bash claude/hooks/foo.sh`); verify its output (`wc -c`, `time`); look at the actual file contents the model receives, not the abstract idea of "context."

---

## When to Apply

- **Use a hook when the answer is "every time event X happens."** Session start, every tool call, every prompt. Hooks are the right tool for "this should fire automatically without the user (or model) deciding to."
- **Use a slash command when the answer is "the user (or model) chooses to invoke this."** Slash commands carry reasoning logic, can be invoked partway through a session, and don't have to fit in `additionalContext`. The /pickup skill is the canonical example: rich, slow, optional. The session-briefing hook is the cheap, fast, automatic complement.
- **Don't put a hook on the critical path of a heavy workload.** SSH calls, large `find` walks, network requests — any of these in a SessionStart hook visibly stall the user's first prompt. Defer to slash commands or background jobs.
- **Don't try to share state between hook script and slash command.** They run in separate processes with separate filesystems-of-record. If you find yourself wanting to "let the hook tell the slash command something," you've probably misshaped the design — collapse the responsibility into one or the other.
- **Be skeptical of "the hint pattern."** Emitting "please run /foo now" from a hook and hoping the model complies is non-deterministic. The model may not run it, may run it with the wrong arguments, may interpret the hint as informational. Use the duplicate pattern (do the work in the hook, accept the drift risk) when determinism matters.

---

## Examples

### Example 1: The session-briefing hook (duplicate pattern)

`claude/hooks/session-briefing.sh` duplicates the cheap-local data-gathering steps of `/pickup` (HANDOFF head, git status, CE artifact counts) and emits them as session-start context. The slow steps (Forge bridge SSH, VPS health snapshot) stay in `/pickup` because they don't fit in a SessionStart hook's latency or output budget.

The duplicate pattern's drift risk is real: if `/pickup`'s data-gathering changes, the hook script needs to follow. The mitigation is keeping the hook's scope narrow — only the data-gathering bits unlikely to need restructuring (HANDOFF read, git, find counts) — and cross-referencing both files in their respective comments and docs so a future editor remembers the relationship.

settings.json wiring (mirror this shape for any new SessionStart hook):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/session-briefing.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
```

### Example 2: The tmux-attention hook (lifecycle pattern)

`claude/hooks/tmux-attention.sh` is the prior hook in this repo. It demonstrates the *lifecycle* pattern: one shell script that responds to multiple hook events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`) by setting tmux user options to drive a status indicator. The script discriminates on its `$1` argument (passed in the settings.json command field), not on the source value (which scripts cannot see).

Key takeaways from that prior implementation:
- Set `set -u`; never `set -e` in a hook (a single subprocess failure shouldn't tank the whole hook).
- Always `exit 0` at the end. The harness logs non-zero exits but doesn't surface them to the user — they're silent noise.
- Guard on every prerequisite. `tmux-attention.sh` early-returns when `$TMUX_PANE` is unset (script running outside tmux); `session-briefing.sh` guards on every section's prerequisite (HANDOFF, git, docs/) so the worst case is an empty briefing, never an error.
- For long-running side effects (the tmux-attention spinner runs as a disowned subshell), use a sentinel file as the "keep running" signal — see `docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md` for the race condition lessons that shaped that design.

### Example 3: SSH in a SessionStart hook — cost is in slicing, not in the SSH itself

The naive first attempt at this hook ran the entire `/pickup` script — including the Forge bridge SSH that dumps `_shared/patterns.md`, the project context, all inbox messages, and all pending tickets. The empirical result, observed during initial design: ~48,000 characters of output (5× over the harness's 10k `additionalContext` cap, silently truncated downstream) and 2-5 seconds wall clock.

The first instinct — "SSH doesn't belong in a SessionStart hook" — turned out to be wrong, or at least too coarse. The user immediately pushed back on the resulting design: deferring the Forge bridge to manual `/pickup` meant agent-filed tickets and inbox messages would sit invisible until the next manual invocation, defeating the automation goal. **Skipping the SSH is itself a failure mode** when async signals depend on it.

The right answer turned out to be **intelligent slicing** rather than skipping:

- Don't `cat` `_shared/patterns.md` (40KB+ accumulated learnings); `tail -n 8` (~1KB) gets the recent ones.
- Don't `cat` the project cadence-log; `tail -n 20` gets the most recent session briefings.
- For inbox/pending: read full content (typically 10-30 lines per file, ~500-1500 chars each) but cap at 2 files with a "...N more — run /pickup for full list" hint when busier.
- Single SSH call (matching `/pickup` Step 2c's pattern); `ConnectTimeout=3` for offline failure mode; harness `timeout: 10` as the hard ceiling.
- Self-truncation footer at ~9.5KB just in case any single day pushes past the budget.
- Gate the whole section on `forge-project-key:` in the cwd's CLAUDE.md so non-Forge repos pay zero SSH cost.

Empirical result with this design: ~6.3KB output, ~1.8s wall clock, full inbox + pending content visible to the model on every fresh session.

**The actual rule of thumb**: if a step requires a network call, you have to either (a) slice it intelligently to fit the output and latency budgets, with a graceful timeout fallback, or (b) defer it to a slash command. The third option ("just skip it") trades silence for missed signals — that's a worse failure mode than a 2-second stall.

Concrete invariants for SSH in SessionStart hooks:

1. Single SSH call per hook (no per-file or per-section connections).
2. `ConnectTimeout=3` on the ssh command + `timeout: 10` in settings.json. Belt and suspenders.
3. Slice content on the *remote* side via `tail`, `head`, `find ... | head -N`. Truncate before transmission, not after — saves bandwidth and stays under the harness's char cap.
4. Cap any per-file contribution (head 20 is plenty for inbox/ticket content).
5. Cap the total file count per section (max 2-3 files, with "...N more" hint).
6. Self-truncate at the script level as a last-resort safety net.
7. Always handle SSH-unreachable as a one-line "(unreachable)" note, never an error.

### Example 4: Verification recipe (use this before declaring a hook done)

```bash
# 1. The script runs cleanly outside the harness.
bash claude/hooks/session-briefing.sh
echo "exit=$?"

# 2. Output is under budget.
output=$(bash claude/hooks/session-briefing.sh)
echo "$output" | wc -c       # well under 10000
echo "$output" | head -5     # sanity-check the shape

# 3. Latency is under budget.
time bash claude/hooks/session-briefing.sh > /dev/null

# 4. Edge cases don't error.
cd /tmp && bash ~/.claude/hooks/session-briefing.sh; echo "exit=$?"

# 5. Live integration test (the only thing that proves the harness wires it correctly).
# Open a fresh terminal, run `claude` in the target repo, then ask the model:
#   "Quote your first-turn context verbatim — specifically anything labeled 'Session briefing'."
# If the model can quote the briefing, the hook is wired end-to-end.
# Then verify the negative case: `claude --continue` should NOT show the briefing
# (matcher "startup" excludes resumes).
```

The fifth step — the live integration test — is the only one that proves the harness honors the matcher and injects stdout into context as advertised. Steps 1-4 prove the script behaves; only step 5 proves the hook does.

---

## Related

- `claude/hooks/tmux-attention.sh` — prior hook in this repo, lifecycle-pattern example
- `claude/hooks/session-briefing.sh` — duplicate-pattern example shipped alongside this doc
- `claude/commands/pickup.md` — the slash command this hook complements
- `docs/plans/2026-04-27-001-feat-session-start-pickup-briefing-plan.md` — full design doc with the duplicate-vs-hint tradeoff analysis
- [Claude Code Hooks reference (official)](https://code.claude.com/docs/en/hooks)
- [LaunchDarkly SessionStart hook example](https://github.com/launchdarkly-labs/claude-code-session-start-hook) — only public dotfiles-style example surfaced in research
