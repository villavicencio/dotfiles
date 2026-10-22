# Linear, branching and review

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Issue tracking — Linear
Issues live in **Linear**, project `Dotfiles`, team `Villavicencio` (key `VIL`):
https://linear.app/villavicencio/project/dotfiles-74974922348e

Migrated off the GitHub Projects board on 2026-08-20 with zero open issues — the old
board (https://github.com/users/villavicencio/projects/2) and the repo's 44 closed
GitHub issues remain as read-only history. **Never create new GitHub issues**; use
`/ticket` (which drives `mcp__linear__save_issue`) or the Linear UI. The Linear MCP
server is configured globally in `~/.claude.json` (machine-local; personal Mac only —
the work Mac deliberately does not use Linear MCP, work tracking lives in other tools);
its tools are deferred, so load them via ToolSearch first. On the work Mac, `/ticket`'s
MCP path is unavailable — capture dotfiles tickets via the Linear web UI instead.

## Branching & pull requests
Work on a **feature branch and merge via pull request** — this is the default for
this repo, not just ticket work. Avoid committing directly to `master`.

- **Branch per change.** Cut a branch off `master` before starting; name it
  conventionally by type: `feat/…`, `fix/…`, `chore/…`, `docs/…`,
  `style/…` (e.g. `feat/statusline-slider-bars`).
- **One PR per logical change.** Push the branch and open a PR with `gh pr create`;
  let the PR carry the review surface. Keep `master` always-green.
- **Merge, then clean up.** After merge, delete the branch and mark any linked
  Linear issue `Done` (`mcp__linear__save_issue` with the issue id + `state: "Done"`)
  as part of the workflow.
- **Documentation and small changes may go straight to `master`** (relaxed
  2026-08-25) — doc edits, typo fixes, and handoff commits included. The rule
  targets behavior and config changes, where review and a clean history matter.
  When in doubt, branch.
- **PR review is review-stack, David's own reviewer** (since 2026-09-24, PRs #190 and
  later; replaces CodeRabbit here). It reviews **every new head** of an open, non-draft PR
  automatically, 2–6 minutes after the push, so there is no trigger comment and no hourly
  budget. It posts **one PR comment per head**, whose first line is
  `<!-- review-stack:head=<full sha> run=<id> -->`, followed by findings with a severity and
  a `path:line`. Wait for the comment for the *current* head (poll every 60 s, give up after
  20 min):

  ```bash
  gh pr view <N> --repo villavicencio/dotfiles --json headRefOid,comments --jq '.headRefOid as $h | [.comments[] | select(.body | contains("review-stack:head=" + $h))] | last | .body // "PENDING"'
  ```

  Fix the real findings and push; the new head is re-reviewed automatically. **Merge
  readiness:** the latest review-stack comment for the current head has no high or
  critical finding that is neither fixed nor explicitly waived with David. It doesn't read
  thread replies, so record a declined finding in your summary to David and the PR body.
  **Since MergeWren 0.4.0 (2026-10-09) each finding is also an inline review thread**, and
  they stay open after the finding is fixed. Resolve a thread once its finding is listed
  under "Resolved" in a later review, or once it is declined, so the unresolved-threads
  check comes back empty before merging. An incremental round ("Incremental since …") can
  keep a finding under "Still open" after the code it describes is gone: on #239,
  `74e3fde#1` described `timing.py` adding `duration_s`, and stayed open for two rounds after
  that line was removed. Check the finding against the current code. If it no longer
  applies, decline it as stale on its thread and in the PR body, then resolve the thread.
  Pushing another fix for it won't close it. A **`partial`** verdict means a file wasn't
  reviewed, not that the review passed. `policy-excluded-path` means a file under
  `coverage_expectation` was dropped, e.g. a `<base>.<suffix>` name such as
  `zsh/zprofile.server` whose suffix OCR doesn't recognise (#208, fixed in MergeWren by
  VIL-316). Get the same head re-run; a new push only reviews what changed after it.
  A comment saying "⚠️ The review did not complete" alerts Atlas; tell David instead of
  waiting. So does a comment whose verdict is **`failed`** or which says "Incomplete review" /
  "NOT COMPLETE": its "0 findings ✅" means *not reviewed*, not clean. Two causes seen so far
  (2026-09-24/25): a held run lock, and the connector tripwire, which fires on the text
  `github_` anywhere in the diff (#194's gitleaks smoke test, `github_token = …`, set it off). Both
  need Atlas to re-run the same head; nothing on the PR side is wrong. **After an interrupted
  run, don't merge on the re-run alone — ask David whether the interrupted run's draft had
  findings.** Runs aren't deterministic: on #194 the stopped run's draft held 3 findings (two
  medium, one a false-green CI path) that the clean 0-finding re-run didn't raise, and they only
  surfaced after the merge, so they landed as a follow-up (#196). CodeRabbit may still comment on its own schedule. That's optional input: don't
  wait for it, and don't mention or re-trigger `@coderabbitai`.

Picking up a board ticket always gets its own branch (never work a ticket on
`master`).

**A docs-only PR skips the install matrix — but not the review.**
`install-matrix.yml` declares `paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']`,
so a markdown-only change never triggers `linux`/`macos`/`windows`; do not wait for a run that
will never start. **review-stack still reviews it** (every head of a non-draft PR), and
reviewers do have findings on markdown, as CodeRabbit did on #171. So `mergeStateStatus:
CLEAN` is not by itself the merge signal — wait for the review-stack comment for the current
head and triage its findings first. `CLEAN` only tells you nothing is *blocking*; a review
that hasn't posted yet also reads clean.

**Markdown still has to pass R3, which a markdown-only push never runs.** The post-apply R3
check scans every tracked file except `docs/**` and `HANDOFF.md` for a literal home path
(`/Users/` followed by a name) and for hostnames. That includes this file, `AGENTS.md` and
`claude/*.md`. A literal path pushed straight to master goes unnoticed until the next PR
that does run the matrix fails on all three Unix legs for a file it never touched (#211,
fixed by #213). Write `/Users/<account>/`, `~` or `$HOME` instead.
