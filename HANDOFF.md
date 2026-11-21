---
created_at: "2026-11-21T15:58:05-08:00"
branch: "master"
head: "df65209"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-21, afternoon (PT)

Hub session in the main checkout, in Manager Mode (admin only). It started with a pickup on 2026-11-18 and resumed on 2026-11-21. Work: answered a question about Linear auto-archive, merged dotfiles PR 294 (VIL-852) on David's approval, set up the Linear `model` label group, removed the finished VIL-852 worktree, and filed VIL-882. Nothing is in flight from this session. The tree is clean and `master` matches origin at `df65209`.

## What We Built
- **PR 294 (VIL-852), squash-merged as `df65209`**, pinned to approved head `3c3211a`. The unresolved-threads check was empty. MergeWren findings `7170dec#1` and `3c3211a#1` were waived by David, with the follow-up in VIL-881. Branch `pilot/vil-852-20261119-220515` was deleted on origin by `cleanup_merged_branch` (no local copy existed). Its new rule lives in `docs/agents/tickets.md` "Model credit", plus the Done-at-merge line in `claude/CLAUDE.md` and `codex/AGENTS.md`.
- **Linear, team VIL:** a new single-select label group `model`, with children `claude-opus-5-5` and `claude-sonnet-5-5`. VIL-852 is Done with `claude-sonnet-5-5`. My recount from `gh pr view 294 --json commits` gave Sonnet 33 lines and qwen3.8-27b 20; merge `3c3211a` was excluded. A future model gets its child label the first time a ticket needs it (`qwen3-8-27b` doesn't exist yet).
- **VIL-852 worktree removed** (`~/orca/workspaces/dotfiles/vil-852-…`) with `orca worktree rm --force`, under the standing approval for finished Orca worktrees (#297). The checks passed: the only file outside git was an identical `settings.local.json`, dotbot was clean, and its 8 reflog-only commits were all PR 294's. Leftover branch `vil-852-credit-each-finished-ticket-to-the-model-that-wrote` (`d16ed76`) was deleted with `delete_leftover_branch`.
- **VIL-882 filed** (hal Local Coding Pilot, Todo): the runner reads the ticket's current Decisions before planning, and the planner declines a brief, first or fix round, that contradicts one. Evidence is in hal `~/runs/queue/taken/` (account `david`): `41-vil-852.md` and the four `*-dotfiles-294.md` fix briefs.

## Decisions Made
- **A brief step that contradicts a ticket's recorded decision declines the run**, and the runner comments on the ticket (David, interview, 2026-11-21; recorded on VIL-882). Rejected options: the ticket overriding the brief, and running as briefed with a flag.
- **Linear auto-archive (6 months) is fine as is:** archived issues stay viewable and restorable in the team's archives; only a manual delete is permanent after 30 days (linear.app/docs/delete-archive-issues, fetched 2026-11-20). The MCP's `list_issues` has `includeArchived`.

## What Didn't Work
- Nothing failed this session.

## What's Next
1. **VIL-881** (Backlog): its blocker VIL-852 is Done, so it can start once David picks it up. Leave it in Backlog until work starts.
2. **VIL-882** (Todo): whenever David starts it as a hal-pilot worktree stream. Editing `plan-prompt.md` needs David to add `Edit(plan-prompt.md)` to hal-pilot's `.claude/settings.local.json` first.
3. **Four open pilot PRs in dotfiles**, not this session's work and not reviewed here: #285 (VIL-745), #286 (VIL-830), #287 (VIL-795), #295 (VIL-853). Check each one's MergeWren verdict and its ticket's state before anyone merges.
4. **Carried from the 2026-11-18 handoff, not rechecked:** delete `.agents/skills/source-command-ticket/SKILL.md` (needs David's yes); the `marketplace.json` `dv` description and `ticket` trigger evals in skills (unfiled); pull hal's shared clone as `david`; Dissolution stories In Progress with no PR; the stale In Progress tickets VIL-107, VIL-360 and VIL-454.

## Gotchas & Watch-outs
- **The Model credit rule now applies at every Done.** Count lines per model from the PR's own commits (`gh pr view <N> --json commits`, then `git show --numstat`). Skip merges of the base branch. Match `Co-Authored-By:` and `Worker-Model:` without regard to case. The `model` group is single-select, so Linear itself enforces one label.
- **hal briefs live in `~/runs/queue/taken/`** as `david`. hal's `stat` isn't BSD (`-f %Sm` fails); use `ls -l --time-style=+%F_%H:%M`.
- **`.claude/worktrees/vil-721-hal-memory-sections`** (detached at `a9af0f3`) belongs to another session. Leave it.
- **The PR 294 body names VIL-852 only**, so no other ticket closed at the merge (checked).
