# Global Claude Code Instructions

These instructions apply across all projects on all machines.

---

## Reasoning

On non-trivial decisions, briefly explain your reasoning before acting. If you notice
an architectural concern — even if it's outside the immediate task scope — raise it.
The value is in the conversation, not just the implementation.

## Data Safety

Never delete user data (files, records, database entries, folders, notes) without explicit user approval.
Even if content seems out of scope or inappropriate, ask before removing. The cost of unauthorized
deletion is far higher than the cost of asking.

## Research

When you hit a wall — unfamiliar tool, unknown API, missing docs — always perform a web search
before giving up or saying "I don't know." The WebSearch tool is available and should be your
default fallback for anything outside your training data.

## Reddit Content

Use the `/reddit` command to fetch Reddit posts and comments. Never use WebFetch for Reddit URLs.

## Time & Session Continuity

The user runs in **PST/PDT**. When citing or reasoning about time:
- Always be explicit about PST vs UTC; never ambient-translate between the two
- Derive day-of-week from the system-provided date; never guess
- Don't layer on "late / morning / evening" framing unless wall-clock evidence supports it (4pm is not "late")

`/pickup` is often a context-hygiene move, not a new day. Sessions are routinely back-to-back —
the user clears the window to reduce cached-context cost and avoid pollution. Before defaulting
to "overnight" / "tomorrow" / "next morning" framing, check HANDOFF mtime, recent commit
timestamps, and any continuation cues in the conversation. If signals say same-session,
say so explicitly instead of pretending it's been hours.

## Proof Document Editor

**Proof default mode: `collaborative_docs`** (set 2026-04-28).

When creating new markdown docs, route to Proof by default if the doc is collaborative —
plans, specs, bug writeups, reports, memos, proposals, drafts, or similar iterative docs.
Code-adjacent local documentation (READMEs, docs/solutions/, repo-tracked CLAUDE.md, repo-tracked
HANDOFF.md, etc.) stays local. Existing repo-tracked markdown stays local unless the user
explicitly asks to move or share it via Proof.

The `proof` skill (`~/.claude/skills/proof/SKILL.md`) has the API details. The `compound-engineering:ce-proof`
skill is a separate wrapper used by ce-brainstorm / ce-plan / ce-ideate handoffs.
