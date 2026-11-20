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

# The context meter

<!-- Moved out of claude/CLAUDE.md on 2026-10-28: David reads the meter; agents only need the 500k cue, which CLAUDE.md keeps. -->

The statusline `ctx` meter turns full yellow with a solid fill at 500k tokens; that's the cue to
hand off and start fresh, or `/clear` alone when nothing lives only in the session, or `dv:closeout` in a finished
worktree ("Keep sessions small" in `claude/CLAUDE.md`). On a window of 500k or less the cue is 80% of the window instead
(160k on a 200k window). When Claude Code reports the window size, the bar can also show a dim
`╎` at the cue ahead of the fill and a white `┃` at `autoCompactWindow` (600k); when each one
draws is in `claude/statusline-command.sh`, and `ci/statusline-checks.sh` pins it. The cue is a
balance between usage per turn (every turn re-reads the whole context) and interruptions. David
chose 500k on 2026-11-17 and the 80% rule for small windows on 2026-11-18, replacing the 200k
cue from VIL-402; 500k leaves time to write a handoff before compaction fires. If Claude Code
reports the token count but not the window, the bar assumes 1M, keeps the 500k cue and draws
neither the tick nor the compaction mark. If it reports neither the token count nor the window
size, the meter shows a plain percentage with neither cue. Auto-compaction is only a backstop:
`autoCompactWindow` puts it at 600k, 60% of a 1M window (since 2026-11-11; it was 400k). Claude
Code caps the value at the model's own window, so a model with a smaller window compacts at its
usual point. On desk Macs and Windows, `helpers/migrate_claude_settings.py` adds the key where
it's missing but leaves an existing value alone; hal's server profile gets neither the seed nor
that step (`docs/reference/install-and-server.md`). So a machine set to 400k keeps it until the
value is changed in its `~/.claude/settings.json`.

An agent can read its own context size from its session transcript,
`~/.claude/projects/<project>/<session>.jsonl`: take the last `assistant` entry and sum its
`message.usage` fields `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`.
That sum is the prompt size of the latest call. (Field names checked against a real transcript on 2026-11-18; they are Claude Code's, not a documented interface.)
For example (`<file>` is the transcript):

```
jq -s '[.[] | select(.type=="assistant" and .message.usage) | .message.usage] | last
       | .input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens' <file>
```
