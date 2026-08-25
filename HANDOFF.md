---
created_at: "2026-08-25T09:08:30-07:00"
branch: "master"
head: "289225d"
resume_focus: "Paste the skills changelist (scratchpad, or regenerate), then the borealis one — both repos still carry pre-reconciliation CodeRabbit rules"
---

# HANDOFF — 2026-08-25, morning (PDT)

Started as the small task the last handoff left: seed the empty Linear `Dotfiles`
backlog. It turned into a CodeRabbit governance consolidation after David asked to
sweep every project for CodeRabbit references and globalize the rules. Six PRs
merged (#168–#173), all reviewed. The previous arc (Linear migration, eleven-agent
fleet, Moshi, ShipSigma) is now fully closed out.

## What We Built

- **PR #171 — the CodeRabbit reconciliation, the centerpiece.** Global CLAUDE.md's
  "Code Review" section is now the single source of truth: CodeRabbit primary,
  `dv:gauntlet` escalation. Read the section before touching any per-repo review
  rule; the whole point was ending the duplication.
- **PR #172 — two rules from the skills session's workout of #171** (nine PRs, 35
  findings): never push mid-review, and anchor session continuity on the handoff's
  `head`. Both live in the same global section.
- **PR #170 — `BAR_CELLS` 10→20** (`claude/statusline-command.sh:53`). David picked
  20 from rendered previews at 10/15/20. The comment there records what widening
  actually buys, which is *not* what the ticket claimed — see What Didn't Work.
- **PR #173 — dropped the project-scoped `dv` pin.** dotfiles had `dv` at both user
  scope (0.4.0) and project scope (0.3.0, pinned 2026-08-07); project wins, so every
  session here silently ran 0.3.0. `.coderabbit.yaml` (new, repo root) sets
  `auto_incremental_review: false`.
- **PRs #168/#169 — mid-session handoff correction and the continuity reorder.**
  #168 is the precedent for fixing HANDOFF mid-session rather than waiting for the
  next `dv:handoff` run.
- **Linear:** VIL-83 **Done** (closed by #172). VIL-82 retitled and **blocked** —
  it carries a 30-second recheck procedure for the next Claude Code version bump.
  ShipSigma KPI: VIL-17→20 **Canceled**, project Canceled with a note, VIL-21 left
  Done because it shipped.
- **Two handoff changelists** at
  `/private/tmp/claude-505/-Users-dvillavicencio-Projects-Personal-dotfiles/0cfd7da4-.../scratchpad/`
  — `changelist-skills.md` and `changelist-borealis.md`. Scratchpad is session-scoped
  and may be swept; both are reproducible from #171's diff if gone.

## Decisions Made

- **CodeRabbit is the primary PR reviewer; `dv:gauntlet` is the escalation** — David's
  call, replacing the 2026-08-18 "trial, no decision yet" state. Gauntlet keeps three
  lanes: large/risky diffs, CodeRabbit throttled and can't wait, and non-PR review.
- **Global + dotfiles only; borealis and skills got changelists, not commits.** They
  are other agents' repos and the skills agent was mid-task — one writer per tree.
- **`head` ranks above `created_at`** in the continuity rule, deviating from the
  wording the skills session suggested. dv 0.4.0's handoff skill stamps `created_at`
  from the shell (`skills/handoff/SKILL.md:73`), so it is trustworthy *going forward*,
  but pre-0.4.0 values were model-authored. `head` also survives rebase/checkout.
  The caveat is scoped to pre-0.4.0 so it retires itself.
- **ShipSigma closed as Canceled, not Done** — it was not delivered as specced; the
  work moved to Brittanie's laptop.
- **Merged #170 over a stale `CHANGES_REQUESTED`** — David corrected this, and the
  correction became the rule in #172. Recorded here as the origin of that rule.

## What Didn't Work

- **The Fable/premium-model statusline meter cannot be built.** A captured live
  payload has exactly two entries under `rate_limits` — `five_hour` and `seven_day`.
  `seven_day_opus` / `seven_day_sonnet` exist in the 2.1.241 bundle but serve the API
  rate-limit and warning paths, never the statusline. Not fixable by updating:
  2.1.241 is latest. The negative is trustworthy — the premium limit was at 76%, the
  most interesting of the three, and still absent.
- **My quantization reasoning was wrong twice**, both caught by CodeRabbit. 3%/7% do
  *not* collide at 10 cells (they differ, and collide at 20); 12%/15% differ at both
  widths; the low end *does* generally improve. Check claims against
  `(pct * BAR_CELLS + 50) / 100` rather than reasoning about them.
- **"Prefer `created_at` over mtime" was the wrong premise** for VIL-83. The observed
  bad value was model-authored, so the fix belonged upstream in `dv:handoff` — which
  is where it shipped (VIL-76, dv 0.4.0).

## What's Next

1. **Paste the skills changelist, then the borealis one.** Skills first: it ships PRs
   actively, so the new rules bite there soonest. Borealis has the one functional gap
   — no `.coderabbit.yaml`, so every push there still auto-re-reviews off the shared
   pool.
2. **Restart sessions to pick up dv 0.4.0.** Every project inherits it from user scope
   now. This is what makes `dv:pickup` report "N commits since `<head>`" instead of
   guessing from file age.
3. **VIL-82 stays blocked** — no action until a Claude Code version bump; the recheck
   is on the ticket.
4. Housekeeping, both harmless: `claude plugin prune` clears a dead project pin for a
   herdr worktree that no longer exists; the VPS `axiom` user still has dv **0.1.0**
   (the live Axiom agent runs as `node` and has 0.4.0, so nothing is broken).

## Gotchas & Watch-outs

- **Naming a `VIL-…` id in a PR body can auto-close that issue on merge.** #168 merely
  *recapped* VIL-82 and closed it 13 seconds after merge, auto-assigning it. VIL-83,
  named in the same body, was untouched — so the trigger is narrower than "any id" but
  not predictable. After merging any PR naming ticket ids, re-check their states. Now
  in global CLAUDE.md's Linear section.
- **CodeRabbit limits are per *developer*, not per repo** — 10/hr, confirmed Pro+ from
  the bot's own review footer. Every repo and parallel agent draws from the same 10.
  `@coderabbitai rate limit` reports capacity without consuming a review.
- **Three CodeRabbit check states pass while no review ran**: `pending`,
  `Review rate limited`, and `Review skipped: incremental reviews are disabled`. So
  `mergeStateStatus: CLEAN` is never evidence of review.
- **`.coderabbit.yaml` applies from the PR head, not the base** — a PR adding it
  governs itself immediately.
- **This repo squash-merges every PR, which orphans a handoff's `head`.** An orphaned
  SHA still returns a *believable* commit count (verified: reported 3 when the true
  distance was 5) — it fails silently. dv 0.4.0's pickup already guards this with
  `cat-file -e` + `merge-base --is-ancestor`; don't hand-roll a count without both.
- **`HANDOFF.md` is tracked in this repo, so the handoff commit rides a branch** per
  the standing never-commit-to-master rule. The `dv:handoff` skill's auto-commit block
  assumes committing on the current branch — on `master` that would violate the rule,
  so branch first.
- Fleet roster, jump keys, and the herdr pane template: CLAUDE.md's Herdr section.
  Passive upstream: herdr #2960/#2961/#2966.
