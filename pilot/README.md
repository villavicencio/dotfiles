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
   - It gets 60 minutes, and is stopped if free memory falls below 10% or the kill switch
     appears.
   - Its env is the one from VIL-395's smoke test: a 64k context cap and an 8k output cap.
5. **Checks.** The runner runs each check itself (`bash -c`, 15 minutes each), whatever the
   worker reported.
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
- `planner.json` and `brief.md`;
- `worker.json`;
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
- How approved tickets get into the queue is VIL-397.

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
~/Projects/Personal/dotfiles/pilot/runner.py --dry-run --ticket <file> --ignore-window   # gates + worktree only
~/Projects/Personal/dotfiles/pilot/runner.py --once --ignore-window                      # one ticket from the queue
```

## Stop it

As `david` on hal:

```sh
~/Projects/Personal/dotfiles/pilot/kill.sh        # stop now and stay off
~/Projects/Personal/dotfiles/pilot/kill.sh --on   # allow runs again
```

The kill switch does **not** unload either LM Studio model. Atlas and Axiom use both (VIL-395).
To remove the schedule as well, run `sudo launchctl bootout system/dev.hal.pilot` as `admin`.
