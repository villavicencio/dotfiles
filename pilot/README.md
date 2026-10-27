# hal overnight pilot runner

The runner for the hal Local Coding Pilot (Linear project P-VIL-11, ticket VIL-396).
Opus writes the brief and the acceptance checks. Local `qwen3.8-27b` on hal does the work.
Each run ends as a PR titled `[pilot]`, reviewed by the repo's automatic reviewer. Nothing merges
without David. The PR is not a draft, because review-stack's watcher skips drafts (mergewren
`src/review_stack/watch.py`, `not pull.get("draft")`).

Everything here runs on **hal as `david`**, from `david`'s dotfiles clone at
`~/Projects/Personal/dotfiles`. None of it runs on the desk Macs, and Dotbot installs none of it.

## Files

| File | What it does |
|---|---|
| `runner.py` | The runner: gates, worktree, planner, worker, checks, commit, push, PR |
| `plan-prompt.md` | The planner's instructions. `{id}`, `{repo}`, `{title}`, `{body}` and `{readonly}` are filled in by `runner.py` |
| `pre-push` | Copied into every runner clone. It refuses any push except to `refs/heads/pilot/*`, and every branch delete |
| `kill.sh` | Kill switch: creates `~/runs/DISABLED` and stops a running run. `--on` removes the file |
| `dev.hal.pilot.plist.in` | LaunchDaemon template, 01:30 PT nightly |
| `install.sh` | Creates `~/runs`, checks the secrets, renders the plist, prints the admin commands |

## One run

1. **Gates**, checked before every ticket:
   - `~/runs/DISABLED` must not exist.
   - Only one runner at a time (`~/runs/.lock`).
   - `memory_pressure` must show at least 20% free.
   - LM Studio must be serving `qwen3.8-27b`.
   - No ticket starts after 06:00, and there are at most 3 tickets a night.
2. **Worktree.** The runner keeps one clone per repo under `~/runs/repos/`. Each run gets a
   fresh worktree under `~/runs/work/` on branch `pilot/<ticket>-<YYYYMMDD-HHMMSS>`, cut from
   origin's default branch (re-read from GitHub each run with `git remote set-head --auto`).
   A worktree with a `uv.lock` then gets one online `uv sync --locked` (10 minutes at most,
   output in `sync.log`). The runner doesn't enforce offline commands, but the "Environment on
   hal" note in each mergewren ticket has the worker and the checks use `uv run --offline`,
   which finds only what `david`'s uv cache (`~/.cache/uv`) holds. Without the sync, a dependency
   the repo added since the cache was last filled fails every check before any test runs,
   and a good change reads `[pilot][failed]` (VIL-391 and VIL-381 on 2026-10-23,
   `markdown-it-py`; VIL-528). If the sync fails, the run is `env-failed`: no planner, no
   worker, no PR, and the night ends. A ticket taken from the queue moves to
   `queue/env-failed/` (a `--ticket` or `--dry-run` run leaves its file where it is). It isn't
   requeued: a lasting cause, such as a broken lockfile, would otherwise fail the same ticket
   first every night and block everything behind it. Nothing shows on GitHub, so check
   `~/runs/log/runner.log` and the run's `sync.log`, fix the cause, and move the ticket back
   into `queue/`.
3. **Planner.** This is `claude -p --model opus` on `david`'s claude.ai login, with only Read,
   Grep and Glob, no MCP, a $10 API-equivalent cap and a 20-minute limit. It reads the
   repo's CLAUDE.md and AGENTS.md and returns JSON (`--json-schema`) with:
   - whether to proceed (declining is allowed);
   - the brief;
   - the acceptance checks;
   - the PR title.
4. **Worker.** This is `claude -p --bare` against LM Studio, with Read, Edit and Bash in
   `dontAsk` mode. Bash is limited to the plan's check commands plus read-only
   `git`/`ls`/`grep`/`rg`.
   - The runner appends the exact allowed commands to the brief, since a check with `| head`
     or `2>&1` added doesn't match its rule (a worker hit 14 such denials on 2026-10-21).
   - It gets 60 minutes, and is stopped if free memory falls below 10% or the kill switch
     appears.
   - Its env is the one from VIL-395's smoke test, with a 192k context cap, a 32k output cap
     and auto-compaction off. Qwen's thinking counts as output: with the old 8k cap, one turn
     thought for 9 minutes, hit the cap without acting, and had to start over. A 32k turn can
     take about 25 minutes, so the API request timeout is 30 minutes. With the 64k cap, the worker began compacting at about 30k
     tokens and then produced nothing for 10 minutes (VIL-251, 2026-10-21), which is likely
     why all six mergewren runs on 2026-10-18 hit the time limit. LM Studio loads
     `qwen3.8-27b` with 234k of context, so a worker that still fills its cap fails rather than
     compacting. The cap was 128k until 2026-10-22: VIL-251 and VIL-380 both ran out of it
     ("Prompt is too long") with the last turn near 109k. 192k leaves room for a 32k reply,
     since LM Studio's 234k holds the prompt and the reply together. A worker with more room
     can run longer, so expect some runs to end at the 60-minute limit instead.
   - Its output is `stream-json`, written to `worker.jsonl` as it happens, so a worker stopped
     at the time limit still leaves its transcript. For a stopped worker, turns and input
     tokens are counted from that transcript; output tokens read 0, because LM Studio's
     streamed messages don't report them.
5. **Checks.** The runner runs each check itself (`bash -c`, 15 minutes each), whatever the
   worker reported. A worker stopped at the time limit still gets its checks run when it
   changed files, because it may have finished the change and kept going (all six mergewren
   runs on 2026-10-18 did; two had passing changes that went out unchecked). A worker stopped
   by the kill switch or low memory gets no checks.
6. **Secret scan.** After the commit and before anything is pushed, gitleaks
   scans the run's commits and the PR title and body. dotfiles and browse-gateway are public,
   and so are their PRs, so a finding blocks the run: status `leak-blocked`, no push,
   no PR, and the local branch is kept in `~/runs/repos/<repo>` for David to inspect. A
   gitleaks that is missing or errors counts as a finding. The scan never runs on the
   checkout, because gitleaks always reads a scanned tree's own `.gitleaksignore`. The runner
   writes the commits (messages and patches) and the PR text into `~/runs/log/<run>/scan/`
   and scans that with `pilot/gitleaks.toml` (default rules, no allowlist), ignoring
   `gitleaks:allow` comments.
7. **Output.** The runner commits, pushes the `pilot/*` branch with the pilot token, and opens
   a PR (not a draft, so the reviewer picks it up). When the worker failed, a check failed, or
   nothing changed, the PR still opens, titled `[pilot][failed]`, so failures get counted. When the planner declines,
   there is no PR. If `gh pr create` itself fails, the run is recorded as `pr-failed`; the
   branch is pushed and `pr/body.md` holds the body to open it by hand. If the push fails, the
   local branch is kept in `~/runs/repos/<repo>` so the commit isn't lost.
   A planner error (often auth or a timeout) puts the ticket back in the queue and ends the
   night.

Each run's record is kept in `~/runs/log/<run-id>/`:
- `run.json` (the summary);
- `sync.log` (the dependency sync, for a repo with a `uv.lock`);
- `planner.json` and `brief.md`;
- `worker.jsonl` (the worker's transcript) and `worker.stderr`;
- `checks.log`;
- `pr/title.txt` and `pr/body.md`;
- `gitleaks.log`.

The worktree is removed after the run; the pushed branch stays.

## Credentials

The runner uses two pilot-only secrets in `~/.config/hal-pilot/`, both mode 600:
- `gh-token`: fine-grained `hal-pilot-runner`, covering dotfiles, bryancola.com,
  browse-gateway and mergewren, with no Workflows permission.
- `lmstudio-token`: `hal-pilot-worker`.

The rules for using them:
- The GitHub token goes only into the env of the `git` and `gh` processes that need it.
- In every git call, the runner first resets `david`'s credential helpers, including the
  github.com-scoped `gh auth git-credential` one, so `david`'s own login is never used.
  Checked on hal with `GIT_TRACE`.
- The planner's env drops the `ANTHROPIC_*` overrides, and the worker's drops
  `ANTHROPIC_API_KEY`.

**Accepted risk** (David, 2026-10-16, widened 2026-10-18; recorded on VIL-396): the worker runs
as `david`, and it can run code as `david`, not just read files. Its Bash allowlist doesn't
contain that: the check commands run code from the checkout (tests, repo scripts), and the
worker can edit that code first. Code run that way, by the worker or by the runner's own
check pass, has `david`'s access: `~/.ssh`, `david`'s `gh` login, the Claude login and the
network. Emptying `GH_TOKEN` wouldn't help, because `gh` then falls back to the stored login.
The real fix is OS isolation, either a Seatbelt profile or a separate `pilot` account. Revisit
before the pilot runs past two weeks or on more repos.

## The queue

The runner works from `~/runs/queue/*.md`, oldest first. Each ticket is a markdown file with
frontmatter:

```markdown
---
id: VIL-123
repo: dotfiles
title: Fix the thing
---
The ticket body, as David approved it.
```

The runner handles ticket files like this:
- A ticket the runner starts moves to `queue/taken/`.
- A file that doesn't parse, or names a repo outside the pilot, moves to `queue/rejected/`.
- "Oldest first" means by file modification time, not by name. Copy files in the order you
  want them run.
- How approved tickets get into the queue is VIL-397. Until then they're copied in by hand,
  and each approved ticket gets the `hal-overnight` label in Linear.

Which tickets fit (learned 2026-10-18 to 10-22):
- **No open decision for David.** The planner declines a ticket that leaves a design or
  policy choice open (VIL-252 on 2026-10-22). Either decide it in the queue file, or queue
  only the part that's already decided (a ticket's "part C", say).
- **A command can check it.** A test file to run, a test to add, or exact pass criteria.
- **Not mergewren's review logic** (incremental review, baseline rules, read evidence): a
  worker change there would change the reviewer that grades the pilot (VIL-397).
- **No network or live service in the check.** A link-preview check or an image CDN rules a
  ticket out.
- **About an hour of work.** Name a smaller part that's still a good PR, so a worker that
  runs short has a clear place to stop.
- Copy the "Environment on hal" note from a ticket in `queue/taken/` into each mergewren
  ticket. It says to run tests with `--offline`, and names the test that always fails on hal.

## Install (on hal)

1. As `david` (SSH: `ssh david@hal`), from the dotfiles clone once this is on master:
   `~/Projects/Personal/dotfiles/pilot/install.sh`
2. As `admin` on hal (admin's password for sudo), run the commands `install.sh` prints:
   copy the plist into `/Library/LaunchDaemons/`, `chown root:wheel`, then
   `launchctl bootstrap system` (after a `bootout`, so the sequence is safe to repeat).

The schedule is a LaunchDaemon, not a LaunchAgent, because `david` has no GUI session on hal
(`gui/502` doesn't exist), so a LaunchAgent would never load.

## Run by hand

As `david` on hal:

```sh
~/Projects/Personal/dotfiles/pilot/runner.py --dry-run --ticket <file> --ignore-window   # gates, worktree, online uv sync
~/Projects/Personal/dotfiles/pilot/runner.py --once --ignore-window                      # one ticket from the queue
~/Projects/Personal/dotfiles/pilot/timing.py ~/runs/log/<run>/ ...                        # where a worker's time went
```

`timing.py` splits a worker's time into thinking, tools and the rest, and shows the longest
single think, the largest context and how the run ended ("Prompt is too long" is a full
context). Tool calls that ran at the same time are counted once. A worker with no `result`
event (stopped at the limit, or died) has a transcript that ends at its last event, often
minutes before the end, so the end comes from `worker.ended_at` in `run.json`, and the report
says "stopped" only when `worker.killed` is set. A tool call still running at the end counts
as tool time; otherwise the time after the last event is shown as "cut off", a think or reply
that never reached the transcript. Without `ended_at` (no `run.json`, a `runner-error` run,
or a run from before 2026-10-22) the report is partial: it says so, and its total stops at
the last event. Read `system/thinking_tokens` events
with care: they're running estimates per step, so adding them up gives nonsense. On the first four transcripts (2026-10-21/22),
thinking was 54–72% of the worker's time, and one think ran 15.7 minutes.

## Stop it

As `david` on hal:

```sh
~/Projects/Personal/dotfiles/pilot/kill.sh        # stop now and stay off
~/Projects/Personal/dotfiles/pilot/kill.sh --on   # allow runs again
```

The kill switch does **not** unload either LM Studio model. Atlas and Axiom use both (VIL-395).
To remove the schedule as well, run `sudo launchctl bootout system/dev.hal.pilot` as `admin`.
