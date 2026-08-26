---
title: "A passing PR check is not a review — read the description string and enumerate unresolved threads"
date: 2026-08-25
category: best-practices
module: code-review-workflow
problem_type: workflow_issue
component: tooling
severity: High
applies_when:
  - "About to report a PR as green, clean, or mergeable on the strength of `gh pr checks` showing `pass` or `mergeStateStatus: CLEAN`"
  - "Working in a repo whose `.coderabbit.yaml` sets `auto_incremental_review: false` — every push after the first review produces a passing check on which no review ran"
  - "Reporting on several PRs in one pass, where a per-PR description string is easy to skim past"
  - "Merging after pushing fixes, when the requested re-review may have posted new findings since anyone last looked"
  - "Any merge gate whose signal is a binary pass/fail that a third-party bot deliberately never fails"
symptoms:
  - "`gh pr checks <N>` shows the CodeRabbit row as `pass` while its description reads `Review skipped: incremental reviews are disabled`"
  - "`gh pr view <N> --json mergeStateStatus` returns `CLEAN` on a PR that still carries untriaged findings"
  - "A check reading `Review completed` on a PR whose most recent re-review posted findings nobody read"
  - "Unresolved review threads surface only by accident, from an unrelated question"
  - "A PR reported as clean turns out to contain a real defect the reviewer had already flagged"
root_cause: observability_gap
resolution_type: workflow_improvement
related_components:
  - development_workflow
  - verification
tags:
  - coderabbit
  - code-review
  - pull-request
  - gh-cli
  - merge-gate
  - silent-failure
  - false-negative
  - review-threads
related_solutions:
  - "docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md — same root_cause; a verdict is only as good as the instrument, and here the blind instrument is a check's pass-state"
---

# A green check is not a review — read the description string and enumerate the threads

## Context

On 2026-08-25 in `villavicencio/dotfiles`, three PRs (#176, #177, #178) were reported as green
and ready to merge. The evidence was a `gh pr checks` line showing `pass` and a
`mergeStateStatus` that was not blocking. Two of the three were not reviewed-and-clean:

- **#178** — check `pass`, description **`Review skipped: incremental reviews are disabled`**.
  A passing check on which *no review ran for the pushed head*. It still carried two untriaged
  findings from its one initial review, with no reply on either thread.
- **#177** — at report time the check read `pass — Review completed`, the string that *does*
  mean a review ran. But a re-review requested after the first round of fixes had posted **two
  new findings** nobody had read. One was cosmetic (markdownlint MD040). One was a real bug.
- **#176** — genuinely clean: `Review completed`, two findings, both fixed, both confirmed,
  both threads resolved. The control case.

Net: **four unaddressed findings across two PRs, all reported as clean.** Discovery was
accidental — the user asked an unrelated question about whether PRs were being auto-merged.

The real bug among the four shows what the pass-state gate was hiding. `CLAUDE.md` documented a
recipe for installing a Claude Code hook as a branch-independent copy:

```bash
git show <branch>:claude/hooks/<hook>.sh > ~/.claude/hooks/<hook>.sh && chmod +x ~/.claude/hooks/<hook>.sh
```

The destination is a Dotbot symlink into the repo working tree, and in the exact situation the
recipe exists to rescue, that symlink is *dangling*. The reviewer predicted the redirect would
fail. Tested empirically on this Mac, the truth is quieter and worse:

```text
before:   hooks/h.sh -> repo/h.sh     (repo/h.sh does not exist)
redirect: echo "content" > hooks/h.sh ; exit=0
after:    hooks/h.sh -> repo/h.sh     (still a symlink)
          repo/h.sh  8 bytes          (content landed HERE)
```

The redirect **succeeds silently**, the symlink stays a symlink, and content lands at the
symlink's *target* inside the repo working tree. The hook still does not exist where Claude Code
looks for it, **and** an untracked file is dropped into the repo. A failure would have been
loud; a silent success is what actually happens.

### This is not a knowledge gap — that is the important part

This repo hit the same class of problem repeatedly across the week of 2026-08-18 to 08-25 —
five PRs below, drawn from roughly as many prior sessions *(session history; the
session-to-PR mapping is not verifiable from git metadata, the PRs are)*. The rules now in
`claude/CLAUDE.md` are accreted scar tissue from these incidents:

- **#142 (merged 2026-08-18 PDT / 08-19 UTC)** merged on `CLEAN` while CodeRabbit was
  rate-limited; its reviews array is empty — no review ever ran. The lesson was written to
  memory the same hour, and not obeyed six days later.
- **#170 (08-24)** merged past a stale `CHANGES_REQUESTED` whose re-review had been throttled.
  The user's correction is what produced the current global rule.
- **#146, #171, #175** each had real findings that were recovered *only* by separately
  enumerating the comments endpoint, after a watcher had already declared green.

Most pointedly: when `.coderabbit.yaml` landed on #171 (08-24), the `Review skipped` string was
**explicitly recognized at the time** as one of three clean-looking states that don't mean
reviewed, and written into the global rules *(session history)*. So the gap has never been
*knowing* that a passing check can mean no review. It is that the merge-time checklist gates on
**state**, and the state is identical across "reviewed clean," "skipped," "throttled," and
"reviewed and found four things."

That history is why the remedy below is an executable check rather than another warning.
Warnings have been written five times and the failure recurred anyway.

### Why no verdict-based gate could have caught it

Every CodeRabbit review on #177 and #178 was submitted as **`COMMENTED`**, never
`CHANGES_REQUESTED`. The existing rule *"do not merge while its verdict is
`CHANGES_REQUESTED`"* had no trigger to fire on — there was never a blocking verdict to go
stale. The findings existed **only** as inline review comments.

### Why `Review skipped` is the normal state here

```yaml
# .coderabbit.yaml
reviews:
  auto_review:
    auto_incremental_review: false
```

That setting is correct and deliberate — it exists to stop every intermediate push from
spending against the per-developer hourly allowance. It is not a misconfiguration to undo. But
its direct consequence is that **after the first review, every subsequent push leaves a passing
check on which no review ran**, until someone comments `@coderabbitai review`. In a repo with
this config, `Review skipped` on an open PR is the *default*, not an anomaly.

## Guidance

**A check's pass/fail state is not evidence a review happened, and a completed review is not
evidence its findings were triaged. Read the description string, then enumerate the threads —
both, every time, before declaring a PR mergeable.**

### Step 1 — read the check description, not its state

```bash
gh pr checks <N> --json name,state,description \
  -q '.[] | select(.name|test("CodeRabbit";"i")) | "\(.state)\t\(.description)"'
```

| Description | Check state | Did a review run? |
|---|---|---|
| `Review completed` | pass | **Yes** — go to step 2 |
| `Review skipped: incremental reviews are disabled` | **pass** | **No** — request one with `@coderabbitai review` |
| `Review rate limited` | **pass** | **No** — throttled; wait, or take the docs/config carve-out and record the throttle in the PR body |
| `Review in progress` / `pending` | pending | Not finished — keep polling |
| `Review failed — the head commit changed during the review` | — | **No** — a push aborted it; the allowance was spent for nothing |

**Three of those five rows show a `pass` state, and only one of them means a review actually
ran.** Treat `pass` as carrying no information until you have read the string next to it.

> The older rule — *poll `gh pr checks <N> \| grep -i '^CodeRabbit'` until it stops saying
> `pending`* — is satisfied instantly by all three non-review states. A non-pending pass is not
> a completed review.

### Step 2 — enumerate unresolved threads

The description only says whether a review *ran*. It never says what it found, and findings
arrive as `COMMENTED` reviews that set no blocking verdict. The GraphQL `reviewThreads`
connection is the only surface exposing `isResolved`, which REST does not:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F pr=<N> -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
    reviewThreads(first:100){ nodes{
      isResolved path line originalLine
      comments(last:1){ nodes{ author{login} createdAt } } } } } } }' \
 -q '.data.repository.pullRequest.reviewThreads.nodes[]
     | select(.isResolved | not)
     | "UNRESOLVED  \(.path):\(.line // .originalLine)  last=\(.comments.nodes[0].author.login)"'
```

**Empty output is the merge signal. Any line is a blocker.** Use `.line // .originalLine` —
`line` is `null` on threads whose diff position went stale, and a bare `.line` renders real
findings as `path:null`.

Two decision rules read off that output:

1. **Any unresolved thread blocks the merge.** Fix it, or decline it with the reason recorded
   both on the thread and in the PR body.
2. **The last comment on each thread must be a confirmation, not a new finding.** On a healthy
   thread the newest comment is the bot acknowledging your fix. A thread whose newest comment is
   the bot *opening* a finding is untriaged regardless of age.

REST fallback — no resolution state, so you must read the ordering yourself:

```bash
gh api --paginate repos/<owner>/<repo>/pulls/<N>/comments \
  -q '.[] | "\(.created_at)  \(.user.login)  [\(.path):\(.line // .original_line)]"'
```

`--paginate` is mandatory: a bare call caps at one page and silently drops findings past it.

### Step 3 — "I fixed everything it found" is not durable

A re-review can **add** findings after the previous round was fully resolved. On #177: four
findings, all fixed, all confirmed, all threads resolved — then the requested re-review posted
two brand-new ones. **Re-run step 2 after every re-review**, not once at the end.

### What `mergeStateStatus` is for

`CLEAN` means nothing is *blocking* the merge button. It cannot be a review signal here:
`COMMENTED` reviews never block, so a PR carrying unresolved findings reads `CLEAN` by
construction. Use it for merge conflicts and required-check failures. Never as review evidence.

## Why This Matters

**The failure mode is silent and self-confirming.** Every signal consulted was literally
accurate — the check *did* pass, the merge *was* unblocked, the reviews API *did* report no
`CHANGES_REQUESTED`. None were about whether a review happened. An agent following the old
checklist to the letter produces "green, ready to merge" with no way to notice it is wrong.

**The safe-looking default is the dangerous one.** `Review skipped` is the *normal* steady state
on an open PR here. A gate that only distinguishes pass from fail reads the common case as
approval, on every PR, forever.

**Findings are load-bearing.** One of the four missed here would have shipped a recipe that
fails worse than failing: writing a hook to the wrong place, exiting 0 about it, and leaving an
untracked file in the repo.

**Autonomous merging raises the stakes.** An agent that merges without a human reading threads
is the only reader those findings will ever get. A pass-state gate makes that reader blind by
construction.

## When to Apply

Apply both steps before:

- Declaring any PR green, clean, or ready to merge.
- Running `gh pr merge`, autonomously or on request.
- Reporting review status across a batch. Batches fail worst — #176's genuinely-clean state lent
  credibility to the two that were not.

Re-run **step 2** specifically after every `@coderabbitai review` round, and after any push to a
PR that already had a review.

Applies to any repo with `auto_incremental_review: false` (`skills`, `dotfiles`). Repos on
push-triggered re-review (`borealis`) will not show `Review skipped`, but the throttle string,
the `COMMENTED`-verdict gap, thread enumeration, and re-reviews-add-findings all apply unchanged.

Step 1 is cheap enough to be unconditional; step 2 is one API call. The documented "a trivial
diff may skip review" carve-out is about *not requesting* a review, and still requires stating
the skip and its reason when reporting the merge.

## Examples

### Before — the report that was wrong

```text
$ gh pr checks 178 | grep -i '^CodeRabbit'
CodeRabbit	pass	0		Review skipped: incremental reviews are disabled
                ^^^^
                stopped reading here
```

Reported: *"#178 is green — ready to merge."* Reality: no review ran on the pushed head, and two
findings sat untriaged.

### After — the same PR, both steps

```text
$ gh pr checks 178 --json name,state,description -q '...'
SUCCESS	Review skipped: incremental reviews are disabled

$ threads 178
UNRESOLVED  AGENTS.md:276  last=coderabbitai
UNRESOLVED  CLAUDE.md:345  last=coderabbitai
```

Correct report: *"#178 is NOT ready. The passing check is `Review skipped` — no review ran on the
current head, and two findings are unresolved."*

### The control case

```text
$ gh pr checks 176 --json name,state,description -q '...'
SUCCESS	Review completed

$ threads 176
                       # empty
```

Both signals agree. This is the only combination supporting "ready to merge."

### The re-review trap — #177

```text
22:25:50  coderabbitai[bot]  4 findings opened
23:00:1x  villavicencio      4 replies: "Fixed in <sha>…"
23:00:3x  coderabbitai[bot]  4 confirmations → all 4 threads resolved
          ← "I fixed everything it found" was TRUE at this instant
23:06:09  coderabbitai[bot]  2 NEW findings  ← the re-review added these
```

The completion state of round N tells you nothing about round N+1.

## Related

- `docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md` — same
  `observability_gap` root cause. A negative conclusion is only as good as the instrument that
  produced it; here the blind instrument is a check's pass-state.
- `claude/CLAUDE.md` → "Code Review" — the cross-repo merge procedure this doc's steps amend.
- `.coderabbit.yaml` — the setting that makes `Review skipped` the steady state.
