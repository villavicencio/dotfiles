# Code review and merging

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

**MergeWren (review-stack) is the default reviewer since 2026-11-03.** It reviews bryancola.com, browse-gateway, dissolution, dotfiles (since 2026-09-24), hal-bench, hal-pilot, mergewren and skills (since 2026-11-03); the adoption records are in mergewren `docs/adoption/`. atlas-tools is adopted review-only, with no remote, so it never has PRs. How to wait for a verdict is under "Merging on a MergeWren review" below. A new repo is onboarded before its first PR, with a ticket in the MergeWren Linear project modeled on VIL-537 (adoption record, OCR rule, posting allowlist, pin test). A repo whose `CLAUDE.md`/`AGENTS.md` names its own reviewer as the gate follows that. The CodeRabbit sections below apply only to a repo not yet onboarded. In MergeWren repos, don't request or wait for CodeRabbit (`@coderabbitai review` spends the per-developer quota for nothing); a CodeRabbit check that appears there on its own is informational, not a gate.

**On a repo not yet onboarded, PR review runs through CodeRabbit** (reconciled across dotfiles /
borealis / skills, 2026-08-24). This file is the single source of truth, and per-repo
`AGENTS.md` files should point here rather than restate it.

**There is no stand-in for MergeWren** (since 2026-11-17, VIL-799):

- A large or risky diff gets MergeWren alone.
- If MergeWren is down or throttled and the review can't wait, wait or bring it to David.
- For review of something that isn't a PR, in a repo with a remote, open a PR for it.
- In a repo with no remote, a change that needs review is brought to David before the local merge.
- A private repo not yet on MergeWren, for a change beyond docs and config: onboard the repo
  to MergeWren first (see the top of this file).

**Reach for CodeRabbit** for review of a PR diff in a repo not yet onboarded.

**Don't hand-roll a review**: no `codex exec review`, no Claude↔Codex loops, no "fan out
reviewers" or "spin up a skeptic panel," including under `/effort ultracode` or workflow
orchestration. Custom workflows may supply research or critique *lenses* upstream; the review
of the diff itself routes through the repo's reviewer.

## Polling `gh` (any reviewer, any repo)

- **`gh`'s `--jq`/`-q` takes one filter and nothing else**: no `--arg`, no `--argjson`, on
  `gh api`, `gh pr view` and the rest. Splice a value in with the shell (a double-quoted
  filter, as in the CodeRabbit check-run recipe below), or pipe plain JSON into real `jq --arg`. Passing
  `--arg` fails with `accepts at most 1 arg(s), received 4`.
- **A wait loop must tell an error from "not yet".** Check `gh`'s exit status on every
  pass; on failure, print the error and stop. On dotfiles#259 (2026-11-02) a MergeWren wait
  loop passed `--arg` to `--jq`. Every pass failed, the empty output read as "still pending",
  and it spun silently for about 20 minutes until David asked. Shape:

  ```bash
  for i in $(seq 1 20); do
    r=$(gh pr view <N> --json comments --jq '<filter>') || { echo "gh failed (error above)" >&2; exit 1; }
    [ "$r" != PENDING ] && { printf '%s\n' "$r"; exit 0; }
    sleep 60
  done; echo "TIMEOUT"
  ```

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
- **On the Free plan a private repo gets a summary, never a review.** CodeRabbit's plans page
  ([docs.coderabbit.ai/management/plans](https://docs.coderabbit.ai/management/plans), fetched
  2026-11-15 22:28 UTC) says of Free: "PR summarization only; code reviews are available through
  the VS Code extension and CLI." Public repos are on the OSS tier, which gets real reviews
  ("Open-source projects receive Team features with no paid subscription required"; skills#55,
  2026-10-29, got line-by-line findings). In a private repo the run posts a walkthrough and a note,
  "Summarized by CodeRabbit Free … For a comprehensive line-by-line review, please upgrade your
  subscription to CodeRabbit Essentials", and no review or thread, yet its check reads exactly
  like a review's: `success`, `Finished`, `Result: Success - Review completed`. A summary-only
  run is **not a review**, the same as rate limited or skipped, and it still spends the hourly
  allowance (bryancola-backups PR 2, 2026-11-15: "This review used your included allowance …
  0 remain after this review"). Of 155 private-repo PRs with a CodeRabbit comment, opened
  2026-10-21 to 2026-11-15, none got a CodeRabbit review or inline comment, and every one carried
  that note. So in a private repo not yet on MergeWren there is no PR reviewer: docs and config
  may merge with "no line-by-line review" recorded in the PR body; for anything else, onboard
  the repo to MergeWren first. A private repo also gets a run
  automatically when the PR opens, with no request (mergewren#135, bryancola.com#50), and that run
  draws on the same hourly allowance. Check for the note:

  ```bash
  gh api --paginate repos/<owner>/<repo>/issues/<N>/comments \
    -q '.[]|select(.user.login|test("coderabbit"))|select(.body|test("Summarized by CodeRabbit Free"))|.html_url'
  ```

  Any output means no line-by-line review ran on that PR.
- **Read what the check says, not its state** — this is the one that has bitten repeatedly.
  **"Not `pending`" is not a completion test**: several results sit on a check that isn't
  failing, and only one of them can mean a review ran. Since about 2026-10-24 (first seen on
  mergewren#89) CodeRabbit reports a **check run**, not a commit status, and
  `gh pr checks` lists it with an **empty description** and a state of `SUCCESS`, `NEUTRAL`,
  `SKIPPED` or `CANCELLED`. Read the latest CodeRabbit check run's title and result line (asking
  for it by name, so a head with many other checks can't push it off the first page):

  ```bash
  gh api --paginate "repos/<owner>/<repo>/commits/<head-sha>/check-runs?check_name=CodeRabbit" \
    -q '.check_runs[] | "\(.conclusion)\t\(.output.title)\t\(.output.summary|split("\n")[0])"'
  ```

  | Conclusion | Title | Result line | Review ran? |
  |---|---|---|---|
  | `success` | `Finished` | `Result: Success - Review completed` | **yes on a public repo; no on a private repo on Free** (summary only, above) |
  | `success` | `Finished` | `Result: Success - Review completed with incomplete coverage` | **no** on Free in a private repo (mergewren#122); not seen on a public repo |
  | `neutral` | `Review rate limited` | `Result: Rate limited - Review rate limited` | **no** — throttled |
  | `skipped` | `Review skipped` or `Review skipped: manual review required for this OSS repository` | `Result: Skipped - …` (same text) | **no** — a public repo under 10 stars; the comment says "This repository does not receive automatic reviews because it has fewer than 10 stars". Request one |
  | `skipped` | `Review skipped: draft pull request` | `Result: Skipped - Review skipped: draft pull request` | **no** |
  | `cancelled` | `Review cancelled` | `Result: Cancelled - Pull request is closed` | **no** |

  Seen on 142 PRs in David's repos, 2026-10-24 to 2026-11-15. A failed or in-progress check run
  wasn't observed in that sample. Before about 2026-10-24 it was a commit status, whose description
  `gh pr checks` showed; summary-only runs there also read `Review completed` (mergewren#69,
  2026-10-22):

  | Description | State | Review ran? |
  |---|---|---|
  | `Review completed` | pass | **yes**, unless the PR carries the Free summary note |
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
- **After requesting a review, read only check runs started after the request.** A watcher that
  stops at the first result it finds can read one left over from when the PR opened: on skills#43
  and browse-gateway#149 (2026-10-06) it reported `manual review required for this OSS
  repository` while CodeRabbit was already reviewing, and the real review then found 5 issues.
  **CodeRabbit's reply decides, not the check run.** It answers every request with a PR comment
  within about 20 s: `Action performed` (the review runs, and the comment is edited to `Review
  finished` when it's done) or `Action not completed` with the reason, `Review rate limited.` or
  `Already reviewed the last commit.` (35 such replies on the PRs surveyed, 2026-09 to 11). A
  refused request may start **no check run at all**: on bryancola-backups PR 2 (2026-11-15) the
  only check run is the one from opening the PR, and the request got `Already reviewed the last
  commit`. A poll that waits only for a check run started after the request then waits forever.
  **The request's own run starts after that reply.** On every request in the survey that had a
  check run (bryancola-backups PR 1, hal-pilot#2, skills#55 and #56, 2026-10-29 to 11-03), the
  run answering it started 5 to 14 s after CodeRabbit's reply (9 requests). Runs that started
  between the request and the reply were someone else's: the `Review skipped` from opening the
  PR (skills#55, 4 s after the request; skills#56, in the same second) or the run a push starts
  on a private repo (hal-pilot#2, 8 s after it). So the poll
  reads only runs that started at or after the reply.

  Every 30 s this reads the first CodeRabbit reply since the request, and once there is one,
  the newest check run (all pages) that started at or after it. It always returns, by elapsed
  time (`$SECONDS`), not by counting passes. Only status 0 can mean a review: 1 `gh` failed, 2
  the request was refused, 3 no reply 5 minutes after the call, 4 no result 20 minutes after
  it, 5 the request's run failed, was cancelled or timed out. Record the time just before the
  request, and poll only if the request posted:

  ```bash
  cr_wait() {  # cr_wait <owner/repo> <pr> <head-sha> <request time>: prints one final line
    local R=$1 N=$2 sha=$3 t=$4 start=$SECONDS tab=$'\t' reply state run
    while :; do
      reply=$(gh api --paginate "repos/$R/issues/$N/comments?since=$t" -q ".[]
        | select(.user.login|test(\"coderabbit\")) | select(.created_at >= \"$t\")
        | select(.body|test(\"Action (performed|not completed)\"))
        | \"\(.created_at)\t\" + (.body | if test(\"Action not completed\") then \"REFUSED: \"
            + (if test(\"rate limited\") then \"rate limited\" elif test(\"Already reviewed\") then \"already reviewed\" else \"read the reply\" end)
          elif test(\"Review finished\") then \"FINISHED\" else \"ACCEPTED\" end)") \
        || { echo "gh failed (error above): stop"; return 1; }
      reply=${reply%%$'\n'*}; state=${reply#*"$tab"}; run=
      case $state in REFUSED*) echo "$state"; return 2 ;; esac
      if [ -n "$reply" ]; then
        run=$(gh api --paginate "repos/$R/commits/$sha/check-runs?check_name=CodeRabbit&filter=all&per_page=100" -q ".check_runs[]
          | select(.started_at >= \"${reply%%"$tab"*}\") | \"\(.started_at)\t\(.status)\t\(.conclusion)\t\(.output.title)\"") \
          || { echo "gh failed (error above): stop"; return 1; }
        run=$(printf '%s\n' "$run" | sort | tail -1)
        case $run in
          *"${tab}completed${tab}success${tab}"*)
            [ "$state" != FINISHED ] || { echo "FINISHED$tab$run"; return 0; } ;;
          *"${tab}completed${tab}failure${tab}"*|*"${tab}completed${tab}cancelled${tab}"*|*"${tab}completed${tab}timed_out${tab}"*)
            echo "RUN ENDED$tab$run"; return 5 ;;
        esac
      elif [ $((SECONDS - start)) -ge 300 ]; then echo "NO REPLY after 5 min: no review"; return 3
      fi
      [ $((SECONDS - start)) -lt 1200 ] || { echo "TIMED OUT after 20 min: ${state:-no reply}, run ${run:-none}"; return 4; }
      sleep 30
    done
  }
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gh pr comment <N> --body '@coderabbitai review' && cr_wait <owner>/<repo> <N> <head-sha> "$t"
  ```

  - 0, `FINISHED`: the request's `success` run finished; read its result line with the table
    above (on a private repo on Free it is a summary, not a review).
  - 2, `REFUSED: …`: this request produces no review. Rate limited: wait for the window (see
    "Rate limits"). Already reviewed: `@coderabbitai full review` if the head needs one.
  - 5, `RUN ENDED`: the request's run failed (a push mid-review, say) or was cancelled: no
    review.
  - 3 or 4, `NO REPLY` or `TIMED OUT`: report no review; don't wait on.

  A `skipped` or `neutral` run started after the reply doesn't end the wait while the reply
  says the request was accepted; one that ends it without CodeRabbit editing the reply shows up
  as `TIMED OUT` with the run named.

  `gh`'s `-q` has no `--arg` (see "Polling `gh`" above), so the time is spliced into
  double-quoted filters; a `gh` failure stops the poll ("A wait loop must tell an error from
  'not yet'" above). `check_name=CodeRabbit` is the check run's exact name in every repo checked
  (dotfiles, skills, mergewren, bryancola.com, hal-pilot), and `filter=all` keeps earlier runs
  on the head, which the default (`latest`) hides. Each `gh` runs on its own, so its exit status
  isn't lost in a pipe; `sort | tail -1` then picks the newest run across all pages, and
  `${reply%%$'\n'*}` keeps the first reply. `>=` counts the reply's own second.

  Checked on 2026-11-15, the function as written here, in bash and zsh, against past requests
  (no review was requested): skills#55's accepted requests on `04a5cfd` and `5231a11`
  (`FINISHED`, `success Finished`; on `04a5cfd` the PR-open `Review skipped` 4 s after the
  request is ignored) and its rate-limited one on `f3ef8d8` (`REFUSED: rate limited`);
  bryancola-backups PR 2 at its real request time and with the time moved to 22:10:30, after
  the PR-open run and before the reply (`REFUSED: already reviewed` both times; in the second
  there is no run after the request, and the old filter printed `PENDING`); a request time with
  no reply (`NO REPLY after 5 min`, 3); and a repo that doesn't exist (`gh failed`, 1). With
  `gh` stubbed (fixture JSON through the function's own filters, with real `jq`) and `sleep`
  adding 30 to `$SECONDS`: an accepted review that never finishes
  (`TIMED OUT`, 4); the request's run cancelled (`RUN ENDED`, 5); a run that failed before the
  reply, as a PR-open run might (ignored; `TIMED OUT`, 4); and a `skipped` run while accepted
  (keeps waiting, then 4).
  An earlier replay that cut the reply and runs off at each moment also found `REFUSED: rate
  limited` for skills#55's other two throttled requests and a run whose start equals the request
  second (the old `>` printed `PENDING`). Not yet tried on a live request: the reply's wording
  between `Action performed` and `Review finished`. A replay can't show it, because the reply
  comment is read as it is now, after its last edit.

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
- **Outside-diff findings have no thread, so the check above can't see them.** When CodeRabbit
  flags a line the PR didn't change, the finding goes only into the review's text, under
  `Outside diff range comments (N)`. No thread is created, so the unresolved-threads check comes
  back empty and the PR reads `CLEAN` with a finding unanswered. Before merging, list every
  CodeRabbit review that has outside-diff findings, not only the latest (on skills#53 they were
  in an earlier round), with the count each one states:

  ```bash
  gh api --paginate repos/<o>/<r>/pulls/<N>/reviews -q '.[]|select(.user.login|test("coderabbit"))|select(.body|test("Outside diff range comments"))|"\(.id) \(.submitted_at) \(.body|capture("Outside diff range comments \\((?<n>[0-9]+)\\)").n) finding(s)"'
  ```

  Then read each listed review in full, since a section can hold several findings:
  `gh api repos/<o>/<r>/pulls/<N>/reviews/<id> -q .body`.

  Answer each one in a PR comment, and record a decline in the PR body too. On skills#49, #51 and
  #53 (2026-10-24) every outside-diff finding was real; one was declined. The reverse case also
  misleads: a clean re-review posts **no new review**, only a `success` check run whose result
  line reads `Review completed` on the head commit (a commit status before about 2026-10-24;
  read it as shown under "After requesting a review"). A latest review sitting on an
  older commit doesn't mean the round was skipped.
- **Triage every finding**: fix it on the branch, or decline it with the reason recorded both on
  the thread and in the PR body. A finding you disagree with is a standoff you document, not one
  you merge past silently.
- **A trivial diff may skip review**, but the skip and its reason must be stated when reporting
  the merge. The skip is fine; the silence isn't.
- **`mergeStateStatus: UNSTABLE` means a check failed, and the merge button still works.**
  This repo's checks aren't required, so GitHub lets the merge through. Before merging, list the checks
  (`gh pr checks <N> --json name,state -q '.[]|"\(.state) \(.name)"'`) and stop on any `FAILURE`:
  fix it, or name it in the merge report as a failure the PR didn't cause. dotfiles#251 merged
  on 2026-10-27 with `macos` red (Homebrew had disabled the `tldr` formula), unnoticed until
  after the merge.
- **`mergeStateStatus: CLEAN` does not mean reviewed.** It means nothing is *blocking* the
  button. There are at least three ways a PR reads clean with findings outstanding: the review
  was **throttled** (below), it was **skipped** because `auto_incremental_review: false` (below),
  or it **completed and found things** — `COMMENTED` reviews never block, so a PR carrying
  unresolved findings reads `CLEAN` by construction. Full write-up, with the incident that
  produced this rule: `dotfiles/docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md`.

## Merging on a MergeWren review

MergeWren (review-stack) reviews every new head of an open, non-draft PR on its own, a few
minutes after the push, and posts a PR comment for each review from David's account, starting
with `<!-- review-stack:head=<full sha> run=<id> -->`. A head usually gets one; an incremental
round gets two (below). There is no trigger comment and no quota. Wait for the verdict with the
shared function, never a hand-written poll. It returns a comment only if the head is unchanged
after reading it, so a push while it waits moves it on to the new head. Only exit 0 means a
verdict:

```bash
source <dotfiles clone>/bin/lib/mergewren-review.sh   # ~/Projects/Personal/dotfiles on the desk Macs
mergewren_review <pr> [owner/repo]   # 0 verdict + the comment; 1 GitHub error; 2 PENDING after 20 min;
                                     # 3 draft; 4 a review comment with no verdict line (printed: read it);
                                     # 5 a final `no verdict` (printed): the review didn't complete, not a pass
```

Why it reads comments this way (hal-pilot#4, 2026-11-02, where MergeWren flagged the old
one-line poll):

- **A draft gets no review at all.** hal-pilot#2 sat unreviewed for two days as a draft; the
  function says so (exit 3) instead of waiting out its timeout. `gh pr ready <N>` starts the
  review.
- **An incremental round posts a placeholder first:** `MergeWren: no verdict — incremental
  round; full confirmation of <sha> queued`, then the full review of the same head about a
  minute later. A poll that stops at the first comment for the head reads no verdict as done.
  The function checks only the `MergeWren:` verdict line, skips the placeholder and keeps
  waiting. It skips only a `no verdict` line that names a full confirmation as `queued`. Any
  other `no verdict` line is final, and nothing follows it: `review incomplete`, a secret scan
  that didn't finish, or an incremental round with no confirmation queued (eagle-hover-save#2,
  2026-11-17; before this the function waited out its 20 min on one and returned `PENDING`).
  The function prints that comment and returns 5. The head wasn't fully reviewed and it isn't a pass: read the comment,
  don't merge, tell David.
- **Only a comment from David's account whose body starts with the marker counts.** The old
  poll matched any comment that contained `review-stack:head=<sha>`, so a reply quoting it would
  pass as the review.
- **It pages through every comment** with `gh api --paginate` on the REST list, rather than
  trusting `gh pr view --json comments` to return them all.
- **A failed GitHub call is an error, not `PENDING`.** The old poll printed `PENDING` when `gh`
  failed, which looks like waiting.

**It reviews the diff against the repository's default branch, not the PR's base.** A stacked
PR (one based on another unmerged branch) gets its base branch's changes too, and no real
review. eagle-hover-save#2 changed 11 files against its base `feat/vil-748-upstream-baseline`,
but MergeWren listed 633 applied paths, 617 of them the base branch's files under `upstream/`,
marked many "not reviewed: over the per-run file limit", and posted `MergeWren: no verdict —
review incomplete` (2026-11-17). Don't stack PRs in a MergeWren repo: open each PR against the
default branch once its base has merged. A branch cut from the base still carries the base's
commits, and a squash merge never makes them ancestors of the default branch. So fetch the
default branch fresh (`git fetch origin +refs/heads/<default>:refs/remotes/origin/<default>`,
as `wt` does), then move only the branch's own commits onto `origin/<default>`. A merge commit
with recorded conflict resolutions needs those resolutions made again, not dropped. Then check
that `git diff --name-only origin/<default>...<branch>` lists only the branch's own files.

Merge only on a `mergeable` verdict (or one whose every finding is fixed or declined with
David) with the unresolved-threads check (above) empty. A `partial` or `failed` verdict, "The
review did not complete", or exit 4 (no verdict line) means the head wasn't fully reviewed:
don't merge, tell David. Each finding is also an inline thread;
resolve it once it's fixed or declined. MergeWren doesn't read thread replies, so a decline
goes in the PR body too. Repo-specific detail (dotfiles' stale-finding case on #239) stays in
that repo's docs.

## Rate limits — per developer, not per repository

Limits are **per developer on a rolling hour**, so every repo and every parallel agent session
draws from one shared pool: a quiet repo can hit the ceiling it never spent. Per
[docs.coderabbit.ai/faq](https://docs.coderabbit.ai/faq) (fetched 2026-08-24): **Trial 3/hr, Pro
5/hr, Pro+ 10/hr**, with fair-usage spacing above the 95th percentile of recent usage and an
optional usage-based add-on. **This account is on the free plan as of 2026-09-24 — 1 included
review per hour** (David, 2026-09-24; CodeRabbit's review footer on dotfiles #186 the same day:
"Your plan provides up to 1 included review per hour"). It was Pro+ at 10/hr before that (footer
on dotfiles #171, 2026-08-24). The plans page
([docs.coderabbit.ai/management/plans](https://docs.coderabbit.ai/management/plans), fetched
2026-11-15 22:28 UTC) still lists Free at 1 PR review per developer per hour, and a summary-only
run counts against it (see "On the Free plan a private repo gets a summary" above). **On the
free plan a public repo with fewer than 10 GitHub stars gets no automatic review** (David,
2026-09-24; the plans page: "For public repositories with less than 10 stars, CodeRabbit requires
reviews to be triggered manually") — every round, including a PR's first, must be requested
with `@coderabbitai review` (or the review checkbox in CodeRabbit's summary comment). A private
repo gets a run automatically when a PR opens, which on Free is summary only. Neither #186
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
reading `Review rate limited` (since about 2026-10-24, a `neutral` check run with that title) and
no review runs — passing by design so it never blocks merging,
which makes it easy to misread as approval. Merging anyway is allowed only when every other gate
is green **and** the PR body records that CodeRabbit was throttled rather than silent. For
anything beyond docs and config, wait for capacity. A summary-only run on a private repo gets the
same carve-out, recorded in the PR body as "no line-by-line review"; waiting for capacity doesn't
help there, so for anything beyond docs and config, onboard the repo to MergeWren first.

## `.coderabbit.yaml` — every repo under review should have one

Set `reviews.auto_review.auto_incremental_review: false`. By default **every push re-reviews**,
spending the shared per-developer allowance on intermediate commits; with it false, each later
round is requested deliberately with an `@coderabbitai review` comment. This matches the
fix → push → request → re-review loop above. On a paid plan the first *eligible* review is still
automatic (`ignore_title_keywords` such as WIP / DO NOT MERGE, and drafts, are excluded). **On the
current free plan a public repo under 10 stars gets no automatic review at all, the first included** (see
"Rate limits" above), so request every round.
Repos carrying this config: `skills`, `dotfiles`. Repos still on push-triggered re-review:
`borealis`.

The config is read from the **PR head branch, not the base** — verified on dotfiles #171, the PR
that added the file: its own later push was skipped rather than auto-reviewed. So a PR introducing
`.coderabbit.yaml` governs itself immediately, and a suppressed round shows up as a *passing*
check reading `Review skipped: incremental reviews are disabled` — another clean-looking check
that means no review ran.

**Naming a ticket id in a PR body can auto-close that issue on merge** — see the Linear rules in the global CLAUDE.md.

## Fix rounds

Any session, any repo. These came out of five review rounds on one PR. The rules about fix
rounds (the first three) are for a PR under its reviewer.

- **Keep a fix round to what the findings ask.** A large fix can push MergeWren from an
  incremental round (see "Merging on a MergeWren review") to a full re-review, which samples
  new findings. The more a round changes beyond the findings, the more it invites another round.
- **Triage each finding.** Fix what weakens what the PR protects. Decline the rest with a
  reason, recorded where this file says: on the thread and in the PR body.
- **Stop at two fix rounds.** Then bring David the list of what is still open, and don't start
  a third round on your own.
- **Strip two things from a PR's docs before it opens:** multi-line shell procedures, and
  absolute claims ("always", "never", "every") you haven't tested. Both draw findings.
- **A reviewer panel before review doesn't replace the review.** The ban on hand-rolled
  reviews at the top of this file stands: the review of the diff still goes through the repo's
  reviewer.
- **On a PR under review, an engineer (a hired agent) runs the reviewer wait in the
  foreground, not as a background shell.** If the wait ends without a verdict (pending, timed
  out, or the command is cut off), the engineer reports that to the manager and doesn't start
  it again on its own. A repo with no remote PR has no reviewer wait, so this rule doesn't
  apply there. The engineer stops any background shell it started before its final report. A
  background wait notifies the manager on every review round, and a shell that outlives the
  agent's last turn likely leaves a finished agent listed as waiting. If one is still listed
  after it reported and its PR merged, stop it.

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

Run it from any worktree of the repo, in bash or zsh, with one exception: **not from inside a
linked worktree on the PR's branch that has no initialized submodules** (a `wt` worktree, for
one). The function removes that worktree, which is the shell's own directory, and every git
call after that fails with "fatal: Unable to read current working directory": it then prints
"local <branch> moved mid-run: keeping it" and a `RESTORE FAILED` line with a `git push` to
recreate the origin branch, though nothing moved and the PR is merged (dotfiles PR 272,
2026-11-15). Don't run that push; `cd` to the main checkout and delete the local branch there,
conditional on its OID (`git update-ref -d refs/heads/<branch> <oid>`). `wt done` is safe: it
runs the function from the main checkout. An Orca worktree with initialized submodules is only
detached, not removed, so running from inside it works (`docs/reference/orca-worktrees.md`).
Right after a merge the main checkout may not be pulled yet, so source the copy in a worktree
that has a newer one (by its path; the shell can stay in the main checkout). The function lives
only in `bin/lib/cleanup-merged-branch.sh`; `wt done` (see `parallel-sessions.md`) sources the
same file.

- **Stale local copy.** After `gh pr update-branch --rebase`, or any rewrite on GitHub, the
  local branch holds the pre-rebase commits. Those aren't the merged head, but they hold no
  new work. `git cherry <merged head> <local tip>` marks each local commit `-` when an
  equivalent patch is in the merged head and `+` when it isn't. One `+` keeps the branch.
  `git cherry` skips merge commits, and a merge can carry its own conflict resolution, so
  any merge commit missing from the merged head keeps the branch too.
- **Worktrees.** Every worktree on the branch must be clean before anything changes. A
  linked worktree without initialized submodules is removed, and `git worktree remove` deletes
  ignored files (`.env`, build output), so for those `--ignored` output counts as dirty too
  (one with submodules is detached instead; next point). The primary
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
  before removing it (dotfiles `docs/reference/orca-worktrees.md`, "Removing an Orca worktree takes Force delete"). It works from inside that worktree,
  so a session that merged its own PR there cleans up before the Force delete closes it.
  `wt done` refuses such a worktree itself, before calling the function, because it expects
  the worktree to be gone afterwards.
- **Rollback.** A worktree step can still fail for reasons nothing can predict, such as
  permissions. So after origin is deleted, a failed worktree step, or a failed local delete
  (the branch moved mid-run), pushes origin's branch back at the merged head, and puts
  each worktree it detached back on the branch with `git symbolic-ref`, when the branch still
  points at that worktree's HEAD and no other worktree has checked it out. A detach counts
  when HEAD ended up detached, even if `git switch` failed (a failing post-checkout hook
  fails it after HEAD moved). If the branch moved or is checked out elsewhere, the worktree
  stays detached and the function prints `REATTACH FAILED`. If the origin push fails, it prints `RESTORE FAILED` with
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
- **Retested 2026-10-22 (VIL-414)**, bash and zsh, 53 checks in 18 scenarios. A clean worktree
  with an initialized submodule is detached at its own HEAD and both copies are deleted: run
  from the main checkout, from inside the worktree, with a stale copy (files unchanged), and
  with only an ignored file. It is kept, still on the branch, with a tracked change, a new
  commit, or a lock. A failed local delete after the detach restores origin and re-attaches
  the worktree; if the branch moved, the worktree stays detached and `REATTACH FAILED` is
  printed, as it is when another worktree checked the branch out meanwhile. A failed detach
  restores origin and leaves the worktree on the branch, putting it back when a failing
  post-checkout hook failed the switch after HEAD moved. `wt done`
  refuses a submodule worktree before the PR lookup and holds no files, but reports copies an earlier run left in `wt-held/` first. Master's function and
  `wt` failed 19 of the first 41 checks. Rerun them with `ci/cleanup-merged-branch-checks.sh`
  after changing the function or `wt done` (local only, not in CI).
- **Local merge, no remote, no PR:** there is no `MERGED` state or origin tip to check.
  Confirm `git merge-base --is-ancestor "$b" "$base"`, then `git branch -d "$b"`, which
  refuses an unmerged branch on its own. Local branch only.

## Leftover local branch: delete without asking

A local branch whose work is already on origin's default branch is deleted without asking
(global rule, 2026-11-19). The typical one is the branch Orca keeps when it removes a
worktree. In skills, Orca's worktree for a ticket sat on a branch named after the ticket, the
work went out on a `feat/` branch that was squash-merged, and after `orca worktree rm` the
Orca-named branch was left at a commit already on `origin/main`, with no upstream and no PR.
Run this function from any checkout of the repo, in bash or zsh. It returns 0 after deleting
the branch, with the command that undoes it; 1 when it keeps the branch, with
`keeping <branch>: <reason>` (`keeping: no branch named` when called without one); and 2 when it deleted the branch but couldn't remove its config
section, or couldn't check for one, with the `git config` command that removes it:

```bash
source <dotfiles clone>/bin/lib/delete-leftover-branch.sh   # ~/Projects/Personal/dotfiles on the desk Macs
delete_leftover_branch <branch>
```

It fails closed: before the delete, every check has to succeed, and a check whose command
fails, or answers with nothing, keeps the branch. After the delete, only the config step can
fail, and that returns 2. A hand-typed chain of these commands doesn't: `! git worktree list
| grep` passes when `git worktree list` fails, and an empty reflog or a failed `git log -g`
makes `git rev-list --not <ref>` print nothing, which reads as "nothing missing" (PR 296).

- **Origin's default branch is asked of origin.** `git ls-remote --symref origin HEAD` gives
  its name and its tip. A cached `origin/HEAD` can name an old default branch, and a narrow
  fetch refspec can leave `origin/<default>` missing or stale, so neither is trusted. If that
  commit isn't here, it fetches the branch with an explicit refspec.
- **Tip and reflog.** The branch's tip, and both commits of every line in its reflog file
  (each entry's old and new side, skipping the all-zero side from before the branch existed),
  have to be on that commit. Deleting a branch deletes its reflog, and once its worktree is
  removed that worktree's HEAD reflog is gone too, so a commit reset off the branch would be
  lost. The file is read raw because `git log -g` and `<branch>@{n}` give only each entry's
  new side, so the old side of the oldest entry is missed (a commit the branch held before
  logging began, or before older entries expired), and `git log -g` silently skips an entry
  whose commit is missing. A missing, empty or unreadable reflog, a line that isn't two commit
  ids, refs not stored as files (reftable), or a failed `git rev-parse --show-ref-format`
  keeps the branch. git before 2.45 has no `--show-ref-format`, so there the function always
  keeps the branch (accepted, 2026-11-20). A squash merge's original
  commits aren't on the default branch, so a branch that once held them is kept; ask.
- **Worktrees, checked last.** It refuses a branch any worktree has checked out (the current
  checkout included), and one that a rebase or bisect in any worktree started from, which
  `git worktree list` shows as detached. It reads git's rebase and bisect state files for
  that; a git dir or state file it can't read counts as busy. These checks run just before
  the delete, not during it (the known limit below).
- **Why not `git branch -d`.** `-d` judges "merged" against the current checkout (or the
  branch's upstream), so from an unrelated checkout it refuses a branch that qualifies, and it
  isn't conditional on the tip that was checked. The function deletes with
  `git update-ref -d refs/heads/<branch> <checked tip>`, which refuses if the branch moved,
  then removes the branch's own config section (`branch.<branch>`, not `branch.<branch>.x`) as
  `-d` does. Never `-D`.
- **Known limit: a race with another process.** The worktree checks run just before the
  delete, but nothing stops another process checking the branch out, or starting a rebase or
  bisect from it, in between; that doesn't move the tip, so the delete goes ahead. git has no
  lock that spans both: `git branch -d` checks and then deletes the same way. The window is a
  few git commands long. If it happens, the worktree is left on a branch that no longer exists;
  `git branch <branch> <tip>` (printed by the function) puts it back.
- **Not covered:** the branch's copy on origin, a branch with commits the default branch lacks
  (a merged PR's head goes through "After the merge" above), stashes, tags, anything else.
- **Tests:** `ci/delete-leftover-branch-checks.sh` (local only, not in CI), 61 checks under
  each of bash and zsh (60 as root, where one is skipped), last run 2026-11-20. A leftover branch is deleted, also from a
  checkout that doesn't contain it, and when `origin/HEAD` is missing, the fetch refspec is
  narrow and `origin/main` is stale. It is kept when it is the default branch or not a valid
  or existing name; is checked out; is being rebased (merge or apply state) or bisected, in a
  linked worktree or the main checkout, or a worktree's rebase state or git dir can't be read;
  is only on a stale `origin/main` or a stale `origin/HEAD`'s branch; or its reflog holds a
  commit reset off it, holds one only on the old side of its first entry, names a missing
  commit, is missing, empty, unreadable or has a line it can't parse; or the refs are
  reftable, the ref-format check fails, or git is older than 2.45 (simulated). It is also
  kept when origin can't be reached, names no default branch or no commit, or the fetch
  fails; when a git command it checks with fails or `git worktree list` answers with nothing
  (injected one at a time for most of them; the script lists which), or `grep` fails; and when the branch moves between the checks and the delete. A failed config removal
  or config check after the delete returns 2 with the branch gone and says so; a
  `branch.<branch>.x` section is left alone. Unreadable files are made with an injected
  failing `cat`, not `chmod 000`, which root can still read; the one exception, a git dir that
  can't be searched, uses `chmod 000` and prints `SKIP` where that has no effect.
