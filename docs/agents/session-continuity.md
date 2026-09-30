# Handoff staleness after `dv:pickup`

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

How to measure how old a `dv:handoff` is without guessing.

`dv:pickup` is often a context-hygiene move, not a new day. Sessions are routinely back-to-back —
the user clears the window to reduce cached-context cost and avoid pollution. Before defaulting
to "overnight" / "tomorrow" / "next morning" framing, **check the handoff's own frontmatter
first**. `dv:handoff` (dv 0.4.0+) writes `created_at`, `branch`, and `head` above the header,
stamped from the shell rather than authored by the model, and `dv:pickup` reports `git log
<head>..HEAD` — so staleness is "N commits since `<head>`", which is a fact, not an inference
from file age. `head` is the anchor that matters: it pins the handoff to a tree state rather than
a moment.

**Validate `head` before trusting the count**, in two steps — `git cat-file -e <head>^{commit}`
(is the object here at all) then `git merge-base --is-ancestor <head> HEAD` (is it actually behind
us). Only if both pass is `git rev-list --count <head>..HEAD` meaningful. Three ways it isn't:

- **Present but not an ancestor** — a squash-merge or rebase rewrote the commit the handoff
  recorded. This repo squash-merges every PR, so it is the common case, and it **fails silently**:
  `rev-list` still returns a believable number. Verified 2026-08-25 — an orphaned pre-squash SHA
  reported `3` when the true distance was `5`. Do not report the count; fall back and say why.
- **Object absent** — fresh clone, or gc'd. `rev-list` errors loudly rather than lying.
- **Frontmatter with no `head`** — possible on pre-0.4.0 handoffs. Nothing to anchor to.

In all three, fall back to HANDOFF mtime and **announce the fallback**, since mtime is destroyed
by any fresh checkout. Do not substitute `created_at`: on **pre-0.4.0** handoffs it was
model-written and can be wrong — one was observed nine minutes *ahead* of both its own mtime and
the commit it described, i.e. less accurate than the mtime it was meant to replace. Also weigh
recent commit timestamps and any continuation cues in the conversation. If signals say
same-session, say so explicitly instead of pretending it's been hours.
