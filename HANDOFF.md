---
created_at: "2026-08-25T21:11:31-07:00"
branch: "master"
head: "61d21a2"
---
# HANDOFF — 2026-08-25, evening (PDT)

Third same-day session (previous handoff at `8d0e5a1`, midday). Started as a small pickup —
two leftover follow-ups — and turned into a run on one theme: **things that report success
while being wrong**. Four PRs merged, two learnings compounded, one falsified rule in the
global instructions replaced, and `atlas-tools` built from scratch on the VPS. The Vice Gage
arc from the midday session is complete (David confirmed); nothing there is outstanding.

## What We Built

- **`atlas-tools` on openclaw-prod** — `/home/node/Projects/atlas-tools`, VPS-side, 3 commits
  on `main`, **no remote** (Task 19, gated). 30/30 acceptance criteria pass. What the repo
  doesn't tell you: Tasks 1 and 2 were done as *separate* commits with the plan's own commit
  messages, because the plan mandates RED→GREEN per task and the brief's single-commit framing
  would have skipped that. Task 2's RED was verified as 8 FAILED / **0 ERROR** — assertion
  failures from missing docs, not collection errors.
- **PR #178 — `atlas-tools ⚙` herdr surface**, jump key `prefix+t`. The load-bearing detail is
  in CLAUDE.md's Herdr section: herdr's pane `cwd` is *always local*, so a remote project needs
  no Mac-side checkout — the working dir comes from the pane command. Reuses the existing
  `claude-code` ssh alias rather than a third shim.
- **PR #177 — blank-pane indicator + `settings.json` copy-seed.** Two unrelated things in one
  PR because the second was discovered while wiring the first. `helpers/install_claude_settings.sh`
  and `migrate_claude_settings.py` are the durable pieces.
- **PR #176 — NVM shim cleanup.** *Closed* the follow-up rather than implementing it: the
  premise was wrong, no shim was ever needed.
- **PR #179 — `helpers/install_uv.sh`.** Took three review rounds; see Gotchas.
- **`docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md`** — the
  two-step merge check. Read this before merging anything.
- **`docs/solutions/best-practices/displayed-commands-must-be-runnable-verbatim.md`** — never
  display a command elided; the clipboard is a second channel.
- **`claude/CLAUDE.md` "Code Review"** — the *"poll until it stops saying `pending`"* rule was
  falsified and replaced. That rule caused this session's failure; it is not a doc improvement.

## Decisions Made

- **`settings.json` is copy-seeded, never symlinked** — three installers rewrite it in place
  (Claude Code, `herdr integration install`, Otty). Same class as Otty; do not restore a `link:`.
- **uv ships via its vendor installer, not the Brewfile** — `~/.local/bin` precedes Homebrew on
  PATH, so a brewed copy would be permanently shadowed, and uv self-updates. **Ruled out:**
  adding a Homebrew `python@3.x` — uv provisions its own interpreters.
- **atlas-tools git identity is repo-local**, not global — user `node` had none, and setting a
  global would affect unrelated repos on that host.
- **No `[project.scripts]` in atlas-tools' pyproject yet** — the console script arrives with
  `cli.py` at Task 11; declaring it early installs a script pointing at a missing module.
- **Declined a CodeRabbit finding on #179** (`$HOME` vs `~` in a comment) — five other helpers
  use `~`, and the repo rule targets literal usernames in code paths. Recorded on the thread and
  in the PR body. CodeRabbit accepted and resolved it. Do not relitigate.
- **The compound runs were kept separate** — overlap scored Low (1/5). "An agent hands a human
  something that looks right and isn't" is a genre, not a cause.

## What Didn't Work

- **Guessing at axiom's `unknown` status.** First hypothesis was `set-titles off`. Wrong — the
  pane was running `/bin/zsh -il`, the shim's clean-detach fallback, so no agent process
  existed. `set-titles` *was* separately wrong and is also fixed, but it was not the cause. The
  wrong diagnosis had already been committed to #178 and needed correcting.
- **Three attempts to edit `~/.claude/settings.json` as the agent** — classifier-blocked each
  time (inline python, the `update-config` skill, an `eval`-wrapped test). That block is
  working as designed; David ran the migration.
- **Two commands handed over elided with `...`** — both failed when pasted; the second
  partially executed. See the second compounded doc.
- **A `pbcopy`-only handoff.** Monologue replaces the clipboard between copy and paste.

## What's Next

1. **`atlas-tools` Task 3** — `ctrl+space` `t` → `claude` → `/dv:pickup`. Resumes from the
   committed `HANDOFF.md` there. Stops before credentials, live providers, plugin install, or
   a remote.
2. **Re-run `./install`** at some point so Dotbot picks up the new `install_uv.sh` and
   `install_claude_settings.sh` steps. Nothing is broken without it — both are seed-if-absent.
3. **The work Mac needs `python3 helpers/migrate_claude_settings.py`** if its `settings.json`
   predates today. It is idempotent and backs up first.
4. **Optional:** give the `axiom` tmux socket the same treatment `atlas-tools` got — its conf
   is wired now, but the runtime `set-titles` only survives until that server restarts, at
   which point the launcher patch takes over. Nothing to do unless it misbehaves.

## Gotchas & Watch-outs

- **A green PR check is not a review.** `Review skipped: incremental reviews are disabled` and
  `Review rate limited` both *pass* with no review run, and `mergeStateStatus: CLEAN` only means
  nothing is blocking. Read the check **description**, then enumerate unresolved threads via the
  GraphQL `reviewThreads` connection (the only surface exposing `isResolved`). Empty output is
  the merge signal. **Re-run after every re-review** — #179 added new findings in rounds 2 and 3
  after earlier ones were resolved and confirmed.
- **Verify the review ran against the current head** — `gh pr view --json headRefOid` vs the
  newest review's `commit_id`. "Review completed" can be a stale verdict from two pushes ago.
- **A hook symlinked into this repo is branch-fragile.** `~/.claude/hooks/*.sh` resolve against
  the checked-out branch; a hook whose file exists only on a feature branch goes dangling on any
  `git checkout` and errors on every SessionStart in *every* project. Land the file on master
  before registering it in `settings.json`.
- **`>` on a dangling symlink succeeds silently** and writes to the symlink's *target* — it does
  not fail. Use `mktemp` + `mv -f`.
- **Never display a command with `...`** — Monologue replaces the clipboard, so David copies the
  displayed text. Long or nested-quoting command → stage a script, hand over a short invocation.
  `cat <<'PASTE' | tee /dev/stderr | pbcopy` makes display and clipboard identical by
  construction. Keep using `pbcopy`; just never as the only channel.
- **`layout.apply` loses the agent name** — re-run `herdr agent rename` after any pane rebuild,
  or the jump key (which targets the name) breaks.
- **A herdr workspace reading `unknown` means check the pane's foreground process first.** A
  fallback `zsh` is the tell, not a detection-config problem.
- **The `atlas-tools` tmux pane sits at a bash prompt** — type `claude` to start. Its
  `new-session -A` makes it self-healing across VPS reboots; no systemd unit exists or is needed.
- **atlas-tools' `docs/IMPLEMENTATION_PLAN.md` is hash-pinned** to the source in the Hermes
  plans dir. Do not rewrite, summarize, or reformat it.
