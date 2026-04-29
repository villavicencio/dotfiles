---
title: "feat: SessionStart hook for auto-loaded /pickup briefing"
type: feat
status: not-implemented
date: 2026-04-27
outcome: "Implemented and field-tested across two iterations (cheap-local only, then with Forge bridge); reverted before merge after concluding the slash command is the right abstraction. See Outcome section below."
---

# feat: SessionStart hook for auto-loaded /pickup briefing

## Outcome (added 2026-04-28)

**Decided not to ship.** This plan was implemented in full (hook script, settings.json registration, install.conf.yaml symlink, CLAUDE.md docs), then field-tested across two iterations:

1. **Phase 1 as planned** — cheap-local briefing only (HANDOFF + git + CE artifact counts). Verified working end-to-end on a fresh `claude` session.
2. **Scope expansion mid-PR** — added Forge bridge after recognizing that deferring it to manual `/pickup` would let agent-filed inbox messages and pending tickets sit invisible until the next manual run. Also verified working.

What surfaced in the design exercise was that **`/pickup` is more load-bearing than the hook can replace**:

- **Synthesis is the value, not data-gathering.** `/pickup` Step 3 produces a 2-3 sentence summary, "next up:", gotchas, and a ready-to-go closer. The hook can dump *data* into context but cannot *synthesize* it; the model receives the data and waits for an instruction. Without the synthesis step, the user still mentally runs `/pickup`-style orientation themselves.
- **Actions stay in the slash command.** Inbox archival (`mv ... && chown 1000:1000`) and pending-ticket promotion to GitHub issues require explicit invocation regardless of whether content was pre-loaded.
- **Cost on every session, value only on some.** Hook adds ~2s SSH + ~6KB context tokens to every fresh session, even when the user opens Claude to ask a one-shot question with no project-state dependency. `/pickup` is opt-in on the sessions that need it.

The hook saves 7 keystrokes per session in exchange for: latency on every session, context bloat on every session, drift risk between hook and slash command, two SessionStart hooks sharing one 10k char budget, and the fragility list documented in the postscript of `docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md`.

The companion solutions doc captures the durable learnings — Claude Code hook contract, SessionStart-specific details, the duplicate-vs-hint tradeoff, and the corrected rule of thumb for SSH in SessionStart hooks. **That doc is the real artifact of this plan**; the implementation work served the learning.

The plan body below is preserved as the design record (what we built, why, and what the budget arithmetic looked like). The decision not to ship is reflected only in `status: not-implemented` and this Outcome section.

---

## Overview

Wire a Claude Code `SessionStart` hook into the dotfiles so that fresh sessions automatically load the cheap, fast portion of `/pickup`'s data-gathering work as additional context — the model sees a session briefing on its first turn without the user having to type `/pickup`. The plan is also the user's learning artifact for Claude Code hooks: the patterns, contracts, and gotchas surface in a `docs/solutions/` entry that any future session (or other agent) can search.

This is the first new hook in the repo since the existing `claude/hooks/tmux-attention.sh` was wired up. It deliberately stops short of the full `/pickup` flow — the slow SSH-driven Forge bridge and VPS health snapshot stay behind the explicit slash command.

---

## Problem Frame

The user runs `/pickup` at the start of every fresh Claude session. The work it does is conventional and predictable: read `HANDOFF.md`, list open PRs, surface recent CE artifacts, sometimes hit the Forge bridge. The pain is small per occurrence (typing six characters) but compounding (every session, several times a day).

Beyond that pain, the user explicitly wants to *learn how Claude Code hooks work* and felt the SessionStart event was the right teaching example for this concrete need. So the plan needs to deliver both: a working hook, and a durable knowledge artifact that captures hook semantics for future use.

The constraint the user has not stated but that matters: `/pickup` does several things that should NOT run on every session start. The Forge bridge SSH call alone produced ~48KB of output in this session and took multiple seconds; baking that into a SessionStart hook would blow past the 10,000-character `additionalContext` ceiling and add ≥ 2s latency to every fresh `claude` invocation. The hook needs to be fast and small; `/pickup` keeps the heavy work behind an explicit invocation.

---

## Requirements Trace

- R1. A fresh `claude` session in any repo with a `HANDOFF.md` produces a session briefing on the model's first turn without the user typing `/pickup`.
- R2. The briefing covers the cheap-and-local portion of `/pickup` only: `HANDOFF.md` head, current branch, uncommitted-file count, counts of recently-modified CE artifacts. No SSH, no `gh` API calls in the hot path.
- R3. The hook is fast (target < 500ms wall clock) and small (target < 2,000 characters of stdout) so it leaves headroom under the documented 10k `additionalContext` cap and does not visibly stall the user's first prompt.
- R4. The hook is graceful in non-dotfiles contexts: no `HANDOFF.md`, no git repo, no jq installed — none of these errors out. Empty sections are stated explicitly so the model never reads silence as "everything's fine."
- R5. The full `/pickup` slash command remains the escape hatch for richer orientation (Forge bridge, VPS health snapshot, CE artifact deep-read). The hook complements `/pickup`, it does not replace it.
- R6. A `docs/solutions/` entry captures Claude Code hook fundamentals, the SessionStart contract, and the design tradeoffs surfaced in this plan, so future sessions can search it.
- R7. The hook is registered in repo-tracked `claude/settings.json` (already symlinked into `~/.claude/settings.json` by Dotbot), so it deploys to every machine via `./install` with no per-machine setup.

---

## Scope Boundaries

- Not refactoring `/pickup` itself; the slash command stays as-is and remains the canonical "full orientation" surface.
- Not migrating `/pickup`'s data-gathering steps into shared shell helpers that both hook and skill invoke. (Tempting future direction, but Phase 1 keeps the briefing script small and standalone.)
- Not adding the Forge bridge SSH call or VPS health snapshot to the hook. Those stay slow + explicit.
- Not adding hooks for `resume`, `clear`, or `compact` matchers in this plan. Phase 1 ships `startup` only; if the briefing proves valuable we widen the matcher set in a follow-up.
- Not setting up cross-machine variants (e.g., a Linux variant of the script for the VPS). The script must be portable but only the Mac/dotfiles install path is tested in this plan.
- Not changing the existing `tmux-attention.sh` hook's behavior; the new hook is additive.

### Deferred to Follow-Up Work

- **Refactor `/pickup` data-gathering into shared shell helpers**: a separate plan once we see whether the hook approach is the right primary surface. Goal would be eliminating drift risk between the briefing script and the slash-command's data steps.
- **Widen the matcher set to include `clear` and `compact`**: a follow-up after a week or two of using the `startup`-only version and confirming the briefing is helpful (and not noisy) post-context-reset.
- **Hook usage cookbook entries for other events** (PreToolUse, PostToolUse, Stop): captured in the solutions doc as further reading once the SessionStart pattern is internalized.

---

## Context & Research

### Relevant Code and Patterns

- `claude/hooks/tmux-attention.sh` — existing hook, sets the precedent for: (a) script lives in `claude/hooks/`, (b) `set -u` and `exit 0` always, (c) script is repo-agnostic and self-guards on missing context (`TMUX_PANE`), (d) graceful no-op when prerequisites are absent.
- `claude/settings.json` — existing hooks block already registers `tmux-attention.sh` for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`. The new hook adds a *second* entry under `SessionStart` — the harness concatenates outputs in registration order, so the briefing's stdout will follow `tmux-attention.sh clear`'s (silent) output cleanly.
- `claude/commands/pickup.md` — the slash command this hook is mirroring a slice of. Steps 1, 2, 2b are the cheap-local portion; Steps 2c (Forge), 2d (VPS), and 3 (synthesis) stay out of the hook.
- `install.conf.yaml` — Dotbot symlinks `claude/` into `~/.claude/`, so `claude/hooks/session-briefing.sh` becomes `~/.claude/hooks/session-briefing.sh` automatically on `./install`.
- `CLAUDE.md` (project) — already contains a "Claude Code tmux tab indicator" subsection documenting the existing hook. The new hook follows the same documentation pattern.

### Institutional Learnings

- `docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md` — the only prior dotfiles solution doc focused on Claude Code hooks. Lesson carried forward: hook scripts must be defensive against partial-state and concurrent invocation.
- `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` — Claude Code tool input pipeline filters PUA characters. Not directly relevant to hook behavior (hooks run as ordinary shell), but a reminder that the harness has surprising filters; `xxd`-based byte-level verification is the only honest signal when something doesn't render as expected.
- `docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md` — adjacent dotfiles learning that "did the script run cleanly" and "did it produce the right output" are different questions. Same logic applies here: the hook can `exit 0` while emitting nothing useful; we need an explicit verification path that the briefing actually appears in context.

### External References

- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks) — authoritative source for SessionStart's source values (`startup`, `resume`, `clear`, `compact`), the `hookSpecificOutput.additionalContext` JSON schema, and the 10,000-character output cap.
- [LaunchDarkly SessionStart hook example](https://github.com/launchdarkly-labs/claude-code-session-start-hook) — only public dotfiles-style example surfaced in research. Uses LaunchDarkly AI Agent Configs to inject context dynamically; not directly applicable but confirms the "hook outputs context for the model" pattern works in practice.
- Research synthesis from this session's claude-code-guide agent: complete answers on stdout vs JSON output, matcher semantics, latency expectations, and "no supported way to invoke a slash command from a hook."

---

## Key Technical Decisions

- **Use plain stdout, not JSON `hookSpecificOutput`.** Both are supported and the model receives them identically. Plain stdout is simpler to read in a debugger (`bash claude/hooks/session-briefing.sh` shows you exactly what the model will see), trivially composable with redirection, and matches the existing `tmux-attention.sh` precedent. The JSON envelope earns its complexity only when multiple structured fields need to coexist (which SessionStart does not currently support).
- **Match `startup` only in Phase 1.** Of the four SessionStart sources (`startup`, `resume`, `clear`, `compact`), only `startup` is unambiguously the right place to brief — `resume` keeps full context, and `clear`/`compact` are debatable (the user might want a re-brief, or the model might already have just-summarized context). Start narrow; widen via follow-up after dogfooding.
- **Duplicate the cheap data-gathering logic in the hook script rather than invoking `/pickup` as a "please run this" hint.** Hooks have no supported mechanism to literally invoke a slash command. The two viable patterns are "duplicate the work" (deterministic, slight drift risk) or "emit a hint and hope the model complies" (non-deterministic). Determinism wins for a fast-path briefing; drift risk is acknowledged and mitigated by keeping the script's scope tight (only the cheap-local steps that are unlikely to change).
- **Hook script is repo-agnostic.** It detects `HANDOFF.md`, `.git/`, and `docs/{brainstorms,plans,solutions}/` and gracefully degrades when each is absent. This means it does useful work in *any* Claude session, not just dotfiles, and a non-dotfiles project will see a minimal git-status briefing rather than an error.
- **Briefing ends with an explicit pointer to `/pickup`.** The model needs to know the briefing is the *fast slice* and that the user can ask for the full pass on demand. One-line trailing instruction: "For Forge inbox / VPS health / full synthesis, run /pickup."
- **No caching.** The briefing is cheap enough (target < 500ms) that re-running it on every fresh session is fine. Caching adds invalidation complexity for marginal latency wins.

---

## Open Questions

### Resolved During Planning

- **Where does hook stdout go?** Into the model's first-turn context as `additionalContext` (see external research above). Confirmed.
- **Will multiple SessionStart hooks step on each other?** No — outputs concatenate in registration order. The existing `tmux-attention.sh clear` produces no stdout, so the briefing appears cleanly.
- **Is there a way to invoke `/pickup` from the hook?** No. Decided to duplicate the cheap logic; defer the heavy work to explicit invocation.
- **Should the briefing carry the Forge bridge results?** No — too slow (2-5s) and too verbose (~48KB of output observed this session) to fit in `additionalContext`'s 10k char cap.

### Deferred to Implementation

- **Exact `HANDOFF.md` slice to include.** Likely first 30-50 lines or up to the first `## What's Next` heading, whichever comes first. Tune during implementation by looking at actual briefing output in the model's context.
- **Whether to include uncommitted-file *names* or just a count.** Names give the model immediate signal but inflate output; count + a hint to run `git status` is leaner. Decide after seeing real briefings.
- **How to detect "no jq" / "no gh" gracefully.** Skip the section, emit a one-line note, never error. Specific shape (silent skip vs explicit "(gh not installed)") TBD during script implementation.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
┌─────────────────────────────────────────────────────────────────────┐
│ User runs `claude` in a fresh terminal                              │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Claude Code harness reads ~/.claude/settings.json                   │
│ Iterates SessionStart hook entries with matcher matching "startup"  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
   ┌────────────────────┐         ┌────────────────────────┐
   │ tmux-attention.sh  │         │ session-briefing.sh    │
   │ clear              │         │ (NEW)                  │
   │ (no stdout)        │         │ - cat HANDOFF head     │
   │                    │         │ - git branch/status    │
   │                    │         │ - count CE artifacts   │
   │                    │         │ - emit /pickup hint    │
   └─────────┬──────────┘         └────────────┬───────────┘
             │                                 │
             │ (silent)                        │ stdout
             │                                 │
             └───────────────┬─────────────────┘
                             ▼
       ┌──────────────────────────────────────────────┐
       │ Concatenated stdout becomes additionalContext│
       │ injected into the model's first-turn context │
       │ (capped at 10,000 characters total)          │
       └──────────────────────────┬───────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────┐
       │ Model sees the briefing on turn 1; user      │
       │ types their first message; model responds    │
       │ informed by the briefing                     │
       └──────────────────────────────────────────────┘
```

The mental model: **a SessionStart hook is a function from `()` to `string`; the string is appended to the model's first-turn context.** Nothing more, nothing less. The hook cannot block the session, modify settings, change permissions, or invoke a slash command. Its only knob is what bytes it prints.

---

## Implementation Units

- [ ] U1. **Write `claude/hooks/session-briefing.sh`**

**Goal:** Produce the cheap, fast, repo-agnostic session briefing that prints to stdout in under 500ms and well under 2,000 characters.

**Requirements:** R1, R2, R3, R4

**Dependencies:** None

**Files:**
- Create: `claude/hooks/session-briefing.sh`

**Approach:**
- Mirror the structural conventions of `claude/hooks/tmux-attention.sh`: `set -u`, defensive guards, always `exit 0`, no error output that would pollute the model's context.
- Sections, in order, each gated on prerequisite presence:
  1. Header: a one-line marker so the model can identify this block in its context (`=== Session briefing ===`).
  2. `HANDOFF.md` slice: if present, print the first ~30 lines (or up to the first `## What's Next` heading); if absent, print a one-line "No HANDOFF.md in $(pwd)."
  3. Git context: current branch + uncommitted-file count. Skip silently if not in a git repo.
  4. CE artifacts: counts of files in `docs/{brainstorms,plans,solutions}/` modified in the last 7 days. Skip the corresponding line silently if a directory does not exist.
  5. Trailing pointer: one-line "For full orientation (Forge inbox, VPS health, synthesis), run /pickup."
- Every external command (`git`, `find`, `wc`) is guarded against absence and against being run in the wrong directory.
- Script header comment explains the hook's role, why it's intentionally narrow, and where the heavy work lives (`/pickup`).

**Patterns to follow:**
- `claude/hooks/tmux-attention.sh` — header doc style, `set -u`, `exit 0` discipline, repo-agnostic guards.

**Test scenarios:**
- Happy path: run the script in the dotfiles repo with a current `HANDOFF.md`. Output contains the briefing header, `HANDOFF.md` slice, git context, CE artifact counts, and the `/pickup` pointer. Total output < 2,000 characters. Exit code 0.
- Edge case: run in a directory that is *not* a git repo (e.g., `cd /tmp && bash ~/.claude/hooks/session-briefing.sh`). Git section is skipped silently; the rest of the briefing renders. Exit code 0.
- Edge case: run in a git repo with no `HANDOFF.md`. The HANDOFF section emits a single "No HANDOFF.md" line; the rest renders. Exit code 0.
- Edge case: run in a repo where one of `docs/brainstorms/`, `docs/plans/`, `docs/solutions/` is missing. The corresponding line is skipped silently; the rest renders. Exit code 0.
- Error path: simulate `git` being absent (temporarily prepend a directory with a stub `git` that exits non-zero). The git section emits a one-line note or silently skips; the script still exits 0.
- Performance: time the script in the dotfiles repo (`time bash claude/hooks/session-briefing.sh > /dev/null`). Wall clock < 500ms.
- Output budget: byte count of stdout < 2,000 characters.

**Verification:**
- `bash claude/hooks/session-briefing.sh` in the dotfiles repo prints a briefing that the user can read top-to-bottom and immediately know "where am I, what's recent, what should I do next" without typing `/pickup`.
- `wc -c` on the output is well under 2,000.
- `time` shows the script completes in under 500ms on a warm filesystem.

---

- [ ] U2. **Register the hook in `claude/settings.json`**

**Goal:** Add a second SessionStart entry that runs `session-briefing.sh` with `matcher: "startup"`, alongside the existing `tmux-attention.sh` entry.

**Requirements:** R1, R7

**Dependencies:** U1 (the script must exist before settings.json references it)

**Files:**
- Modify: `claude/settings.json`

**Approach:**
- Add a sibling object to the existing SessionStart array. The existing entry uses `matcher: "*"`; the new entry uses `matcher: "startup"` so it fires only on fresh `claude` invocations and not on `--continue` or post-compaction.
- Use the same `~/.claude/hooks/<name>.sh` path style as the existing hook (resolves through the Dotbot symlink).
- Set `timeout: 5` matching the existing hook entries' convention; the script should complete in well under 500ms but the timeout is a safety net.
- Validate the JSON parses (`python3 -m json.tool < claude/settings.json`) before considering the unit done.

**Patterns to follow:**
- The existing SessionStart entry in `claude/settings.json` (matcher, command, timeout shape).

**Test scenarios:**
- Happy path: after the edit, `python3 -m json.tool < claude/settings.json > /dev/null` succeeds. The SessionStart array contains exactly two hook entries, the new one with `matcher: "startup"`.
- Live test: open a fresh `claude` session in the dotfiles repo (NOT `--continue` — fresh process). The model's first-turn context contains the briefing string. The user can ask the model "what did you see in your first-turn context?" to confirm.
- Negative test: open `claude --continue` against an existing session. The briefing does NOT appear in new context (matcher restricts to `startup`).
- Regression test: the existing `tmux-attention.sh clear` behavior is unaffected — open a fresh session inside tmux and verify the tab indicator clears (no leftover spinner from a prior session).

**Verification:**
- `~/.claude/settings.json` (which is the symlink target) parses as valid JSON.
- A fresh `claude` invocation in the dotfiles repo produces a briefing the model can describe back when asked.
- A `claude --continue` invocation does NOT produce a duplicate briefing.

---

- [ ] U3. **Document the new hook in the project `CLAUDE.md`**

**Goal:** Add a "Session-start briefing hook" subsection to `CLAUDE.md` that mirrors the existing "Claude Code tmux tab indicator" subsection's shape, so future agents (and the user, on a future session) can find this convention quickly.

**Requirements:** R6 (the user's "learn hooks" goal — the project-level doc is the immediate-discovery surface)

**Dependencies:** U2 (no point documenting until the hook is wired)

**Files:**
- Modify: `CLAUDE.md`

**Approach:**
- Place the new subsection adjacent to "Claude Code tmux tab indicator" under the "Key conventions" section, since both subsections describe `claude/hooks/` behavior.
- Cover, briefly: what the hook does, where the script lives, what matcher it uses (and why `startup` only), the size/latency budget, and an explicit pointer to the longer `docs/solutions/` writeup.
- Keep it under 15 lines — `CLAUDE.md` is a context-budget document, not a tutorial.

**Patterns to follow:**
- The existing "Claude Code tmux tab indicator" subsection — same density, same prose register, similar pointer-to-solutions-doc shape.

**Test scenarios:**
- Test expectation: none — pure documentation, no behavior to verify beyond "the markdown renders and a future reader can follow it." Verified by `git diff` review.

**Verification:**
- `git diff CLAUDE.md` shows a coherent subsection that reads like the surrounding ones, points at the script and the solutions doc, and explains the `startup`-only matcher choice.

---

- [ ] U4. **Write a `docs/solutions/` entry on Claude Code hook fundamentals**

**Goal:** Capture the durable knowledge artifact the user explicitly asked for: how Claude Code hooks work, the SessionStart event in particular, and the design tradeoffs surfaced in this plan. This is the user's stated learning goal made permanent.

**Requirements:** R6

**Dependencies:** U1, U2 (the doc references the actual files we built)

**Files:**
- Create: `docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md`

**Approach:**
- Knowledge-track entry in the `best-practices/` category (no narrower category currently fits "how a Claude Code feature works"; future entries on other hook events would slot in alongside).
- Frontmatter follows the existing dotfiles solution doc convention: `title`, `date`, `category`, `module`, `problem_type: best_practice`, `component: tooling`, `severity: low`, `tags`, `applies_when`.
- Body sections (knowledge-track template):
  - **Context** — when this matters: anyone touching `claude/hooks/` or `claude/settings.json`, anyone designing automation around session lifecycle.
  - **Guidance** — the hook contract: events, matchers, output schema (plain stdout vs JSON), the 10k cap, blocking semantics, *no slash-command invocation*, the duplicate-vs-hint tradeoff.
  - **Why This Matters** — silent failure modes (hook exits 0 but emits nothing useful; matcher too broad; output blown past cap), and the broader pattern that hooks are pure functions from event-to-stdout.
  - **When to Apply** — picking a SessionStart hook over a UserPromptSubmit hook, deciding when a hook is the wrong tool (e.g., when you actually want a slash command).
  - **Examples** — the `session-briefing.sh` shape we shipped, the `tmux-attention.sh` precedent, and one explicit non-example ("don't put a 5-second SSH call in SessionStart — too slow, too verbose, blocks first prompt").
- Cross-link to the existing `tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md` runtime-error doc for the lifecycle-race lesson.

**Patterns to follow:**
- `docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md` — knowledge-track tone, dense but readable, uses concrete code blocks to anchor abstract claims.
- `docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md` (this session's other compound) — pattern of "two related defects, one document, with explicit invariants at the end."

**Test scenarios:**
- Test expectation: none — knowledge-artifact doc, no executable behavior. Verified by re-reading the file end-to-end and confirming a stranger could implement a SessionStart hook from this doc alone.

**Verification:**
- Frontmatter parses as valid YAML.
- Doc contains all five knowledge-track sections (Context, Guidance, Why This Matters, When to Apply, Examples).
- A reader unfamiliar with Claude Code hooks could, after reading only this doc, write a working SessionStart hook of their own and explain the `startup`-only matcher choice in their own words.

---

- [ ] U5. **End-to-end live verification in a fresh Claude session**

**Goal:** Confirm the full path works in production: `claude` in the dotfiles repo, model first-turn context contains the briefing, briefing is short, no error output anywhere.

**Requirements:** R1, R2, R3, R4

**Dependencies:** U1, U2 (and ideally U3, U4 for review purposes, but the live test is independent)

**Files:**
- None modified.

**Approach:**
- Open a brand-new terminal pane (clean tmux window, no inherited Claude state).
- Run `claude` — wait for the prompt.
- First user message: "What did you see in your first-turn context? Quote the relevant block verbatim."
- Confirm the model quotes the briefing.
- Check timing subjectively (the prompt should not visibly stall).
- Bonus check: run `claude --continue` against a prior session and confirm the briefing does NOT appear (matcher works).

**Patterns to follow:**
- HANDOFF gotcha: "statusline edits can blank pre-existing Claude sessions — always test from fresh `claude` invocation, not `--continue`." Same discipline applies here.

**Test scenarios:**
- Integration: fresh `claude` → first-turn context contains "=== Session briefing ===" header and the rest of the briefing. Model can quote it back.
- Integration: `claude --continue` → first-turn context does NOT contain the briefing (no duplication, matcher honored).
- Performance: subjectively, the time-to-first-prompt is indistinguishable from before. If there's a visible stall, U1's performance scenario was wrong and we have to revisit the script.

**Verification:**
- Live model can describe the briefing it received.
- `--continue` flow is unchanged.
- No visible stall on session start.

---

## System-Wide Impact

- **Interaction graph:** Two SessionStart hooks now run in sequence on fresh-session start. Outputs concatenate in registration order; `tmux-attention.sh clear` produces no stdout, so the concatenation is effectively just the briefing. No interaction with the other hook events (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`) — those continue to run only `tmux-attention.sh`.
- **Error propagation:** The hook script always `exit 0` so it cannot fail the session start. Any internal errors are absorbed silently — the briefing may be empty but the session always starts. This matches the `tmux-attention.sh` invariant.
- **State lifecycle risks:** None. The hook reads files but writes nothing; no sentinel files, no temp state, no concurrency. (Compare to `tmux-attention.sh`, which juggles a sentinel file and a background spinner — the briefing has none of that complexity.)
- **API surface parity:** `claude/settings.json` is the same file that gets symlinked to `~/.claude/settings.json` by Dotbot, so the hook deploys to every machine via `./install`. No machine-specific divergence. On a fresh Linux install, the script runs identically (POSIX shell + `git` + `find` + `wc` are all available; if `gh` or `jq` are missing, those sections silently skip per the script's defensive design).
- **Integration coverage:** U5 is the integration test. Unit-level happy-path tests on the script alone don't prove the hook actually fires, that the harness honors the matcher, or that the model receives the output as `additionalContext`. Live verification is required.
- **Unchanged invariants:** `/pickup` slash command behavior is untouched. `tmux-attention.sh` behavior is untouched. The Forge bridge SSH call frequency is unchanged (still one call per `/pickup` invocation, not one call per session start).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Briefing script and `/pickup` data-gathering steps drift apart over time | Keep the script's scope narrow to data unlikely to need restructuring (HANDOFF head, git status, file counts). Cross-link from the `docs/solutions/` doc back to `claude/commands/pickup.md` so future edits to either surface remember the relationship. |
| Hook output exceeds 10k character cap (e.g., a HANDOFF.md grows enormous) | U1 enforces a HARD upper bound by slicing the HANDOFF to ~30 lines or the first `## What's Next` heading, whichever is shorter. The script can also count its own output and short-circuit if it approaches the cap. |
| Briefing becomes noise that the user wants to disable on some sessions | The hook is registered in repo-tracked settings.json; toggling it off is a one-line change. If usage friction emerges, add an env-var escape hatch (e.g., `CLAUDE_SKIP_BRIEFING=1`) — defer until needed. |
| `matcher: "startup"` doesn't behave as documented (Claude Code is recent and this corner of the contract is undertested) | U5's negative test (`claude --continue` does not duplicate the briefing) catches this. If the matcher misbehaves, fall back to `matcher: "*"` and have the script self-detect the source via... actually there's no source env var per the research, so the fallback is to live with the duplication or move the briefing into a UserPromptSubmit-style hook with first-message detection. Document the workaround in the solutions doc if we hit it. |
| Adding a SessionStart hook subtly changes the model's behavior on first turn (more verbose, less greeting-y) | Soft risk; surface it in U5 by checking that the first-turn response feels normal. If the briefing is too prominent, make the header less attention-grabbing. |
| Cross-platform: script breaks on the VPS Linux install | The script is POSIX shell and uses only universally-available tools (`git`, `find`, `wc`, `cat`). On Linux, `~/.claude/` is not symlinked (per CLAUDE.md: "Linux skips: ... `~/.claude/*`"), so the hook never deploys to the VPS in the first place. Mac is the only target. |

---

## Documentation / Operational Notes

- `CLAUDE.md` (project) gets a new "Session-start briefing hook" subsection (U3).
- `docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md` is the durable knowledge artifact (U4).
- No rollout plan needed — the hook deploys to the personal Mac via `./install` on next run, and to the work Mac whenever the user next syncs.
- No monitoring needed — the hook is silent on success and silent on failure (always `exit 0`); the only observability is "does the briefing appear in the next fresh session," which U5 verifies once.
- HANDOFF.md does NOT need to mention this work in-flight; it's a discrete plan that lives in `docs/plans/` and gets surfaced by `/pickup` Step 2b until completed.

---

## Sources & References

- Related code: `claude/hooks/tmux-attention.sh`, `claude/settings.json`, `claude/commands/pickup.md`, `CLAUDE.md`
- Related solutions: `docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md`
- External: [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks), [LaunchDarkly SessionStart hook example](https://github.com/launchdarkly-labs/claude-code-session-start-hook)
- This session's research synthesis from `claude-code-guide` agent (full Q&A captured in conversation)
