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

How Orca 1.4.257 runs the script on macOS (2026-11-17, adding `orca.yaml` to eagle-hover-save,
and in the app bundle): it writes it to `.git/worktrees/<name>/orca/setup-runner.sh` and
types `bash <that path>` into an interactive shell in a terminal tab titled "Setup". So the
script runs under bash, not `sh`, and gets the interactive shell's PATH (nvm's `node`, say).
To try a branch's script before pushing it, `orca worktree create --base-branch <branch>`
takes a local branch that isn't on origin (same day).

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
removes the worktree's git registration and Orca's entry for it. It keeps the worktree's
branch (see the last point below). The main checkout's files
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
- The branch's commits aren't at risk. In Orca 1.4.257 (checked 2026-11-17) `orca worktree rm`
  keeps the local branch by default, `--force` included. `--delete-branch` attempts a safe
  delete: it deletes the branch only when Orca can prove it's already merged, and keeps it
  otherwise (`orca worktree rm --help`). Older hosts keep their old policy, which deleted a
  branch Orca could prove merged without the flag.

**After a merge, run the cleanup before Force delete.** This repo squash-merges, so Orca can
never prove the branch merged, and Force delete leaves it locally and on origin.
`cleanup_merged_branch <pr> master` (`docs/agents/code-review.md`, "After the merge") deletes
it in both places. git can't remove a worktree with a submodule, so the function detaches it
at its own HEAD instead and prints `<path> is detached at <sha>`. Ignored files stay, so the
checks above still apply before Force. It works from inside that worktree, so a session that
merged its own PR cleans up before the Force delete closes it (VIL-414); source the
worktree's own copy of the function, since the main checkout may not be pulled yet.

**In a repo with no submodules, detach the Orca worktree before running the cleanup from
another checkout.** There `cleanup_merged_branch` removes a linked worktree on the PR's branch,
so run from the main checkout it deletes the directory an Orca session is still working in.
Run `git -C <worktree> switch --detach` first, which detaches at the worktree's own HEAD and
changes no files: the function then finds no worktree on the branch and deletes only the branch
(skills, VIL-843 closeout, 2026-11-19).

**`gh pr close --delete-branch` while a worktree has the branch checked out closes the PR and
leaves the branch on origin.** For a PR from a branch in this repo (not a fork), delete it only
while it still points at the PR's head:
`git push --force-with-lease=refs/heads/<branch>:<head> origin :refs/heads/<branch>`, with
`<head>` from `gh pr view <N> --json headRefOid -q .headRefOid`. A branch that moved since is
refused; check with `git ls-remote origin refs/heads/<branch>` (skills PR 72, 2026-11-19).

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
`.claude/worktrees/`, so `wt done` doesn't manage them; remove them from Orca. The other way
round, `orca worktree list` leaves out worktrees under `.claude/worktrees/` when the repo's
`externalWorktreeVisibility` is `hide` (`orca repo show --repo <selector> --json`; Orca
1.4.257, 2026-11-17).

**A project whose sidebar fills with worktrees Orca didn't make has
`externalWorktreeVisibility: show`.** Tools that run `git worktree add` in the clone (hal-pilot's
runner, MergeWren review checkouts at a detached HEAD) then show up as `[pilot] …` and
`Detached HEAD @ <sha>` entries. On 2026-11-21 review-stack in the `hal-orca` environment was
`show`, while every project in hal's local runtime was `hide`. Check and fix it from the
personal Mac, whose Orca is paired with `hal-orca` (a session on hal as `david` has no paired
environments):

```
orca repo show --repo name:<repo> --environment hal-orca --json | grep -i externalWorktree
orca repo set --repo name:<repo> --environment hal-orca --external-worktree-visibility hide
```

This only hides them from the sidebar; the worktrees stay on disk.

## Launching an agent in a worktree

- `--agent` without `--surface` can open a terminal even when the agent's Chat UI default is Chat; pass `--surface chat` and read `launch.outcome` / `launch.receipt.detail` from `--json`. Source: on 2026-11-25, VIL-925's worktree was created without the flag and Claude opened as a terminal although Settings > Chat UI had Chat as Claude's default; the cause is unknown.

## What survives an Orca restart or update, and a reboot

Checked 2026-11-03 on the personal Mac, Orca 1.4.238.

- **Orca's terminals don't live in the app.** Each runs under an `Orca Terminal Host` daemon
  (`~/Library/Application Support/orca/daemon-host/macos/terminal-host-<build hash>/`), whose
  parent is launchd, not Orca. Quitting, restarting or updating Orca leaves the shells and
  whatever runs in them (Claude Code, Hermes) running, mid-turn included.
- **An update doesn't cut them off.** A new build starts a new host with a new hash, and the
  old host keeps serving its terminals. On 2026-11-03 the app started on 2026-10-23 was showing
  5 terminals: 2 from the host started 2026-10-20 (shells from 10-21 and 10-22) and 3 from its
  own host. A host with no shells left (here, one from 2026-10-18) idles until logout.
- **A reboot ends every local process**, the hosts included. The conversations stay on disk:
  Claude Code resumes with `claude --resume` (or `claude -c`) in the same directory, and Syd
  lists its sessions with `syd sessions list`. Whether Orca reopens the tabs by itself after a
  reboot hasn't been tested (the Mac had been up since 2026-09-22).
- **Atlas and Axiom don't run on the Mac.** They run in tmux on hal as `hal`, and their Orca
  tabs are on the `hal-svc` environment, so neither an Orca restart nor a Mac reboot touches
  them. `atlas` or `axiom` reattaches (`tmux new -A`). Rebooting hal ends them.
