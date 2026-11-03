---
created_at: "2026-11-02T19:51:48-08:00"
branch: "master"
head: "8defc50"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "check the 2026-11-03 01:30 PST hal pilot run (VIL-546, VIL-544, VIL-550 briefs) and reopen partial tickets after merges; pick tomorrow's briefs that evening, before 22:00 PT"
---
# HANDOFF — 2026-11-02, evening (PST)

This session picked up after the 15:07 handoff. The pilot run wasn't due until 01:30, so it did side work: a new rule for picking pilot briefs, cleanup of the `comment-cleanup` worktree, and Desktop Commander's remote device as an always-on LaunchAgent (VIL-571, #258), which went through nine MergeWren rounds before merging. The pilot queue for tonight was filled in the previous session and is unchanged.

## What We Built
- **#258** (`8defc50`): `helpers/install_desktop_commander_remote.sh` and `helpers/desktop_commander_remote.sh`. Docs are in `docs/reference/tooling.md` ("Desktop Commander remote"), with a rule line in `CLAUDE.md` and an invariant in `AGENTS.md`. David installed it at 18:54 PST and it's live (`com.dvillavicencio.desktop-commander-remote`, package 0.3.1, ~79 MB). Reached from the phone; `launchctl kickstart -k` brought it back in 4 s. The installed job script is byte-identical to `master`.
- **Pilot rule** (memory `feedback_pilot_queue_night_before.md`, `13d7c6c`): pick and check briefs the evening before each run, before about 22:00 PT, never days ahead.
- **Linear:** VIL-570 (evening alert when the pilot queue is empty, hal Local Coding Pilot project); VIL-571 Done; VIL-579 (rotate the remote's log; it records every received command in full); VIL-581 (deferred live QA: crash, sleep/wake, Wi-Fi drop, login).
- `wt done comment-cleanup`: worktree and `chore/comment-cleanup` deleted locally and on origin.

## Decisions Made
- **LaunchAgent, not LaunchDaemon:** a daemon would give claude.ai a root shell. David's defaults: keep the package's `caffeinate` (the Mac doesn't idle-sleep), pin the version, telemetry off, stop for good instead of looping when the sign-in fails.
- **Only one copy may run.** Two copies share one rotating refresh token, and a replayed one can revoke the sign-in. The job steps aside (stops its own copy, waits) when it finds a hand-started one; the installer and job refuse to start beside one.
- **The installer refuses to run through Desktop Commander:** it stops the agent, which is the process carrying the command, so it would cut the connection mid-run.
- **Declined MergeWren `6b5465f#2`:** a start-up `pgrep` error counts as a quick failure on purpose. Reason in #258's body.
- David approved merging past MergeWren's medium-only "not mergeable" banner, per the repo rule (only high/critical block). He also chose to defer the remaining QA to VIL-581 rather than hold VIL-571 open.

## What Didn't Work
- Test harnesses that background a shell *function* (`f &`, zsh or bash): `$!` is a wrapper, so the TERM missed the job and left an orphan. Background the `env … /bin/bash job` command itself.
- zsh doesn't word-split `$VAR`, so `env -i $ENVV …` passed one huge argument. Write such harnesses as bash scripts.
- A Bash call with `rm -rf "$VAR/…"` inside a multi-part command was blocked by Claude Code's safety check. Use literal paths, or put test steps in a script that removes fixed paths.

## What's Next
1. **Check the 11-03 01:30 PST pilot run:** `ssh hal` (as `david`), `tail ~/runs/log/runner.log`, then each `~/runs/log/vil-54{6,4}-*/run.json` and `vil-550-*/run.json`. Hand passing PRs to MergeWren with the evidence.
2. **After any pilot merge, reopen the parent ticket** (VIL-546, VIL-544, VIL-550): each brief covered only part, and the merge closes it (VIL-543).
3. **Evening, before 22:00 PT: pick the next night's briefs** from the `hal-overnight` label and check each on current mergewren `main` in a scratch clone (rule above). VIL-570 would alert when the queue is empty.
4. **David, in the MergeWren session:** mergewren#105 (VIL-448, MergeWren recommends merging); mergewren#103 (VIL-345, false-flags 4 adopted records: rework or close).
5. VIL-552/553/554 in hal-pilot; VIL-581 (remote QA, needs David at the Mac); VIL-579 (log rotation).

## Gotchas & Watch-outs
- **Never run `npx … remote` or the old `curl … | sh` command** while the agent is loaded, and never run the installer or `--remove` through Desktop Commander (it refuses now). The package's own log hints suggest `npx …@latest remote --logout`; running that would sign the Mac out.
- **macOS `pgrep` skips its own ancestors.** Run through Desktop Commander, `pgrep -f` can't see Desktop Commander; use `pgrep -a`.
- A Desktop Commander outage from the phone is fixable from a Claude Code session on the Mac (read `~/Library/Logs/desktop-commander-remote.log`, re-run the installer). If it stopped for good, the reason is in that log and in `stopped` in `~/Library/Application Support/desktop-commander-remote/`.
- Carried over: MergeWren gates pilot merges on David's own per-PR approval in its session; don't relay approvals. A brief's check must pass on `main` as it stands; run it in a scratch clone (`git clone --shared ~/runs/repos/mergewren`, then fetch `refs/remotes/origin/main` from it). Nothing else on hal's local models 01:30–05:00 PST.
- The skills plugin cache here was 0.7.1 last session; run `claude plugin update dv@villavicencio-skills` on machines not yet on 0.7.2.
