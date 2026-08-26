---
created_at: "2026-08-26T06:59:42-07:00"
branch: "master"
head: "423e41c"
resume_focus: "Nothing is pending in dotfiles — it is clean with zero open PRs. Before doing anything else, read the two new docs/solutions/best-practices/ entries: the two-step merge check gates every future merge, and atlas-tools work belongs in its own pane on the VPS, not here."
---
# HANDOFF — 2026-08-26, early morning (PDT)

Refresh of the 21:11 handoff from the same working stretch, written because that one carried
an instruction that is now known to be wrong (see *What Didn't Work*). No new commits since —
`HEAD` is still the handoff commit itself. The session's arc was one theme: **things that
report success while being wrong**. Four PRs merged, two learnings compounded, one falsified
rule replaced in the global instructions, and `atlas-tools` built on the VPS. Everything in
this repo is closed; the only live work has moved to its own pane.

## What We Built

- **`atlas-tools` on openclaw-prod** — `/home/node/Projects/atlas-tools`, VPS-side, **no
  remote** (Task 19, gated). 30/30 creation-acceptance criteria passed. What the repo doesn't
  tell you: Tasks 1 and 2 were committed *separately* with the plan's own messages, because the
  plan mandates RED→GREEN per task and the brief's single-commit framing would have skipped it.
  Task 2's RED was verified as 8 FAILED / **0 ERROR** — assertion failures from missing docs,
  not collection errors, which is the distinction the protocol actually requires.
- **PR #178 — `atlas-tools ⚙` herdr surface**, jump key `prefix+t`. The load-bearing fact is in
  CLAUDE.md's Herdr section: herdr's pane `cwd` is *always local*, so a remote project needs no
  Mac-side checkout. Reuses the existing `claude-code` ssh alias rather than a third shim.
- **PR #177 — blank-pane indicator + `settings.json` copy-seed.** Two unrelated changes in one
  PR because the second was found while wiring the first. `helpers/install_claude_settings.sh`
  and `migrate_claude_settings.py` are the durable pieces.
- **PR #176 — NVM shim cleanup.** *Closed* the follow-up instead of implementing it; the premise
  was wrong and no shim was ever needed.
- **PR #179 — `helpers/install_uv.sh`.** Three review rounds. See Gotchas.
- **`docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md`** — the
  two-step merge check. Read before merging anything.
- **`docs/solutions/best-practices/displayed-commands-must-be-runnable-verbatim.md`** — never
  display a command elided; the clipboard is a second channel, not the delivery channel.
- **`claude/CLAUDE.md` "Code Review"** — the *"poll until it stops saying `pending`"* rule was
  falsified and replaced. That rule caused the near-miss; replacing it mattered more than the
  docs describing it.

## Decisions Made

- **`settings.json` is copy-seeded, never symlinked** — three installers rewrite it in place.
  Do not restore a `link:` entry.
- **uv ships via its vendor installer, not the Brewfile** — `~/.local/bin` precedes Homebrew on
  PATH so a brewed copy is permanently shadowed, and uv self-updates. **Ruled out:** a Homebrew
  `python@3.x`; uv provisions its own interpreters.
- **atlas-tools git identity is repo-local** — user `node` had no global identity and setting
  one would affect unrelated repos on that host.
- **Declined a CodeRabbit finding on #179** (`$HOME` vs `~` in a comment) — five other helpers
  use `~`, and CLAUDE.md:94 targets literal usernames in code paths. Recorded on the thread and
  in the PR body; CodeRabbit accepted and resolved it. Do not relitigate.
- **The two compound runs were kept separate** — overlap scored Low (1/5). "An agent hands a
  human something that looks right and isn't" is a genre, not a cause.
- **The hook-before-master lesson gets no `docs/solutions/` entry** — it is already in CLAUDE.md
  as a gotcha, and unlike the other two it is a repo-specific operational trap rather than
  transferable methodology. Closed deliberately, not forgotten.

## What Didn't Work

- **The previous handoff said "re-run `./install` at some point." Do not do that from an agent
  shell.** Verified 2026-08-26: `brew bundle` has 16 unmet entries, two of which are hazards
  this repo already documents — **`herdr` 0.8.0 → 0.8.2**, where CLAUDE.md:382 notes a service
  restart *kills every pane process* (including the agent running the command), and
  **`docker-desktop`**, whose upgrade script invokes `sudo` internally and fails without a TTY,
  per CLAUDE.md:690, potentially aborting *after* unloading services. The config half of
  `./install` has nothing left to do anyway: all 22 symlinks are correct and both new seed steps
  are no-ops on this Mac. Run `brew bundle install` from a **real terminal**, deliberately.
- **Guessing at axiom's `unknown` status.** First hypothesis was `set-titles off`. Wrong — the
  pane was running `/bin/zsh -il`, the shim's clean-detach fallback, so no agent process existed
  to detect. `set-titles` *was* separately wrong and is also fixed, but it was not the cause. The
  wrong diagnosis had already been committed and needed correcting.
- **Three attempts to edit `~/.claude/settings.json` as the agent** — classifier-blocked each
  time. Working as designed; David ran the migration himself.
- **Two commands handed over elided with `...`** — both failed when pasted, and the second
  *partially executed*. Compounded as its own doc.
- **The work Mac is unreachable** from here (`ssh work` times out). David has taken it.

## What's Next

1. **Nothing in this repo.** Clean tree, 0 uncommitted, 0 open PRs, 0 stray branches, in sync
   with origin. Do not invent work here.
2. **`atlas-tools` has moved on without this session** — as of 06:51 PDT it is at **8 commits,
   through Tasks 3 and 4**, with its pane actively `working`. Its own committed `HANDOFF.md`
   names **Task 5 (bounded HTTP transport)** as next. That work belongs in the `prefix+t` pane;
   one writer per tree, so do not touch that repo from here.
3. **`brew bundle install` from a real terminal** when David wants the fleet restarted — see
   *What Didn't Work* for why it is not an agent-shell task.
4. **Work Mac** — `python3 helpers/migrate_claude_settings.py` if its `settings.json` predates
   2026-08-25. David's, explicitly. Idempotent, backs up first; `dot drift` there will say
   whether it is needed.
5. **Worth a look, no urgency:** `obscura` now appears in homebrew/core ("Headless browser for
   AI agents and web scraping"), spotted during the brew check. Relevant because the local
   `obscura` CLI is currently an `npm link` from `~/Projects/browse-gateway` and therefore
   cannot be tracked in `npm-requirements.txt`.

## Gotchas & Watch-outs

- **A green PR check is not a review.** `Review skipped: incremental reviews are disabled` and
  `Review rate limited` both *pass* with no review run; `mergeStateStatus: CLEAN` only means
  nothing is blocking. Read the check **description**, then enumerate unresolved threads via the
  GraphQL `reviewThreads` connection — the only surface exposing `isResolved`. Empty output is
  the merge signal. **Re-run after every re-review:** #179 added new findings in rounds 2 *and*
  3 after earlier ones were resolved and confirmed.
- **Verify the review ran against the current head** — compare `gh pr view --json headRefOid`
  against the newest review's `commit_id`. "Review completed" can be a stale verdict from two
  pushes ago. This was the final gate before merging #179.
- **A hook symlinked into this repo is branch-fragile.** `~/.claude/hooks/*.sh` resolve against
  the checked-out branch; one whose file exists only on a feature branch goes dangling on any
  `git checkout` and errors on every SessionStart in *every* project. Land the file on master
  before registering it in `settings.json`.
- **`>` on a dangling symlink succeeds silently** and writes to the symlink's *target* — it does
  not fail. Use `mktemp` + `mv -f`.
- **Never display a command with `...`** — Monologue replaces the clipboard, so David copies the
  displayed text. Long or nested-quoting command → stage a script, hand over a short invocation.
  `cat <<'PASTE' | tee /dev/stderr | pbcopy` makes display and clipboard identical by
  construction. Keep using `pbcopy`; never as the only channel.
- **`layout.apply` loses the agent name** — re-run `herdr agent rename` after any pane rebuild,
  or the jump key (which targets the name) breaks.
- **A herdr workspace reading `unknown` means check the pane's foreground process first.** A
  fallback `zsh` is the tell, not a detection-config problem.
- **atlas-tools' `docs/IMPLEMENTATION_PLAN.md` is hash-pinned** to the source in the Hermes
  plans dir. Do not rewrite, summarize, or reformat it.
- **Dotbot prints only undescribed directives at default verbosity** — `./install --dry-run`
  showing one line is not a broken preview. Use `-v` to see all 19 steps.
