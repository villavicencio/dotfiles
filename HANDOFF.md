# HANDOFF — 2026-04-28 (Tuesday afternoon PDT)

Continuation session that started Mon 2026-04-27 morning and rolled into Tuesday. Four direct-to-master commits shipped early (docs + tmux UI), then a /ce-plan + /ce-work cycle around a SessionStart hook for /pickup that ultimately concluded the slash command was the right abstraction. PR #54 stands open as a docs-only design exercise (zero behavior change to merge).

## What We Built

### Direct-to-master commits (4)

1. **`ca7f2d3` — `docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md`** (228 lines). Joint write-up of the two defects that drove PRs #48/#49/#51/#53: ssh-as-root + `>>` first-write ownership trap, and `find -exec ... \;` discarding exec'd command's exit code. Captures symptom → root cause → fix per defect, the compound failure mode where they collide inside one ssh one-liner, and four invariants for future ssh-as-root sites.
2. **`c4640dd` — `tmux/tmux.display.conf` right-side date+time pill.** Combined the previous `│ HH:MM │ Mon DD ` separator chrome into a single rounded blue pill (`#2563EB` bg, white bold fg) matching the LOCAL session pill on the left. Middle-dot separator joins time and date into one "host clock" unit. Powerline Extra Symbols U+E0B6/U+E0B4 as rounded ends.
3. **`97e1d49` — `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` extended.** Added a third confirmed reproduction (Edit tool strips PUA chars from `new_string` parameter). Bash, Write, AND Edit all share the same filter. Bumped the concrete-rules list to cover all three tool surfaces. Documented the Python-via-Bash-heredoc workaround for Edit specifically.
4. **`30404aa` — `tmux/tmux.display.conf` status-left rounded caps.** Extended the rounded-pill treatment to all four left-side pill branches (PREFIX/COPY/SYNC/LOCAL-or-VPS). Each branch's cap fg tracks its own bg color via the existing ternary. Visual symmetry: both ends of the status bar now wear the same rounded shape.

### Open PR #54 — SessionStart hook design exercise (docs-only)

`feat/session-start-pickup` branch, 8 commits, **cumulative diff against master is two doc files only.** Implementation was built and field-tested across two iterations (cheap-local only → with Forge bridge), then reverted before merge. The two doc files that land:

- `docs/plans/2026-04-27-001-feat-session-start-pickup-briefing-plan.md` — design record, `status: not-implemented`, Outcome section explains the decision.
- `docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md` — durable knowledge artifact: hook contract, event/matcher matrix, three failure modes, when-to-hook vs when-to-slash-command, 5-step verification recipe, Postscript explaining why we didn't ship for /pickup.

The branch history preserves the build → field-test → revert journey for transparency.

## Decisions Made

- **zshrc:30 brew shellenv filter stays.** The previous handoff's "next up" item #1 claimed modern `brew shellenv` no longer emits the path_helper eval, making the filter dead code. Empirically false: Homebrew 5.1.7's `brew shellenv` still emits `eval "$(/usr/bin/env PATH_HELPER_ROOT=... /usr/libexec/path_helper -s)"`, the existing regex `'^eval .*path_helper'` still matches it, and removing the filter would jump `/opt/homebrew/bin` to PATH position 1 and shadow `~/.local/bin/claude`. Lesson: verify "this is dead code now" claims with one shell command before acting.
- **Carve-out to "ask before committing" rule:** for pure additive content (new docs, new files, comment-only edits), commit directly without asking. Saved as `feedback_commit_approval.md` in memory; MEMORY.md updated.
- **Same `#2563EB` blue for both ends of the status bar.** User had asked to combine the right-side date+time and give it a blue treatment "matching LOCAL or maybe something more pleasant." Picked the same blue as LOCAL for visual symmetry rather than introducing a new color. When user later asked to round the LOCAL/PREFIX/COPY/SYNC pills too, extended the treatment to all 4 left-side branches.
- **`/pickup` is the right abstraction for /pickup-shaped work.** Built a SessionStart hook that auto-loaded /pickup's data (HANDOFF + git + CE artifacts + Forge bridge) and field-tested it. Concluded the hook saves keystrokes but cannot replace synthesis (Step 3 reasoning) or actions (inbox archival, ticket promotion). User chose option B (revert hook, keep docs). PR #54 now lands as docs-only.
- **Edit/Write/Bash strip PUA chars from string inputs (U+E000–U+F8FF range).** Bash heredoc-via-stdin preserves PUA. The existing solutions doc was extended to cover all three tool surfaces. Workaround: use Python via Bash with `\uXXXX` escape syntax, verify with `xxd -p | grep -oE "ee82(b6|b4)"` (the `-p` flag is critical — default xxd output groups bytes with spaces, breaking naive grep patterns).

## What Didn't Work

- **First Edit attempts to add Powerline cap glyphs to tmux config.** Edit reported success, file was missing the U+E0B6/U+E0B4 bytes. Pivoted to Python via Bash heredoc.
- **First Python script with literal cap glyphs in source.** Bash tool argv also strips PUA — the literal cap chars in my Python heredoc body were stripped before reaching the remote shell. Pivoted to using Python's `\uXXXX` escape syntax in the source (which is pure ASCII on the wire and Python decodes at runtime).
- **First xxd verification used `xxd | grep -oE "ee82(b6|b4)"`.** Returned empty when bytes were actually present — default xxd output groups bytes as `ee82 b623 ...` with spaces, breaking the pattern. Switched to `xxd -p` (plain hex, no spaces) for verification.
- **Initial SessionStart hook design with cheap-local sections only.** Field-tested fine, but skipped Forge bridge — meaning agent-filed inbox messages and pending tickets sit invisible until the next manual /pickup. Defeated the automation goal.
- **"Just ship the full /pickup as a SessionStart hook" naive approach.** The Forge bridge SSH alone produced ~48KB of output (5× over the harness's 10k `additionalContext` cap, silently truncated). Pivoted to intelligent slicing: `tail -n 8` on patterns.md, `head -20` on inbox/pending files, capped at 2 files per section.
- **Trying to use a SessionStart hook to replace `/pickup`.** Built it, verified it works end-to-end, then realized it doesn't actually solve the problem: a hook can dump *data* into context but cannot do the *synthesis* step (Step 3's "next up:", gotchas, ready-to-go closer) or the *actions* (inbox archival, ticket promotion). The user mentally runs /pickup-style orientation themselves regardless of pre-loaded data. Reverted.

## What's Next

1. **Merge PR #54** — docs-only design exercise capturing the SessionStart hook learnings + Postscript explaining why we kept /pickup. Zero behavior change. After merge, delete `feat/session-start-pickup` branch.
2. **Wait for an inbound signal** — board is otherwise clean. No in-flight work after PR #54 lands.

Optional follow-up only if it bites: revisit the matcher-behavior question on `claude --continue`. PR #54's verification surfaced an ambiguity (briefing appeared on both fresh `claude` and `claude --continue`; could be matcher misbehaves or could be `--continue` with no resumable session falling back to `startup` source). PR #54 reverts the hook anyway so this is academic for now, but worth a focused test if anyone wires a future SessionStart hook.

## Gotchas & Watch-outs

- **`claude/CLAUDE.md` has uncommitted changes (Proof Document Editor config, externally added)** — not from this session's work, not mine to commit. The file is symlinked to `~/.claude/CLAUDE.md` (global, not project-tracked). Leave it alone.
- **PUA chars (U+E000–U+F8FF) are filtered by Edit/Write/Bash-argv.** Bash heredoc-via-stdin preserves them. For any glyph work in tmux config, status lines, etc., reach for Python-via-Bash with `\uXXXX` escapes, then verify with `xxd -p | grep -oE "ee82(b6|b4)"` (the `-p` flag matters — default xxd has spaces that break grep).
- **`/pickup` remains the canonical orientation surface.** Don't try to replace it with a hook. The lesson from PR #54: hooks dump data, slash commands reason. Synthesis-and-actions work belongs in a slash command, period.
- **Ship-time pattern this session:** small docs/UI commits go direct to master; substantive feature work goes through a PR (the hook work). User explicitly endorsed this hybrid mid-session.
- **Carry-forward (still valid):** ssh-as-root + `>>` first-write ownership trap → trailing chown invariant; `find -exec ... \;` discards exec'd exit code → use `+` form; tmux `##` escape rule for hex inside `#{?...}` ternaries; tmux statusline edits can blank pre-existing Claude sessions (test from fresh invocation, not `--continue`); HANDOFF.md stays on master only — never commit mid-branch.
