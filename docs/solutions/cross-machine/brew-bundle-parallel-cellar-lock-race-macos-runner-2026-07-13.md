---
title: "`brew bundle` races on shared-dependency Cellar locks when the macos-15 runner parallelizes it"
date: 2026-07-13
category: cross-machine
tags:
  - homebrew
  - brew-bundle
  - macos-runner
  - github-actions
  - install-matrix
  - flaky-ci
  - parallelism
  - cellar-lock
severity: Medium
component: ".github/workflows/install-matrix.yml — macOS job `env:` block; `HOMEBREW_BUNDLE_JOBS`"
symptoms:
  - "macOS install-matrix leg intermittently red on commits that don't touch brew/Brewfile"
  - "Intermittent: `A ...brew install --formula <X>... process has already locked /opt/homebrew/Cellar/<keg>`"
  - "The racing pair varies run-to-run (e.g. `go` via `gitleaks`, `luajit` via `luarocks`)"
  - "`brew bundle failed! N Brewfile dependencies failed to install` — but a plain re-run fails again on a DIFFERENT pair"
problem_type: "Parallel `brew bundle` install races on shared-dependency Cellar keg locks, producing nondeterministic flaky CI failures"
module: "install-matrix CI workflow"
related_solutions:
  - "docs/solutions/cross-machine/adoptopenjdk-dead-tap-fails-brew-bundle-2026-07-13.md — the OTHER macOS-CI failure discovered in the same red run; both had to land together for green master"
  - "docs/solutions/cross-machine/python-bytecode-cache-falsely-fails-r2-on-macos-runners-2026-05-04.md — sibling macos-15-runner-specific behavior in the same workflow"
---

## TL;DR

The macOS leg intermittently fails with `... process has already locked /opt/homebrew/Cellar/<keg>`. That error requires **two concurrent `brew` processes** — so `brew bundle` was installing in **parallel** on the runner, even though our helper passes no `--jobs` and Homebrew's upstream default is `--jobs=1` (serial). The `macos-15` runner image injects a higher bundle job count. Parallel installs of formulae that share a dependency keg (e.g. `luarocks` needs `luajit`, which is also a top-level Brewfile entry; `go` is pulled by `gitleaks`) collide on the Cellar lock. It's **nondeterministic** — the racing pair changes run-to-run and a plain re-run doesn't reliably clear it. Fix: pin `HOMEBREW_BUNDLE_JOBS: '1'` in the macOS job `env:` to force serial installs, overriding whatever the runner injects. (PR #98, commit `ab3c347`.) Drop the pin once Homebrew ships its upstream lock-fix ([Homebrew/brew#22293](https://github.com/Homebrew/brew/issues/22293) / #22297) to the runner image.

## Symptom

The macOS leg failed in `Apply (./install)`:

```
##[error]A `brew install --formula gitleaks` process has already locked /opt/homebrew/Cellar/go.
##[error]A `brew install --formula luarocks` process has already locked /opt/homebrew/Cellar/luajit.
`brew bundle` failed! 2 Brewfile dependencies failed to install
```

Two properties made it clearly a race, not a config bug:

1. **The racing pair varied run-to-run.** One run: `go` (direct) + `luarocks`→`luajit`. A re-run: `gitleaks`→`go` + `luarocks`→`luajit`. Same commit, same Brewfile, different collisions.
2. **A plain re-run did NOT fix it.** Re-running the failed macOS job just produced a different racing pair — verified twice. Re-runs are not a fix.

## Root cause

**An "already locked" error requires ≥2 concurrent `brew` processes.** `brew install` acquires a lock on the target formula's `Cellar/<keg>` path; a second `brew` touching the same keg reports "already locked." A single serial installer can never collide with itself.

So `brew bundle` was running **parallel installs** on the runner. But:

- Our helper (`helpers/install_from_brewfile.sh`) runs plain `brew bundle --file=./brew/Brewfile` — **no `--jobs` flag**.
- Homebrew's upstream default is **`--jobs=1` (serial)** — parallel bundle install is opt-in via `--jobs=N` / `--jobs=auto` / the `HOMEBREW_BUNDLE_JOBS` env var (added in [Homebrew/brew#21891](https://github.com/Homebrew/brew/pull/21891)).

Therefore the parallelism is **injected by the `macos-15` runner image**, which ships a default environment raising the bundle job count. Under parallelism, two formulae that need the same keg get installed concurrently and race on its lock:

| Racing formula | Shared keg | Why they collide |
|---|---|---|
| `luarocks` (top-level) | `luajit` | `luarocks` depends on `luajit`, which is *also* a top-level Brewfile entry — both install paths touch the same keg |
| `gitleaks` / other | `go` | `go` is pulled as a dependency by a Go-based formula while another install also wants it |

The upstream lock-handling bug is acknowledged and being fixed in Homebrew ([#22293](https://github.com/Homebrew/brew/issues/22293) / #22297) — until that reaches the runner image, parallel bundle installs remain racy.

## Fix

Pin the job count to 1 in the macOS job `env:` block, next to the existing `HOMEBREW_*` tuning:

```yaml
  macos:
    runs-on: macos-15
    env:
      HOMEBREW_NO_AUTO_UPDATE: '1'
      HOMEBREW_NO_INSTALL_CLEANUP: '1'
      HOMEBREW_BUNDLE_JOBS: '1'   # force serial; overrides runner-injected parallelism
      CI: 'true'
```

Setting `HOMEBREW_BUNDLE_JOBS: '1'` at job scope overrides whatever the runner injects, regardless of its source (runner env or a future Homebrew default flip).

### Why in the workflow, not the helper

The pin lives in CI config, **not** `install_from_brewfile.sh`, on purpose:

- **Real-machine `./install` is unaffected** — it relies on Homebrew's serial default and doesn't set this var. Forcing `--jobs=1` in the helper would permanently forgo the parallel-install speedup on real bootstraps, even after Homebrew fixes the bug.
- **Trade-off accepted:** serial install makes the macOS leg somewhat slower but **deterministic** — no more flaky reds.
- **Escape hatch:** if a *real* fresh-machine install ever races (i.e., Homebrew flips the default to parallel for everyone), export the same var in the helper.

## The general lesson

- **"already locked" ⇒ concurrency.** If you see a Cellar lock error, something is running two `brew` processes at once. Find the parallelism source before assuming a package is broken.
- **The parallelism may not be in your code.** Our invocation was serial-by-default; the runner image supplied the parallelism. When CI behaves differently from a local run with identical commands, suspect the runner environment (see workflow header caveat #8 on runner-image rotation).
- **A re-run is not a fix for a race.** It just re-rolls the dice. Only removing the concurrency (serial install) fixes it deterministically.

## Sites

- `.github/workflows/install-matrix.yml` — macOS job `env:` block declaring `HOMEBREW_BUNDLE_JOBS: '1'`
- `helpers/install_from_brewfile.sh` — the plain `brew bundle --file=...` invocation (no `--jobs`; inherits the env var)

## Verification

PR #98's macOS log had **zero `already locked` lines** after the pin (the fix's signal), with the `brew bundle` failure count dropping to 1 — and that 1 was the unrelated dead-`adoptopenjdk`-tap failure (removed in PR #96, see related doc). Once both fixes were on master, PRs #97 and #95 — rebased onto the fixed master — passed the full install-matrix (linux **and** macOS) green.

## When to remove the pin

Drop `HOMEBREW_BUNDLE_JOBS: '1'` once the upstream lock-fix ([Homebrew/brew#22293](https://github.com/Homebrew/brew/issues/22293) / #22297) lands in the `macos-15` runner image. At that point parallel bundle installs become safe again and the serial pin is just leaving CI speed on the table. The pin's inline comment flags this.
