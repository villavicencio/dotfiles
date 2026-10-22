# Orca worktrees

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Orca worktrees — `orca.yaml` setup script
Orca runs `scripts.setup` from `orca.yaml` in each worktree it creates, with `ORCA_ROOT_PATH`
(the main checkout) and `ORCA_WORKTREE_PATH` set. It reads the file from the **new worktree**,
so a change only applies to worktrees cut from a branch that has it. The script checks out the
`dotbot` submodule (a new worktree has none; `./install` checks it out itself, but direct
`dotbot/bin/dotbot` runs such as the dry-run check under "`--dry-run`" need it there) and
copies from the main checkout the gitignored files that the worktree's own `.worktreeinclude`
names (`wt new` reads the main checkout's copy instead, so it copies nothing until the file is
on the main checkout's branch). Today that
is `.claude/settings.local.json`; without it a session falls back to the tracked allowlist.
The pre-commit hook needs nothing: hooks live in the shared `.git/hooks`.

**Never run `./install` from a worktree, in the setup script or by hand.** Dotbot points the
live `~/.config`, `~/.claude` and `~/.local/bin` links at whichever checkout ran it, and they
dangle once the worktree is removed. Don't launch nvim there either (first launch rewrites
`nvim/lazy-lock.json`).

**Removing an Orca worktree takes Force delete.** `git worktree remove` refuses a worktree
with an initialized submodule ("working trees containing submodules cannot be moved or
removed"), and Orca's plain delete doesn't pass `--force`. The CLI then reports `removed: true,
removing: true` while the worktree stays, stuck in Orca's "removing" state. Use Force delete
(CLI: `orca worktree rm --force`). It deletes the whole worktree directory, gitignored files
included, and the worktree's dotbot clone with its own branches, tags and stash. It also
removes the worktree's git registration and Orca's entry for it, and deletes the worktree's
branch when Orca can prove it's merged (see the last point below). The main checkout's files
are left alone. No status command proves that's safe, so before Force, check **the
worktree you're removing**, not the main checkout. Set `W` to its path first, using the name
Orca shows for it:

```bash
W=$(orca worktree show --worktree "name:<display name>" --json | jq -r .result.worktree.path)
```

- `git -C "$W" status --porcelain --ignored --untracked-files=all` lists every untracked and
  ignored file that goes with the directory, one per line. Run from the main checkout without
  `-C`, it would inspect the main checkout instead. Without `--untracked-files=all`, git
  collapses a directory into one `?? dir/` or `!! dir/` line and hides what's in it (`wt done`
  runs that shorter form, which is enough for its yes/no check). Files inside `dotbot/` aren't
  listed; see the next point. The `.claude/settings.local.json` setup copied in is expected; if
  `cmp "$W/.claude/settings.local.json" <main checkout>/.claude/settings.local.json` shows it
  changed (rules approved in this worktree), copy back what you want to keep.
- If you changed anything inside `$W/dotbot/`, push it or copy it out first. A clean
  `git -C "$W/dotbot" status` doesn't show commits, tags or stash entries that exist only in
  that clone.
- The branch's commits aren't at risk: Orca deletes the branch only when it can prove it's
  already merged, and keeps it otherwise (`orca worktree rm --help`). If you want the branch
  name kept even when merged, note it first: `git -C "$W" branch --show-current`.

**After a merge, run the cleanup before Force delete.** This repo squash-merges, so Orca can
never prove the branch merged, and Force delete leaves it locally and on origin.
`cleanup_merged_branch <pr> master` (`docs/agents/code-review.md`, "After the merge") deletes
it in both places. git can't remove a worktree with a submodule, so the function detaches it
at its own HEAD instead and prints `<path> is detached at <sha>`. Ignored files stay, so the
checks above still apply before Force. It works from inside that worktree, so a session that
merged its own PR cleans up before the Force delete closes it (VIL-414); source the
worktree's own copy of the function, since the main checkout may not be pulled yet.

**There is deliberately no `scripts.archive` to clear the submodule first.** #225 tried one,
and four review rounds each found a new way an automatic delete could lose work: a staged
gitlink, remote-tracking refs that outlive their branch, a tag-only pin, branch and tag names,
objects the main clone holds unreferenced. A script can't prove a git clone is safe to
delete; Force with a human check is the simpler contract. If one is ever added, two facts from
Orca's code (2026-10-18): Orca reads the archive hook from the **main checkout's** `orca.yaml`,
not the worktree's, and `orca worktree rm` skips it unless passed `--run-hooks`.

**Never `git submodule deinit` in a worktree.** It unsets `submodule.dotbot.*` in the shared
`.git/config`, so the main checkout's dotbot reads as uninitialized (`-a7fe585 dotbot`) even
though its files are intact. `git -C <main checkout> submodule init dotbot` restores it, and so
does the next `./install`.

Orca's file parser isn't full YAML: keys under `scripts:` take two spaces and script lines
four, as in Orca's own template. Orca worktrees live under `~/orca/workspaces/`, not
`.claude/worktrees/`, so `wt done` doesn't manage them; remove them from Orca.
