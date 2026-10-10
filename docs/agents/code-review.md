# Code review and merging

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

Repos with their own review rules (dotfiles uses review-stack since 2026-09-24) override this.

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
  | `Review rate limited` | pass | **no** — throttled |
  | `Review failed — the head commit changed during the review` | — | **no** — a push aborted it |
  | `Review in progress` / `pending` | pending | unfinished |

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
# Delete a merged PR's branch locally and on origin. Usage: cleanup_merged_branch <pr> <base>
# Fails closed: every check runs before anything changes (including that each worktree step
# can succeed), every failure returns 1, and the step that can delete files (removing a
# worktree) runs only after origin accepted the delete.
cleanup_merged_branch() {
  local N=$1 base=$2 b oid cross tip cherry merges wl main wts w s rc
  read -r b oid cross < <(gh pr view "$N" --json state,headRefName,headRefOid,isCrossRepository \
    -q 'select(.state=="MERGED") | "\(.headRefName) \(.headRefOid) \(.isCrossRepository)"')
  [ -n "$oid" ] || { echo "PR $N is not merged (or gh failed): stop"; return 1; }
  [ "$cross" = false ] || { echo "PR $N's head is in a fork: no branch of ours to delete"; return 1; }
  # Local tip: absent, the merged head, or a stale copy of it (the PR was rebased or updated
  # on GitHub). A stale copy has no commit that isn't patch-equivalent to one in the merged
  # head (`git cherry` marks those `-`). Any `+` commit is new work: keep the branch.
  tip=$(git rev-parse -q --verify "refs/heads/$b")
  if [ -n "$tip" ] && [ "$tip" != "$oid" ]; then
    git cat-file -e "$oid^{commit}" 2>/dev/null || git fetch -q origin "refs/pull/$N/head" \
      || { echo "can't fetch PR $N's merged head: stop"; return 1; }
    cherry=$(git cherry "$oid" "$tip") || { echo "git cherry failed: stop"; return 1; }
    case $cherry in *+*) echo "$b has commits that aren't in PR $N: keeping it"; return 1 ;; esac
    # git cherry skips merge commits, and one can carry its own conflict resolution.
    merges=$(git rev-list --merges "$oid..$tip") || return 1
    [ -z "$merges" ] || { echo "$b has a merge commit that isn't in PR $N: keeping it"; return 1; }
  fi
  # Worktrees on $b: all clean before anything changes. A linked one will be removed, which
  # deletes ignored files too (.env, build output), so for those ignored files count as dirty.
  wl=$(git worktree list --porcelain) || { echo "git worktree list failed: stop"; return 1; }
  main=$(printf '%s\n' "$wl" | awk '/^worktree /{print substr($0,10); exit}')
  wts=$(printf '%s\n' "$wl" | awk -v r="branch refs/heads/$b" '/^worktree /{w=substr($0,10)} $0==r{print w}')
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then s=$(git -C "$w" status --porcelain) || return 1
    else
      s=$(git -C "$w" status --porcelain --ignored) || return 1
      # `git worktree remove` refuses a locked worktree and one with submodules.
      printf '%s\n' "$wl" | awk -v t="$w" '/^worktree /{c=(substr($0,10)==t)} c && /^locked/{f=1} END{exit !f}' \
        && { echo "$w is locked: keeping $b"; return 1; }
      [ ! -e "$w/.gitmodules" ] || { echo "$w has submodules: keeping $b"; return 1; }
    fi
    [ -z "$s" ] || { echo "$w has changes, untracked or ignored files: keeping $b"; return 1; }
  done < <(printf '%s\n' "$wts")
  # The primary worktree will switch to $base: that has to be possible before origin changes.
  if printf '%s\n' "$wts" | grep -qxF -- "$main"; then
    printf '%s\n' "$wl" | awk -v m="$main" -v r="branch refs/heads/$base" '/^worktree /{w=substr($0,10)} $0==r && w!=m{f=1} END{exit !f}' \
      && { echo "$base is checked out in another worktree, so $main can't leave $b: stop"; return 1; }
    git rev-parse -q --verify "refs/heads/$base" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null \
      || { echo "no $base branch to switch $main to: stop"; return 1; }
  fi
  # Origin first: GitHub's auto-delete may already have removed it (exit 2). Delete only
  # while it still points at the merged head; any other ls-remote exit is a failed lookup.
  git ls-remote --exit-code origin "refs/heads/$b" >/dev/null; rc=$?
  case $rc in
    0) git push --force-with-lease="refs/heads/$b:$oid" origin --delete "$b" \
         || { echo "origin refused the delete (moved since the merge?): keeping $b"; return 1; } ;;
    2) echo "origin already deleted $b" ;;
    *) echo "ls-remote failed ($rc): stop"; return 1 ;;
  esac
  # Worktrees: re-check, then remove a linked one, or switch the primary (git can't remove it).
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then
      s=$(git -C "$w" status --porcelain) || return 1
      [ -z "$s" ] || { echo "$w changed mid-run: origin is deleted, local $b kept"; return 1; }
      git -C "$w" switch "$base" || return 1
    else
      s=$(git -C "$w" status --porcelain --ignored) || return 1
      [ -z "$s" ] || { echo "$w changed mid-run: origin is deleted, local $b kept"; return 1; }
      git worktree remove "$w" || return 1
    fi
  done < <(printf '%s\n' "$wts")
  # Local: refuses unless the tip is still the one checked above (branch -D deletes whatever).
  [ -z "$tip" ] || git update-ref -d "refs/heads/$b" "$tip" || return 1
  git fetch --prune
}
```

Call it as `cleanup_merged_branch <pr> <default branch>` from any worktree of the repo. It
works in bash and zsh.

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
  It also refuses a linked worktree that is locked or has submodules, both of which
  `git worktree remove` refuses, so no worktree step can fail after origin is deleted.
  Worktrees are touched only after origin accepted the delete, and are re-checked right before.
- **Why `update-ref -d` and not `git branch -D`:** a squash or rebase merge leaves the branch
  unmerged in git's eyes, so `-d` refuses and `-D` deletes whatever the tip is by then.
  `update-ref -d <ref> <old>` refuses unless the tip is still `<old>`. It also deletes a
  checked-out branch without complaint, which is why worktrees are cleared first.
- **zsh gotcha when editing this:** `$var:r`, `:h`, `:t` and `:e` are zsh modifiers, so
  `$new:refs/heads/x` silently becomes something else. Brace the variable (`${new}:…`).
  `"refs/heads/$b:$oid"` is safe because `:$` isn't a modifier.
- **Tested 2026-10-10** in a scratch repo with `gh` stubbed, under bash and zsh: 17
  scenarios. Both copies are deleted:
  - on the happy path;
  - when origin already auto-deleted the branch;
  - for a stale copy after a rebase;
  - after removing a clean linked worktree;
  - after switching the primary worktree off the branch.

  Everything is kept when:
  - the PR isn't merged;
  - the head is in a fork;
  - the local branch has a new commit, with or without a stale copy alongside;
  - a stale copy also carries a merge commit with its own change;
  - the PR branch is in the primary worktree while the default branch is checked out in another;
  - origin moved, whether or not a worktree exists (the worktree survives too);
  - a linked worktree has a modified, untracked or ignored file, is locked, or has submodules.
- **Local merge, no remote, no PR:** there is no `MERGED` state or origin tip to check.
  Confirm `git merge-base --is-ancestor "$b" "$base"`, then `git branch -d "$b"`, which
  refuses an unmerged branch on its own. Local branch only.
