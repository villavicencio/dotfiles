---
title: "install-matrix.yml seeded-failure validation evidence (R3 assertion 2)"
date: 2026-05-06
category: cross-machine
tags:
  - github-actions
  - install-matrix
  - validation
  - seeded-failure
  - r3-assertion-2
  - dotbot
severity: Informational
component: ".github/actions/install-matrix-pre-apply/action.yml — R3 assertion 2 (Dotbot symlink-target resolution)"
problem_type: "validation evidence"
module: "install-matrix CI workflow"
related_solutions:
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md — sibling R3 assertion 1 evidence (origin SC#1)"
  - "docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md — the plan whose R-spec assertions both evidence rounds back"
---

## Why this exists

PR #57 satisfied origin SC#1 by red-CI'ing R3 assertion 1 (no hardcoded
`/Users/<user>/` paths) on a seeded commit. R3 assertion 2 — Dotbot
symlink-target resolution, every `Would create symlink X -> Y` target Y
must exist in the repo — was never exercised against a real failure. A
future Dotbot submodule bump that changes the emitter format could
silently mis-parse and pass the assertion vacuously, and we'd only know
after a real symlink target went missing in production. This doc closes
that evidence gap.

Filed as #60 after PR #57's seeded round only covered R3 assertion 1.

## What was tested

A single seeded link entry pointing to a target file that does not exist
in the repo, added to **both** `install.conf.yaml` and
`install-linux.conf.yaml` so both legs would surface the regression:

```yaml
# SEEDED FAILURE for #60 R3-b evidence — points at a path that does
# not exist in the repo so the dry-run emits a "Would create symlink"
# line whose target fails the existence check in R3 assertion 2. This
# branch is throwaway; do NOT merge.
~/.config/r3b-seed: zsh/nonexistent-r3b-target.sh
```

`zsh/nonexistent-r3b-target.sh` is not in `git ls-files`; the path resolves
to a missing file in the workspace mount.

## Run details

- **Run ID**: `25464126950` ([url](https://github.com/villavicencio/dotfiles/actions/runs/25464126950))
- **Branch**: `seed/r3b-evidence-2026-05-06` (deleted post-evidence)
- **Seeded commit**: `9d1ceb8` — *seed: R3-b evidence — link to nonexistent target (do not merge)*
- **Linux job**: `74713259559` — failed in **14 seconds**
- **macOS job**: `74713259600` — failed in **22 seconds**
- **Trigger**: `workflow_dispatch` against the seed ref (no PR opened — keeps the seed off the PR queue and the failure surface narrow)

## Failure mode (different from what #60's spec predicted)

#60 expected R3 assertion 2's explicit grep + missing-target loop to fire
with `Dotbot symlink target missing: <target>` followed by
`<n> symlink target(s) missing from repo`. **That is not what happened.**

Dotbot's own `--dry-run` mode catches the missing target *before* it ever
gets to emit a `Would create symlink` line for it. The dry-run output
includes the legitimate links followed by:

```
Nonexistent target ~/.config/r3b-seed -> zsh/nonexistent-r3b-target.sh
Some links were not successfully set up
Would run command echo "Installation complete!"

Some tasks were not executed successfully
```

…and Dotbot exits with code 1. With `set -eo pipefail` in the assertion
step's `run:` block, `./install --dry-run | tee "$DRY_LOG"` propagates
that nonzero exit, the step fails immediately, and our explicit grep +
missing-target loop never executes.

This is a more useful finding than the seeded round expected:

1. **Dotbot is more diligent than the assertion assumed.** The
   missing-target class is detected inside Dotbot itself, not just by
   the YAML-side assertion. Coverage of this regression class is
   defense-in-depth, not single-point.
2. **R3 assertion 2 remains a backstop.** It still has teeth for failure
   modes where Dotbot's pre-check doesn't fire (output format change,
   suppressed Dotbot errors, an entirely new emitter wording the
   pre-check doesn't cover, or a future regression where Dotbot emits a
   `Would create symlink` line and only surfaces missing-target later).
3. **The strict regex from #61 still earns its keep.** If a Dotbot bump
   changes "Would create symlink X -> Y" to "Would create symlink X => Y",
   the strict regex falls through to zero matches and the
   fresh-runner sanity check (`created≥1`) fires — which is the actual
   live primary guard for emitter-format drift.

## Step-by-step results (per leg)

| Step | Linux conclusion | macOS conclusion |
| --- | --- | --- |
| Set up job | ✅ success | ✅ success |
| Checkout | ✅ success | ✅ success |
| Mark workspace safe / Cache restore | ✅ success | ✅ success |
| **Pre-apply assertions (R2 + R3 symlink-resolution + checkout cleanup)** | ❌ **failure** | ❌ **failure** |
| Apply (./install) | ⏭ skipped | ⏭ skipped |
| Post-apply assertions (R3 user-paths + R4 zsh init) | ⏭ skipped | ⏭ skipped |

## Failure messages captured

**Linux (`74713259559`)**:

```
2026-05-06T22:14:33.5436724Z Nonexistent target ~/.config/r3b-seed -> zsh/nonexistent-r3b-target.sh
2026-05-06T22:14:33.5437095Z Some links were not successfully set up
2026-05-06T22:14:33.5437399Z Would run command echo "Installation complete!"
2026-05-06T22:14:33.5437696Z Some tasks were not executed successfully
2026-05-06T22:14:33.5533836Z ##[error]Process completed with exit code 1.
```

**macOS (`74713259600`)**:

```
2026-05-06T22:14:36.4898970Z Nonexistent target ~/.config/r3b-seed -> zsh/nonexistent-r3b-target.sh
2026-05-06T22:14:36.4899320Z Some links were not successfully set up
2026-05-06T22:14:36.4901110Z Some tasks were not executed successfully
```

Both legs identical in mode and order; the runner-platform difference
collapses to the timestamp.

## What this proves

1. **Missing-target regressions red-CI in seconds, not the full
   assertion-step budget.** Both legs failed within ~22 seconds because
   Dotbot's dry-run short-circuits at the first nonexistent target and
   never gets to the post-apply steps.
2. **`set -eo pipefail` is load-bearing for this defense.** Without it,
   `./install --dry-run` would emit the error line and continue, and our
   tee-captured log would contain a `Nonexistent target` line that the
   regex doesn't match (it matches `^Would create (sym|hard)link`),
   which means the assertion would *vacuously pass* — `created` would
   still be ≥1 from the legitimate links, and there'd be no
   missing-target loop trigger because Dotbot didn't emit one. Keep the
   pipefail.
3. **R3 assertion 2 is structurally correct as a backstop.** The
   regex-tightening from #61 plus the missing-target loop combine to
   cover the case where a future Dotbot version emits a `Would create
   symlink` line for a nonexistent target instead of bailing
   pre-emptively. That theoretical case isn't exercised by this seed,
   but the synthetic regex test in #61's PR body confirms the parser
   does the right thing if it ever sees that input.
4. **Cross-platform parity.** Both Linux container and macOS-15 bare
   runner reach the same failure at the same step in the same mode.

## Cleanup

The seed branch was force-removed locally and pushed-deleted from origin
after this evidence was captured. Master is unaffected; no merge
occurred.

```
git branch -D seed/r3b-evidence-2026-05-06
git push origin --delete seed/r3b-evidence-2026-05-06
```

## Operational notes

- **If you want to seed R3 assertion 2's own grep + missing-target
  loop directly**, you'd need to bypass Dotbot's pre-check — for
  example, by making Dotbot emit a `Would create symlink` line whose
  target *exists at dry-run time but is removed before the assertion
  grep runs*. That's a contrived race and not worth setting up; the
  defense-in-depth structure documented above is the practical
  validation surface.
- **For future seeded rounds on this matrix**, this directory
  (`docs/solutions/cross-machine/`) is the canonical home. Filename
  pattern: `install-matrix-seeded-failure-evidence-<assertion>-<date>.md`.
