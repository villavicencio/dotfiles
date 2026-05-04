---
title: "install-matrix.yml seeded-failure validation evidence (origin SC#1)"
date: 2026-05-03
category: cross-machine
tags:
  - github-actions
  - install-matrix
  - validation
  - seeded-failure
  - origin-sc1
severity: Informational
component: ".github/workflows/install-matrix.yml — R3 assertion 1 (no hardcoded user paths)"
problem_type: "validation evidence"
module: "install-matrix CI workflow"
related_solutions:
  - "docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md — the plan whose origin Success Criterion #1 this satisfies"
  - "docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md — sibling cross-machine workflow"
---

## Why this exists

The plan for `feat/ci-install-matrix` (PR #57) requires manual seeded-failure
validation per origin SC#1 — proving that a deliberate, in-scope regression
red-CIs both Linux and macOS legs at the *correct* assertion before the matrix
is allowed to merge. Without this round, we'd ship a CI workflow whose green
status meant only "the workflow ran without errors," not "the assertions
actually have teeth." This doc is the durable record so future readers can see
what was tested and what fired.

## What was tested

A single line was added to `helpers/install_node.sh` (a tracked install-pipeline
file inside the R3 grep scope):

```
# SEEDED-FAILURE-2026-05-03: deliberate hardcoded /Users/dvillavicencio/Downloads/foo
# path to verify R3 assertion 1 trips on both legs. REVERT BEFORE MERGE.
```

The literal `/Users/dvillavicencio/Downloads/foo` substring matches the R3
grep regex `/Users/[^/]+/`. No other change.

## Why this bug class

Origin SC#1 names three regression classes — cross-platform divergence,
fresh-`$HOME` mutation, and shell-startup regression. A hardcoded user path is
the canonical cross-platform divergence bug: the path resolves on one machine
but breaks bootstrap on every other. R3 assertion 1 is the matrix's first line
of defense against this exact class. It's also the cheapest assertion to
exercise (a `grep` against tracked files, no install state required), so the
evidence is unambiguous and not coupled to install-pipeline timing or runner
flakiness.

## Run details

- **Run ID**: `25293491791` ([url](https://github.com/villavicencio/dotfiles/actions/runs/25293491791))
- **Branch**: `feat/ci-install-matrix`
- **Seeded commit**: `6db87f9` — *SEEDED FAILURE: hardcoded /Users/dvillavicencio/ in install_node.sh*
- **Linux job**: `74148651331` — failed in **1m 6s**
- **macOS job**: `74148651338` — failed in **10m 8s**

## Step-by-step results (per leg)

| Step | Linux conclusion | macOS conclusion |
| --- | --- | --- |
| Set up job | ✅ success | ✅ success |
| Bootstrap deps (python3, sudo) / Cache restore | ✅ success | ✅ success |
| Checkout | ✅ success | ✅ success |
| Mark workspace safe (Linux only) | ✅ success | n/a |
| **R2 + R3 dry-run / symlink-resolution** | ✅ success | ✅ success |
| Clean `$HOME/.gitconfig` | ✅ success | ✅ success |
| **Apply (./install)** | ✅ success | ✅ success |
| **R3 assertion 1 (no hardcoded user paths)** | ❌ **failure** | ❌ **failure** |
| R4 assertion (`zsh -i -c true`) | ⏭ skipped (R3 short-circuited) | ⏭ skipped (R3 short-circuited) |

## Failure messages captured

Both legs emitted the same xargs-grep output (the file with the offending path)
followed by the workflow-level error annotation:

**Linux (`74148651331`)**:
```
2026-05-03T23:09:45.9682610Z helpers/install_node.sh
2026-05-03T23:09:45.9716645Z ##[error]found hardcoded user path(s) in install-pipeline files
```

**macOS (`74148651338`)**:
```
2026-05-03T23:18:44.2731270Z helpers/install_node.sh
2026-05-03T23:18:44.2783110Z ##[error]found hardcoded user path(s) in install-pipeline files
```

## What this proves

1. **R3 assertion 1 has teeth.** Both legs surfaced the offending file by name
   and aborted the job at the correct step.
2. **Apply succeeded before R3 fired.** The seeded comment didn't break
   `./install` (it's a comment, no runtime impact), so the assertion failure is
   genuinely catching a *would-be-merged* bug rather than collateral install
   damage.
3. **R4 short-circuited correctly.** Skipped on both legs because R3 failed
   first; the matrix doesn't waste runtime on later assertions when an earlier
   one trips.
4. **Cross-platform parity.** Identical failure mode and output on Linux
   container and macOS-15 bare runner.

## Cleanup

The seeded commit was reverted before merge (see commit immediately following
`6db87f9` on this branch). The next CI run on this branch returned both legs
to green.

## Operational notes for future seeded rounds

- This kind of validation belongs in PRs that change *what the matrix
  asserts*, not every PR. R2/R3/R4 are stable and don't need re-validation
  unless their assertion logic is materially edited.
- For a future expansion (e.g., adding a credential-pattern grep), repeat
  this dance with a seeded fake credential and a corresponding evidence doc
  under this same directory.
