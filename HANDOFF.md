---
created_at: "2026-10-27T10:16:31-07:00"
branch: "master"
head: "b2085b3"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-10-27, morning (PDT)

A long session, from the 2026-10-23 pickup to 2026-10-27. Six dotfiles PRs merged: the statusline ticket badge, a follow-up on how capture handles hooks and plugins an installer added, a CI break from Homebrew dropping `tldr`, and the pilot runner's dependency sync (VIL-528). VIL-391 part B ran on hal and came back with every check passing. MergeWren spent several hours halted on a false-positive incident lock, which David cleared.

## What We Built
- **#250** (VIL-522, Done): `claude/statusline-command.sh` shows a linked `VIL-N` badge when the branch is `<type>/vil-N-<slug>`.
  - It matches `vil-` only, so the work Mac's tracker keys never trigger it.
  - The global naming rule is in `claude/CLAUDE.md` and `codex/AGENTS.md`.
- **#249** (VIL-431, Done): `--capture` and `dot drift` ignore hooks the Orca and iTerm2 installers add. The marker list is kept in three places: `install_claude_settings.sh`, `report_drift.sh` and `migrate_claude_settings.py`.
  - **Capture refuses when** the live file lacks a tracked hook (matched on event and exact command), a tracked plugin, or a tracked top-level key. A tracked object whose live value is `null` or a list also counts as missing.
  - **The migration** adds the missing entries back and prints separately any key it replaced.
  - Tracks `cc-plugin-you-should-know@builtin`.
- **#251:** capture's refusal message and `docs/reference/claude-code-config.md` now say what to do for a hook or plugin changed live on purpose: copy the change into the tracked file first, then migrate, then capture. Run the migration on an intentional change and it restores the old hook beside the new one, so both run.
  - David waived high finding 62b9dfe#1. It contradicted b6d7a4a#1, which needs the migration to keep running for its herdr-hook cleanup. The waiver is recorded in the PR.
- **#254:** Homebrew disabled the `tldr` formula (unmaintained; the replacement is `tlrc`). That broke CI's `macos` leg on master and every branch from 2026-10-25.
  - `brew/Brewfile` now names `tlrc`.
  - `helpers/migrate_tldr_tlrc.sh` runs before the desk `brew bundle`. It unlinks `tldr`, links or installs `tlrc`, and only then uninstalls `tldr`. If `tlrc` fails it relinks `tldr`. It never overwrites a `bin/tldr` it doesn't own.
- **#252** (VIL-528, Done): `pilot/runner.py` `sync_env` runs `uv sync --locked` online, once per run, for any repo with a `uv.lock`.
  - **A failed sync** is recorded as `env-failed`. No PR opens, the ticket moves to `queue/env-failed/`, and the night stops.
  - **A run stopped by SIGTERM** at any stage is recorded as `disabled` (kill switch) or `killed`.
  - **Name clashes:** `shelve` and `shelve_back` pick the first free numbered name.
  - **Deployed:** David pulled hal's runner checkout (`david`, `~/Projects/Personal/dotfiles`) to `b2085b3`.
- **#248:** `ci/op-agent-checks.sh` asserts that refused cases never call the stub.
- **Docs pushed straight to master:**
  - `docs/reference/shell-and-path.md`: zsh's `path` and `fpath` are tied to `PATH` and `FPATH`, so never use them as loop variables.
  - `docs/agents/code-review.md`: `mergeStateStatus: UNSTABLE` means a check failed, and the merge button still works.
- **Linear:**
  - VIL-422 Done (herdr was never on the work Mac).
  - VIL-528 filed and Done.
  - VIL-529 (connector-active false alarm) and VIL-530 (Slack halt alert) were filed by the MergeWren session.
- **Memory:** `feedback_work_mac_parked.md` says to raise no work-Mac follow-ups until David brings the work Mac up again.

## Decisions Made
- **Statusline ticket source:** the branch name only, showing the id without a title. A per-branch config, the PR body and the transcript were all ruled out. Linear's GitHub integration acting on branch names is fine.
- **Installer hooks stay untracked:** David chose "ignore them" over tracking them on the desk Macs only.
- **Nested guard, not top-level only (David, 2026-10-24):** capture refuses on a missing nested hook or plugin as well as a missing top-level key. He chose that over dropping the plugin or waiving the finding.
- **`env-failed` sets the ticket aside rather than requeuing it,** from a side agent's review point. A lasting cause, such as a broken lockfile, would otherwise fail the same ticket first every night. The night still stops, so a network blip costs one ticket, not the whole queue.
- **Declined with reasons** (on the threads and in the PR bodies):
  - #254 1a79a02#1: a foreign `bin/tldr` exits 0, so the install doesn't stop over a working tool.
  - #254 9005ee7#1: doc wording.
  - #252 f14143b#2: a `uv` that can't execute ends as `runner-error`. Catching it means a catch-all `OSError`, and that catch-all swallowed SIGTERM.
- **#249 merged** with the medium 5373489#1 still listed. It was fixed twice, and incremental rounds carried it forward with no new reasoning. The repo gate blocks on high or critical only.

## What Didn't Work
- **A broad `except OSError` around `run_limited`** (in #252) also caught the `PermissionError` raised by `on_sigterm`, so a kill during the sync read as `env-failed`. Replaced with a `shutil.which("uv")` check before the sync starts.
- **Timestamp suffixes for shelved tickets** repeat within the same second, so a clash could still overwrite. They became numbered free names.
- **Testing the runner locally:** the Claude Code sandbox refuses `setsid`, so `start_new_session=True` Popen fails with EPERM. Test `runner.py` process handling on hal as `david`, in a scratch dir with `PILOT_RUNS` set.
- **zsh test harnesses:** an unquoted `$var` isn't word-split in zsh (use `${=var}`), and `read … path` overwrites `PATH`. Each made a correct script look broken once.

## What's Next
1. **mergewren#90** (VIL-391 part B, from Sun 2026-10-25 01:30 PT): titled `[pilot][failed]` only because the worker hit its 60-minute limit. All three checks passed: the 2 new regression tests, both test files, and ruff. MergeWren's comment says "review incomplete". The MergeWren session owns it and was told (Remote Control, delivery unconfirmed). Once #90 and #89 merge, VIL-391 can close. VIL-381 part B waits on #89.
2. **Pilot queue is empty.** Packets live in hal's `~/runs/queue/` (as `david`). Copy the "Environment on hal" block from `queue/taken/14-vil-391.md`. The runner now syncs deps itself, so `--offline` checks no longer need a warm cache.
3. **VIL-515:** move `pilot/` into a private repo. VIL-528 is now done, so the move can go ahead.
4. **This Mac still has both `tldr` and `tlrc`.** The next `./install` runs `migrate_tldr_tlrc.sh` and swaps them.
5. **Old pilot branches #79 and #81** are still on mergewren's origin, waiting for David's OK to delete them. Not done.

## Gotchas & Watch-outs
- **MergeWren halts on an incident lock and posts nothing.** Its last comment just stops, while the watcher process is alive, idle and has no children. Only David clears the lock: `docs/runbooks/incidents/` in the mergewren repo, with the lock at `~/.local/state/review-stack/lane/.lock` as `hal`. VIL-529 covers the false-positive class. Clearing doesn't re-review the head that tripped it.
- **MergeWren's incremental rounds carry a finding forward without re-reading the fix.** After a real fix, a "still open" entry with no new reasoning can be declined on the thread. Mediums don't block, but a high still needs fixing or David's waiver.
- **Check CI before every merge:** `gh pr checks <N> --json name,state`. #251 merged with `macos` red because `UNSTABLE` was missed.
- **On macOS, `os.killpg(pgid, 0)` returns EPERM** (not ESRCH) for an exited, unreaped group leader. `stop_groups` now treats that as gone.
- **This repo's `merge.ff` setting refuses plain `git merge origin/master`** on a diverged branch. Use `--no-ff`.
- **`wt done` stops on ignored files** in the worktree, such as `settings.local.json` copied by `.worktreeinclude` or a stray `__pycache__`. Check the copy matches the main checkout's, remove both, then rerun.
- **A squash merge's commit message lists every branch commit,** so ids named only in commits (VIL-381 and VIL-391 in #252) land on master. Both were checked and still In Progress.
