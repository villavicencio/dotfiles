# Parallel Claude Code sessions

How to run several Claude Code sessions on one repo at once without them colliding (VIL-299).
Runbook view: `davidv.sh/ops/parallel-sessions` (repo `~/Projects/davidv.sh`); update it, and its Verified badge, when this file changes.

**One session = one worktree = one branch.** Never run two sessions in the same directory: they
share one working tree, one index and one `HANDOFF.md`, so each one's edits and handoffs land
on top of the other's.

## `wt`: create and remove a session's worktree

`bin/wt`, linked to `~/.local/bin/wt` by `dotbot-conf/base.yaml`. Run it from anywhere in the repo.

```bash
wt new <topic> [type]     # branch <type>/<topic> (type defaults to feat) in .claude/worktrees/<topic>
wt done <topic>           # after the PR merges: remove the worktree and delete the branch
```

**`wt new`:**
- **Where the worktree goes.** `<main checkout>/.claude/worktrees/<topic>`, the same place
  `claude --worktree`, the `EnterWorktree` tool and `isolation: worktree` subagents use. Keeping
  one location matters for agents. Claude Code asks for approval every time an agent enters a
  worktree outside `.claude/worktrees/`, and no permission rule turns that prompt off. A resumed
  session also re-enters a worktree there even when launched from inside it
  (code.claude.com/docs/en/worktrees, read 2026-10-12).
- **Keeping it out of `git status`.** The global `git/gitignore` ignores `.claude/worktrees/` at
  every repo's root. In a clone where that doesn't apply, `wt new` appends `/.claude/worktrees/`
  to the clone's `.git/info/exclude` and says so.
- **Which branch it checks out.** An existing local branch is checked out as is, without asking
  origin. For any other name, in a clone with an `origin` remote, it asks origin first and stops
  if origin can't be asked (offline, say) rather than create a branch that may already exist
  there. A clone with no `origin` skips the lookup and branches from the main checkout's current
  branch. A branch that exists only on origin is fetched with an explicit refspec (so it works in
  a clone that fetches only the default branch), and its upstream is set to `origin/<branch>`; if that config write
  fails, `wt new` says so and the first push needs `-u`. Otherwise it creates a new branch from
  `origin/<default>`, with no upstream; the first push sets one with `-u`. It asks origin
  which branch is the default (the cached `origin/HEAD` only when origin doesn't answer) and
  fetches it first with an explicit refspec, so `origin/<default>` exists even when the clone's
  fetch config names a different branch. If that fetch fails it uses the cached ref and says
  so, and stops if there is none. If no default
  branch can be found, it branches from the main checkout's current branch and says so.
- **Local-only files.** A new worktree has none of the main checkout's gitignored files (`.env`,
  `node_modules`). `wt new` copies the ones named in the repo's `.worktreeinclude`, which is
  Claude Code's own convention for `--worktree`: gitignore syntax, and only files that are also
  gitignored are copied. The list of copies goes in the worktree's git dir
  (`.git/worktrees/<topic>/wt-carried`). If listing the files fails, or a copy fails, `wt new`
  says so and finishes with the worktree as made; copy what's missing by hand.
- **Opening the session.** In iTerm2 on this Mac (not over SSH), it opens a new tab in the
  current window running `claude --continue || claude` in the worktree. Otherwise, or with
  `--no-tab`, it prints the `cd … && claude` line.
  - Drag the tab into the project's tab group yourself. iTerm2 3.7.2 can't script tab groups:
    the AppleScript dictionary has no group terms, and gnachman/iTerm2 PR #756, a Python API for
    them, closed unmerged.
  - The tab's title is set to the topic, but the shell and Claude Code replace it with their own
    titles.

**`wt done`:**
- **Run it from outside the worktree.** It refuses while your shell is inside the worktree, or
  while any process has its working directory there. It checks with `lsof`, or `/proc` where
  there's no `lsof`, and refuses outright when it has neither, when `lsof` exits nonzero, when
  its listing doesn't include `wt` itself, or when reading that listing fails. It can see only
  your own account's processes; another account's are invisible without root. Exit the worktree's Claude
  session first.
- **Which PR counts.** Among the branch's merged PRs (the 20 newest by creation date, as `gh pr list` returns them), the first whose head is
  the branch's tip, or one the tip only lags (the PR was rebased or updated on GitHub): every
  commit on the tip has a patch-equivalent in it and no merge commit is left over, the same
  test `cleanup_merged_branch` applies. A branch name reused after an earlier PR merged has
  commits that PR lacks, so that PR doesn't count; `wt done` names the PRs it checked and
  refuses. If a PR's head can't be fetched or compared, it stops and says so instead.
- **With a merged PR** for the branch, it runs `cleanup_merged_branch`
  (`bin/lib/cleanup-merged-branch.sh`, the same function as `code-review.md`'s "After the
  merge"). That removes the worktree and deletes the branch locally and on origin, only if the
  branch holds nothing the merge didn't.
- **It needs `gh` to check.** If `gh` isn't installed or the lookup fails, `wt done` stops and
  says so rather than treat the branch as unmerged; `--keep-branch` doesn't need `gh`.
- **Without a merged PR, it refuses.** `wt done <topic> --keep-branch` removes only the worktree and
  keeps the branch. There is no flag that deletes an unmerged branch; do that by hand if you
  mean it.
- **What counts as work.** Once the PR check passes, copies `wt new` made that are still
  byte-identical to the main checkout's file are moved into the worktree's git dir
  (`wt-held/`), which goes when the worktree does. Anything else that would go with the
  directory blocks removal: changes, untracked files, ignored files, or a copy that was edited.
  If removal stops while the worktree still exists (a failed check, library load or
  `git status`), the held copies are moved back. A copy is left in `wt-held/`, and named, only
  when something now stands at its path or the move fails, and `wt done` then refuses to run
  again until `wt-held/` is empty, since removing the worktree would delete what's in it.
  `cleanup_merged_branch` ends with `git fetch --prune`, which can fail after the worktree and
  branches are already gone; `wt done` then says so, and there is nothing to move back.

**Not done yet:** a distinct `PORT` per worktree for dev servers.

## Roles

- **The home session** (the main checkout, on the default branch) owns the things there's only
  one of:
  - merges, and the `wt done` after each;
  - deploys;
  - Colima restarts and prunes (below);
  - the CodeRabbit hourly review in repos that still use it. It's one review per hour across
    all repos; dotfiles uses MergeWren instead (since 2026-09-24).
- **Worktree sessions** work their branch, push, and open the PR. They leave merging to the home
  session.
- **Sessions can message each other** (Claude Code's cross-session messaging, `SendMessage` /
  `ListAgents`). Use that to hand a finished PR to the home session instead of merging it
  yourself.

## What sessions share (measured on Claude Code 2.1.278, 2026-10-06)

- **Memory is shared; transcripts are not.**
  - A session in a worktree uses the main checkout's memory directory, so make small, targeted
    `MEMORY.md` edits only. A rewrite of the whole file clobbers another session's write.
  - Transcripts go to a new `~/.claude/projects/<worktree-path-key>/`, so `claude --continue`
    in a worktree resumes that worktree's own session.
- **Handoffs are per branch.** `dv:handoff` mirrors each branch's handoff into
  `<git-common-dir>/handoffs/`, which every worktree sees and which survives `wt done`.
  `dv:pickup` lists the other sessions in flight. `HANDOFF.md` is committed only from the
  default branch.
- **Colima is one VM for every project.** A restart kills every project's containers; those
  set to `unless-stopped` come back. During a long VM uptime the Rosetta handler can drop
  without any error. Check that `colima ssh -- ls /proc/sys/fs/binfmt_misc/` lists `rosetta`
  (browse-gateway#149).
- **No shell state between Bash calls**, in any session. Every block in a runbook or skill has to
  stand on its own.
