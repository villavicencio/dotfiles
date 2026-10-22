# Code review and merging

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

Repos with their own review rules override this: dotfiles (review-stack since 2026-09-24) and bryancola.com (MergeWren, review-stack), and any repo whose `CLAUDE.md`/`AGENTS.md` names its own reviewer as the gate. In those repos, don't request or wait for CodeRabbit (`@coderabbitai review` spends the per-developer quota for nothing); a CodeRabbit check that appears there on its own is informational, not a gate.

**PR review runs through CodeRabbit; `dv:gauntlet` is the escalation, not the default**
(reconciled across dotfiles / borealis / skills, 2026-08-24). Before this, the global rule named
gauntlet as the blanket default while two repos had already overridden it per-project — this
file is the single source of truth, and per-repo `AGENTS.md` files should point here rather
than restate it.

**Reach for CodeRabbit** for review of a PR diff. **Reach for `dv:gauntlet`** when the diff is
large or risky enough to warrant a convergent find→refute→fix loop, when CodeRabbit is throttled
and the review genuinely cannot wait, or when reviewing something that is not a PR. Bare
`dv:gauntlet` is the full autonomous loop (it fixes and commits); `dv:gauntlet report` is a single
report-only round and is the right rate-limit fallback. The skill owns its own procedure — rounds,
budgets, the fingerprint ledger, stop rules — so don't re-derive it per project.

Either way, **don't hand-roll a review**: no `codex exec review`, no Claude↔Codex loops, no
"fan out reviewers" or "spin up a skeptic panel," including under `/effort ultracode` or workflow
orchestration. Custom workflows may supply research or critique *lenses* upstream; the review of
the diff itself routes through one of the two tools above.

## Merging on a CodeRabbit review

- **Wait for the review, and wait for each re-review** (David, 2026-08-24). Do not merge while its
  verdict is `CHANGES_REQUESTED`, even after pushing a fix that you believe resolves the finding —
  the stale verdict is not permission. If the re-review is throttled, wait for the window; the one
  exception is the docs/config carve-out under "Rate limits" below, and it requires recording the
  throttle in the PR body.
- **Never push while a review is in flight.** A push that lands mid-review *aborts* it —
  CodeRabbit posts "Review failed — the head commit changed during the review" — and the spent
  review is gone with nothing to show for it, still charged against the hourly allowance. Land
  every edit first, *then* request the round. This matters most when addressing findings: batch
  the fixes, push once, then comment `@coderabbitai review`. (Observed on skills#36, in the very
  commit documenting the throttle rules.)
- **Read the check DESCRIPTION, not its state** — this is the one that has bitten repeatedly.
  Poll the check line rather than the reviews API (`gh pr checks <N> | grep -i '^CodeRabbit'`),
  but **"not `pending`" is not a completion test**: three different descriptions sit on a
  *passing* check, and only one of them means a review ran.

  ```bash
  gh pr checks <N> --json name,state,description \
    -q '.[] | select(.name|test("CodeRabbit";"i")) | "\(.state)\t\(.description)"'
  ```

  | Description | State | Review ran? |
  |---|---|---|
  | `Review completed` | pass | **yes** |
  | `Review skipped: incremental reviews are disabled` | pass | **no** — request one with `@coderabbitai review` |
  | `Review skipped: manual review required for this OSS repository` | pass | **no** — posted when the PR opens on a repo under 10 stars; request one |
  | `Review rate limited` | pass | **no** — throttled |
  | `GitHub unavailable during review post` | pass | **no** — the review ran but its comments never posted; retry with `@coderabbitai full review` |
  | `Review failed — the head commit changed during the review` | — | **no** — a push aborted it |
  | `Review in progress` / `pending` | pending | unfinished |

  `GitHub unavailable during review post` leaves no review object and no threads, so the
  unresolved-threads check below comes back empty and the PR reads `CLEAN` (skills#44,
  2026-10-07). A plain `@coderabbitai review` is refused on a head CodeRabbit already reviewed;
  `@coderabbitai full review` reviews the current head again and uses the hourly slot. Whether
  the refused request also uses it hasn't been checked.
- **After requesting a review, read only statuses posted after the request.** A watcher that
  stops at the first status it finds can read one left over from when the PR opened: on skills#43
  and browse-gateway#149 (2026-10-06) it reported `manual review required for this OSS
  repository` while CodeRabbit was already reviewing, and the real review then found 5 issues.
  Record the time just before you post the request, then read the newest CodeRabbit status
  created after it:

  ```bash
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ); gh pr comment <N> --body '@coderabbitai review'
  gh api repos/<owner>/<repo>/commits/<head-sha>/statuses -q "[.[]
    | select(.context|test(\"CodeRabbit\";\"i\")) | select(.created_at > \"$t\")]
    | sort_by(.created_at) | last | .description // \"PENDING\""
  ```

  `gh api -q` has no `--arg`, so the time is spliced into a double-quoted filter.

  `PENDING` (no status since the request) means CodeRabbit hasn't picked it up yet, not that it
  finished. The table above says which description to trust; this says which status to read it
  from.

  Poll the reviews API instead and it fires early or never: the bot posts as `coderabbitai` on
  some PRs and `coderabbitai[bot]` on others, and its replies to your thread replies register as
  `COMMENTED` reviews.
- **Enumerate unresolved threads before every merge decision** — a completed review is not a
  triaged one, and findings arrive as `COMMENTED` reviews that never block. GraphQL is the only
  surface exposing `isResolved`:

  ```bash
  gh api graphql --paginate -F owner=<owner> -F repo=<repo> -F pr=<N> -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){ repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){ reviewThreads(first:100,after:$endCursor){
      pageInfo{ hasNextPage endCursor } nodes{ isResolved path line originalLine
      comments(last:1){ nodes{ author{login} } } } } } } }' \
   -q '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)
       | "UNRESOLVED \(.path):\(.line // .originalLine)"'
  ```

  **Empty output is the merge signal; any line is a blocker.** Use `.line // .originalLine` —
  bare `.line` is `null` on stale-position threads and renders real findings as `path:null`.
  Re-run it **after every re-review**, not once per PR: a re-review can add findings after the
  previous round was fully resolved and confirmed. On the REST fallback
  (`gh api --paginate repos/<owner>/<repo>/pulls/<N>/comments`, which has no resolution state)
  `--paginate` is mandatory — `per_page` alone caps at one page and silently drops findings past
  it, and `gh api repos/<owner>/<repo>/issues/comments/<id>` 404s for review comments (they live
  under `pulls/comments/<id>`).
- **Triage every finding**: fix it on the branch, or decline it with the reason recorded both on
  the thread and in the PR body. A finding you disagree with is a standoff you document, not one
  you merge past silently.
- **A trivial diff may skip review**, but the skip and its reason must be stated when reporting
  the merge. The skip is fine; the silence isn't.
- **`mergeStateStatus: CLEAN` does not mean reviewed.** It means nothing is *blocking* the
  button. There are at least three ways a PR reads clean with findings outstanding: the review
  was **throttled** (below), it was **skipped** because `auto_incremental_review: false` (below),
  or it **completed and found things** — `COMMENTED` reviews never block, so a PR carrying
  unresolved findings reads `CLEAN` by construction. Full write-up, with the incident that
  produced this rule: `dotfiles/docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md`.

## Rate limits — per developer, not per repository

Limits are **per developer on a rolling hour**, so every repo and every parallel agent session
draws from one shared pool: a quiet repo can hit the ceiling it never spent. Per
[docs.coderabbit.ai/faq](https://docs.coderabbit.ai/faq) (fetched 2026-08-24): **Trial 3/hr, Pro
5/hr, Pro+ 10/hr**, with fair-usage spacing above the 95th percentile of recent usage and an
optional usage-based add-on. **This account is on the free plan as of 2026-09-24 — 1 included
review per hour** (David, 2026-09-24; CodeRabbit's review footer on dotfiles #186 the same day:
"Your plan provides up to 1 included review per hour"). It was Pro+ at 10/hr before that (footer
on dotfiles #171, 2026-08-24). **On the free plan a repo with fewer than 10 GitHub stars gets no
automatic review** (David, 2026-09-24) — every round, including a PR's first, must be requested
with `@coderabbitai review` (or the review checkbox in CodeRabbit's summary comment). Neither #186
nor #187 got an automatic first review; both were triggered by David ticking that checkbox. So after
opening a PR here, request the review; don't wait for one that will never start. **To tell who
triggered a review, check the summary comment's edit history** (GraphQL `userContentEdits`
→ `editor`): a checkbox trigger is an edit, not a comment, so it never shows in the comment list,
and a review that follows it looks automatic when it wasn't.
One review an hour covers every repo and agent together, so the
first review of a PR can use up the hour and its fix round then waits — plan PRs around that
rather than splitting work finely. A request sent while throttled only returns `Review rate
limited`; CodeRabbit's "Review limit reached" comment on the PR states when the next review is
available ("Next included review available in N minutes"). **That comment is edited in place** on
every throttled request, so count N from its `updated_at`, never its `created_at` — on #186 the
created-at reading put availability 15 minutes early and the retry was throttled again
(`gh api repos/<owner>/<repo>/issues/<N>/comments` shows both timestamps).
It is also CodeRabbit's **single summary comment**, rewritten through every state (skip notice →
limit reached → "Currently processing new changes" → the walkthrough), so an edit alone is not a
new throttle — read the body. On #188 (2026-09-24) a watcher keyed on `updated_at` alone reported
"throttled again" at the very moment the requested review started.
Treat capacity as a budget: `@coderabbitai rate limit` reports real remaining capacity
**without consuming a review**,
and the review footer prints what is left after each run.

**A throttled CodeRabbit is unavailable, not clean.** A throttled PR shows a *passing* check
reading `Review rate limited` and no review runs — passing by design so it never blocks merging,
which makes it easy to misread as approval. Merging anyway is allowed only when every other gate
is green **and** the PR body records that CodeRabbit was throttled rather than silent. For
anything beyond docs and config, wait for capacity.

## `.coderabbit.yaml` — every repo under review should have one

Set `reviews.auto_review.auto_incremental_review: false`. By default **every push re-reviews**,
spending the shared per-developer allowance on intermediate commits; with it false, each later
round is requested deliberately with an `@coderabbitai review` comment. This matches the
fix → push → request → re-review loop above. On a paid plan the first *eligible* review is still
automatic (`ignore_title_keywords` such as WIP / DO NOT MERGE, and drafts, are excluded). **On the
current free plan a repo under 10 stars gets no automatic review at all, the first included** (see
"Rate limits" above), so request every round.
Repos carrying this config: `skills`, `dotfiles`. Repos still on push-triggered re-review:
`borealis`.

The config is read from the **PR head branch, not the base** — verified on dotfiles #171, the PR
that added the file: its own later push was skipped rather than auto-reviewed. So a PR introducing
`.coderabbit.yaml` governs itself immediately, and a suppressed round shows up as a *passing*
check reading `Review skipped: incremental reviews are disabled` — another clean-looking check
that means no review ran.

**Naming a ticket id in a PR body can auto-close that issue on merge** — see the Linear rules in the global CLAUDE.md.

## After the merge: delete the branch

A merged PR's branch is deleted locally and on origin as part of the merge, without asking
(global rule, VIL-340). The standing approval covers only the PR's own head branch, and
only while it holds nothing the merge didn't. Run this function. Every check runs before
anything changes, any failure returns before the next step, and each delete is conditional
on the OID it checked. The branch name comes from the PR, never typed by hand.

```bash
source <dotfiles clone>/bin/lib/cleanup-merged-branch.sh   # ~/Projects/Personal/dotfiles on the desk Macs
cleanup_merged_branch <pr> <default branch>
```

Run it from any worktree of the repo, in bash or zsh. Right after a merge the main checkout
may not be pulled yet, so from a worktree that has a newer copy, source that one. The function lives only in
`bin/lib/cleanup-merged-branch.sh`; `wt done` (see `parallel-sessions.md`) sources the same file.

- **Stale local copy.** After `gh pr update-branch --rebase`, or any rewrite on GitHub, the
  local branch holds the pre-rebase commits. Those aren't the merged head, but they hold no
  new work. `git cherry <merged head> <local tip>` marks each local commit `-` when an
  equivalent patch is in the merged head and `+` when it isn't. One `+` keeps the branch.
  `git cherry` skips merge commits, and a merge can carry its own conflict resolution, so
  any merge commit missing from the merged head keeps the branch too.
- **Worktrees.** Every worktree on the branch must be clean before anything changes. A
  linked worktree is removed, and `git worktree remove` deletes ignored files (`.env`, build
  output), so for linked worktrees `--ignored` output counts as dirty too. The primary
  worktree can't be removed; it switches to the default branch, so before origin changes the
  function checks that the default branch exists and isn't checked out in another worktree.
  It also refuses a linked worktree that is locked.
- **Worktrees with submodules are detached, not removed (VIL-414).** `git worktree remove`
  refuses a linked worktree with initialized submodules (its own `modules` git dir; an empty
  `.gitmodules` doesn't count), and every Orca worktree has one (dotbot). So the function
  detaches it with `git switch --detach` at its own HEAD, which changes no files, after origin
  accepted the delete. It prints `<path> is detached at <sha>` and how to remove it: Force
  delete in Orca, or, for a worktree that isn't Orca's, `git worktree remove --force <path>`
  (a single `--force` removes one with submodules). Detaching deletes nothing, so only changes
  and untracked files block it, not ignored ones; those are still in the worktree, so check it
  before removing it (CLAUDE.md, "Removing an Orca worktree takes Force delete"). It works from inside that worktree,
  so a session that merged its own PR there cleans up before the Force delete closes it.
  `wt done` refuses such a worktree itself, before calling the function, because it expects
  the worktree to be gone afterwards.
- **Rollback.** A worktree step can still fail for reasons nothing can predict, such as
  permissions. So after origin is deleted, a failed worktree step, or a failed local delete
  (the branch moved mid-run), pushes origin's branch back at the merged head, and puts
  each worktree it detached back on the branch with `git symbolic-ref`, when the branch still
  points at that worktree's HEAD. If the branch moved, the worktree stays detached and the
  function prints `REATTACH FAILED`. If the origin push fails, it prints `RESTORE FAILED` with
  the exact `git push` that restores it, shell-quoted with `printf %q`. The local branch still
  holds the commit either way. The closing `git fetch --prune` runs after both deletes and
  isn't rolled back; if it fails, only a stale `origin/<branch>` tracking ref is left.
  Worktrees are touched only after origin accepted the delete, and are re-checked right before.
- **Why `update-ref -d` and not `git branch -D`:** a squash or rebase merge leaves the branch
  unmerged in git's eyes, so `-d` refuses and `-D` deletes whatever the tip is by then.
  `update-ref -d <ref> <old>` refuses unless the tip is still `<old>`. It also deletes a
  checked-out branch without complaint, which is why worktrees are cleared first.
- **zsh gotcha when editing this:** `$var:r`, `:h`, `:t` and `:e` are zsh modifiers, even
  inside double quotes, so `"$oid:refs/heads/x"` silently becomes something else. Brace the
  variable (`"${oid}:refs/…"`). `"refs/heads/$b:$oid"` is safe because `:$` isn't a
  modifier. The rollback push hit exactly this in testing. To check, run this from the repo
  root. It should print nothing:
  `grep -nE '\$[A-Za-z_0-9]+:[A-Za-z]' bin/lib/cleanup-merged-branch.sh`
- **Tested 2026-10-10** in a scratch repo with `gh` stubbed, under bash and zsh: 20
  scenarios. Both copies are deleted:
  - on the happy path;
  - when origin already auto-deleted the branch;
  - for a stale copy after a rebase;
  - after removing a clean linked worktree;
  - after switching the primary worktree off the branch;
  - with an empty `.gitmodules` and no initialized submodules.

  Everything is kept when:
  - the PR isn't merged;
  - the head is in a fork;
  - the local branch has a new commit, with or without a stale copy alongside;
  - a stale copy also carries a merge commit with its own change;
  - the PR branch is in the primary worktree while the default branch is checked out in another;
  - origin moved, whether or not a worktree exists (the worktree survives too);
  - a linked worktree has a modified, untracked or ignored file, or is locked (for one with
    submodules, only a modified or untracked file keeps it);
  - removing the worktree fails after origin was deleted (origin is pushed back);
  - the local branch moves between the checks and the local delete (origin is pushed back).
- **Retested 2026-10-21 (VIL-414)**, bash and zsh, 41 checks in 15 scenarios. A clean worktree
  with an initialized submodule is detached at its own HEAD and both copies are deleted: run
  from the main checkout, from inside the worktree, with a stale copy (files unchanged), and
  with only an ignored file. It is kept, still on the branch, with a tracked change, a new
  commit, or a lock. A failed local delete after the detach restores origin and re-attaches
  the worktree; if the branch moved, the worktree stays detached and `REATTACH FAILED` is
  printed. `wt done` refuses a submodule worktree and holds no files. The unchanged function
  from master fails 19 of the 41 checks. Rerun them with `ci/cleanup-merged-branch-checks.sh`
  after changing the function or `wt done` (local only, not in CI).
- **Local merge, no remote, no PR:** there is no `MERGED` state or origin tip to check.
  Confirm `git merge-base --is-ancestor "$b" "$base"`, then `git branch -d "$b"`, which
  refuses an unmerged branch on its own. Local branch only.
