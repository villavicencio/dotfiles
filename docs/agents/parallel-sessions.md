# Parallel Claude Code sessions

How to run several Claude Code sessions on one repo at once without them colliding (VIL-299).

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
- **Which branch it checks out.** An existing local branch is checked out as is. A branch that
  exists only on origin is fetched and tracked. Otherwise it creates a new branch from a fresh
  `origin/<default>`, with no upstream; the first push sets one with `-u`. If origin's default
  branch can't be found, it branches from the main checkout's current branch and says so.
- **Local-only files.** A new worktree has none of the main checkout's gitignored files (`.env`,
  `node_modules`). `wt new` copies the ones named in the repo's `.worktreeinclude`, which is
  Claude Code's own convention for `--worktree`: gitignore syntax, and only files that are also
  gitignored are copied. The list of copies goes in the worktree's git dir
  (`.git/worktrees/<topic>/wt-carried`).
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
  while any process has its working directory there (checked with `lsof`). Exit the worktree's
  Claude session first.
- **With a merged PR** for the branch, it runs `cleanup_merged_branch`
  (`bin/lib/cleanup-merged-branch.sh`, the same function as `code-review.md`'s "After the
  merge"). That removes the worktree and deletes the branch locally and on origin, only if the
  branch holds nothing the merge didn't.
- **Without one, it refuses.** `wt done <topic> --keep-branch` removes only the worktree and
  keeps the branch. There is no flag that deletes an unmerged branch; do that by hand if you
  mean it.
- **What counts as work.** Copies `wt new` made that are still byte-identical to the main
  checkout's file are deleted first. Anything else that would go with the directory blocks
  removal: changes, untracked files, ignored files, or a copy that was edited. If removal stops,
  the copies are put back.

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
