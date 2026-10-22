---
title: "Clean up a merged branch before Force-deleting the Orca worktree your session runs in"
date: 2026-10-21
category: best-practices
module: code-review-workflow
problem_type: workflow_issue
component: tooling
severity: medium
applies_when:
  - "A Claude Code session running inside an Orca worktree (~/orca/workspaces/dotfiles/<name>) has merged its own PR"
  - "cleanup_merged_branch prints '<worktree> has initialized submodules: keeping <branch>'"
  - "About to tell David to Force delete the worktree and come back to finish the branch cleanup"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
tags: [orca, worktree, force-delete, cleanup-merged-branch, submodule, squash-merge, branch-cleanup]
---

# Clean up a merged branch before Force-deleting the Orca worktree your session runs in

## Context

The global rule is to delete a merged PR's branch, locally and on origin, as part of the
merge (`docs/agents/code-review.md`, "After the merge"). The tool for that is
`cleanup_merged_branch`, which first clears every worktree on the branch: it removes a linked
worktree and switches the main checkout to the default branch. It refuses an Orca worktree, because Orca's setup script checks out the dotbot submodule in every worktree and
`git worktree remove` can't remove one with an initialized submodule:

```
<worktree> has initialized submodules: keeping feat/axiom-command
```

(`bin/lib/cleanup-merged-branch.sh:46`.) The documented way to remove such a worktree is
Orca's Force delete, a human step (CLAUDE.md, "Removing an Orca worktree takes Force
delete"). Orca also deletes the branch only when it can prove it's merged (CLAUDE.md,
"The branch's commits aren't at risk"), and this repo squash-merges, so the branch's commit
is never an ancestor of master.

On dotfiles #234 the session that opened the PR ran inside its Orca worktree and merged
the PR there. The agent hit the refusal and told David to Force delete the worktree and then
come back so it could run the cleanup. David pointed out the flaw: the session lives in that
worktree, so Force delete closes it, and nobody is left to come back. The branch would have
been left behind on origin and locally.

## Guidance

Two routes, depending on who merges.

**Default: the home session merges and cleans up.** `docs/agents/parallel-sessions.md`
("Roles") gives merges and the cleanup after each to the home session (the main checkout).
A worktree session pushes, opens the PR, and hands it over (`SendMessage`). The home session
merges, David Force deletes the worktree, and then the home session runs
`cleanup_merged_branch <pr> master`, which works once the worktree is gone. No session dies
mid-procedure.

**When the worktree session merged its own PR** (David asked it to), it cleans up from inside the
worktree, before the worktree is deleted:

```bash
source ~/Projects/Personal/dotfiles/bin/lib/cleanup-merged-branch.sh
cleanup_merged_branch 234 master
```

Since VIL-414 the function detaches a worktree it can't remove (one with initialized
submodules, which every Orca worktree has) instead of refusing. It detaches at the worktree's
own HEAD, so no file changes, then deletes the branch on origin and locally with the usual
conditional checks, and prints `<path> is detached at <sha>: Force delete it in Orca`. The
branch is kept, and the worktree stays on it, whenever the local tip holds work the merge
didn't take or the worktree has changes or untracked files. The worktree is left clean, with
nothing that isn't on master, so David can Force delete it whenever he likes.

Before VIL-414 the function refused here (`<worktree> has initialized submodules: keeping
<branch>`), and #234's branch was cleaned up by hand with the same steps: a conditional
`git push --force-with-lease=refs/heads/<b>:<oid> origin --delete <b>`, `git switch --detach`,
then `git update-ref -d refs/heads/<b> <oid>`.

Before telling David it's safe, run the CLAUDE.md pre-Force checks against the worktree:
`git -C "$W" status --porcelain --ignored --untracked-files=all` (only the copied
`.claude/settings.local.json` is expected; `cmp` it against the main checkout's copy), and the
dotbot check. A clean `git -C "$W/dotbot" status` doesn't show stash entries, tags or unpushed
commits in that clone, so list those too. This doc adds one more: `git cherry origin/master
<tip>` should show `-` for the branch's commit, meaning its patch is on master.

## Why This Matters

Without this, the "delete the branch at merge" rule silently fails for every PR merged from
an Orca worktree: the cleanup tool refused (until VIL-414), Force delete takes the session with it, and Orca
keeps a squash-merged branch. The branches pile up on origin, and the next agent sees stale
`feat/*` branches it has to investigate. Telling David to "come back after the delete" also
hands him a step that can't be completed, in the session that just promised to finish it.

## When to Apply

- Any agent session whose working directory is an Orca worktree of this repo (path under
  `~/orca/workspaces/`) and that is about to merge, or has merged, its own PR.
- Not needed when the home session merges: it cleans up from outside the worktree, after
  David's Force delete (or with `wt done` for a `wt new` worktree, which removes the worktree
  itself; `wt done` doesn't manage Orca worktrees).

## Examples

What went wrong on #234, and the fix:

| Step | Before | After |
|---|---|---|
| Merge | `gh pr merge 234 --squash` from inside the worktree | same |
| Cleanup | `cleanup_merged_branch` refused (submodule) | conditional origin delete, detach, conditional local delete, from inside |
| Hand-off | "Force delete it, then tell me and I'll run the cleanup" | "Branch is gone on origin and locally; the worktree is detached at the merged commit and safe to Force delete" |

## Related

- CLAUDE.md, "Orca worktrees — `orca.yaml` setup script": Force delete, the pre-Force checks,
  and why there's no `scripts.archive`.
- `docs/agents/code-review.md`, "After the merge": `cleanup_merged_branch` and its refusals.
- `docs/agents/parallel-sessions.md`, "Roles": the home session owns merges.
