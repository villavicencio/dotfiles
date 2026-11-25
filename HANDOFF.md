---
created_at: "2026-11-24T17:56:59-08:00"
branch: "master"
head: "b1c4d61"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-24, evening (PT)

Home session in the main checkout, running Director Mode (on top of the standing Manager Mode) from about 14:45 to 17:57 PT. It opened seven ticket worktree sessions, relayed their highlights, merged their PRs, closed each ticket with its model label and cleaned up every branch and worktree. Nothing is in flight: no open PR, no other session running, `master` level with origin at `b1c4d61`, tree clean.

## What We Built
- **Merged, each with its ticket Done and `model` label:** #287 VIL-795 (`qwen3-8-27b`), #300 VIL-888, #301 VIL-933, #285 VIL-745, #302 VIL-889 (all `claude-sonnet-5-5`), #303 VIL-1010, #304 VIL-881 (both `claude-opus-5-5`). Credit counts are in each ticket's Done comment.
- **#305 (no ticket):** the Linear PR automation is now recorded as confirmed in `claude/CLAUDE.md`, `codex/AGENTS.md` and `docs/agents/tickets.md` "Ticket states", with a tested `op-agent` + GraphQL check command. Live settings read 2026-11-24: draft → In Progress, start → In Review, review → In Review, merge → Done; no ready-for-merge rule.
- **`model-credit VIL-N`** (#304) is on the personal Mac's PATH after David's `./install`; its first real run (VIL-881) matched a hand count.
- **Linear:** new `qwen3-8-27b` child in the `model` label group (team VIL; creating a child label needs `teamId`, not just the parent). VIL-107, VIL-360, VIL-454 moved In Progress → Todo with evidence comments. VIL-890 Blocked → Todo. VIL-1009, VIL-1035 filed by sessions.
- **Tickets filed tonight:** VIL-1031 (bring MergeWren's pre-review and fix-round rules into "Fix rounds"), VIL-1032 (third fix round without David for lows/mediums on the last fix's lines), VIL-1033 (skills: matching manager-mode line, blocked by 1032), VIL-1034 (skills, High: the Director authority below), VIL-1036 (write the four roles into `docs/agents/roles.md`), VIL-1037 (`model-credit` on hal's PATH).
- **Deleted** gitignored `.agents/skills/source-command-ticket/` on David's yes (stale Codex copy of the retired `/ticket`).

## Decisions Made
- **Roles (David, 2026-11-24):** Chairman of the Board (David), Director (home session), Manager (worktree session), Engineer (hired agent); MergeWren is the reviewer gate. VIL-1036 writes them down.
- **Director authority (David, 2026-11-24), on VIL-1034:** the Director decides fix rounds, declines, merges and deletes; it decides scope cuts and informs the Chairman. Chairman items (declining a high/critical on safety-boundary code, spending money, reaching outside) must never stop progress: route around them (split, ticket) and bring them together at the end. Every ask to David names the session's chat and the exact option number and label, standalone. Saved in project memory `feedback_director_decision_asks.md`; VIL-1034 carries it into the skills so other projects' Directors get it.
- **MergeWren rounds:** 4 of 7 PRs needed a third-round decision, some a fourth or fifth. Causes: prose restating code, fixes creating new claims, stale cross-file mentions, and the stale-reopen symptom (VIL-903). David chose A–D; A+B merged into VIL-1031 because VIL-814 already proved those rules in mergewren. VIL-903 raised to High and its decision recorded ("yes 903": rows made unclear by the quote rule don't hold the confirmation net).
- **hal gets `model-credit`** (David): VIL-1037.

## What Didn't Work
- `${!v}` indirection and a function named `show` both fail in this zsh (bad substitution; `show` is an alias). Write such scripts with explicit calls.
- `cleanup_merged_branch` refuses an Orca worktree without submodules because of its ignored `.claude/settings.local.json`. The documented route works: check it, `git -C <wt> switch --detach`, rerun the cleanup, then `orca worktree rm --force` (`docs/reference/orca-worktrees.md`).

## What's Next
1. **VIL-1034** (High, skills repo): the Director authority. Until it merges, worktree sessions still reject Director answers on MergeWren-gate questions, so those keep reaching David.
2. **VIL-1031**, then **VIL-1032** (both touch `docs/agents/code-review.md` "Fix rounds"; merge the second after updating from master), then **VIL-1033** (skills).
3. **VIL-1036** (roles doc), **VIL-1037** (hal link), **VIL-903** (MergeWren repo, ready).
4. Backlog now unblocked, left there until pulled: VIL-1035 (check suite with spaces in TMPDIR).

## Gotchas & Watch-outs
- **`.claude/worktrees/vil-721-hal-memory-sections`** (detached at `a9af0f3`) belongs to another session. Leave it.
- **Waived findings now in master:** #304's `f418ef6#1/#2` (no-PR commit search starts 30 days before ticket creation) and #303's `58c1617#1` (follow-up VIL-1035).
- **Shared-store handoff `villavicencio/docs-linear-completed-issues`** (otter worktree, 2026-10-23) shows as "branch gone locally" in pickup; stale, not archived automatically.
- No background shells or agents were running when this was written.
