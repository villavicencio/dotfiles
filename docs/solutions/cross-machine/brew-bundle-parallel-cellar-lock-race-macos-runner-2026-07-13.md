---
title: "`brew bundle` races on shared-dependency Cellar locks under Homebrew's parallel `auto` default (observed on the macOS CI leg)"
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

The macOS leg intermittently fails with `... process has already locked /opt/homebrew/Cellar/<keg>`. That error requires **two concurrent `brew` processes** — so `brew bundle` was installing in **parallel**, because our helper passes no `--jobs` and current Homebrew (6.x) defaults `HOMEBREW_BUNDLE_JOBS` to `auto` (parallel, up to 4 jobs). (An earlier version of this doc mis-attributed the parallelism to a runner-injected job count and claimed Homebrew defaults to serial — see the 2026-07-14 update below; the default is `auto`, which also exposes real machines.) Parallel installs of formulae that share a dependency keg (e.g. `luarocks` needs `luajit`, which is also a top-level Brewfile entry; `go` is pulled by `gitleaks`) collide on the Cellar lock. It's **nondeterministic** — the racing pair changes run-to-run and a plain re-run doesn't reliably clear it. Fix: pin `HOMEBREW_BUNDLE_JOBS: '1'` in the macOS job `env:` to force serial installs, overriding Homebrew's parallel `auto` default. (PR #98, commit `ab3c347`.) ~~Drop the pin once Homebrew ships its upstream lock-fix ([Homebrew/brew#22293](https://github.com/Homebrew/brew/issues/22293) / #22297) to the runner image.~~ **Superseded — see "When to remove the pin" below: the fix shipped and reached the runner, but the race persists, so the pin stays.**

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

So `brew bundle` was running **parallel installs**. The source:

- Our helper (`helpers/install_from_brewfile.sh`) runs plain `brew bundle --file=./brew/Brewfile` — **no `--jobs` flag** — so it inherits Homebrew's default.
- Current Homebrew (6.x) defaults `HOMEBREW_BUNDLE_JOBS` to **`auto`** (parallel, up to 4 jobs). The `HOMEBREW_BUNDLE_JOBS` env var was added in [Homebrew/brew#21891](https://github.com/Homebrew/brew/pull/21891). (The original investigation believed the default was serial and the runner was "injecting" parallelism — that was wrong; parallelism is Homebrew's own default, which is why it also affects real machines.)

Under that parallel default, two formulae that need the same keg get installed concurrently and race on its lock:

| Racing formula | Shared keg | Why they collide |
|---|---|---|
| `luarocks` (top-level) | `luajit` | `luarocks` depends on `luajit`, which is *also* a top-level Brewfile entry — both install paths touch the same keg |
| `gitleaks` / other | `go` | `go` is pulled as a dependency by a Go-based formula while another install also wants it |

The upstream lock-handling bug ([#22293](https://github.com/Homebrew/brew/issues/22293) / #22297, fixed in Homebrew 5.1.12) was expected to make parallel bundle installs safe. **It did not** for this Brewfile — the race persisted on Homebrew ≥6.0.5; see the 2026-07-14 update in "When to remove the pin".

## Fix

Pin the job count to 1 in the macOS job `env:` block, next to the existing `HOMEBREW_*` tuning:

```yaml
  macos:
    runs-on: macos-15
    env:
      HOMEBREW_NO_AUTO_UPDATE: '1'
      HOMEBREW_NO_INSTALL_CLEANUP: '1'
      HOMEBREW_BUNDLE_JOBS: '1'   # force serial; overrides Homebrew's parallel `auto` default
      CI: 'true'
```

Setting `HOMEBREW_BUNDLE_JOBS: '1'` at job scope forces serial installs, overriding Homebrew's `auto` default.

### Why in the workflow, not the helper

The pin lives in CI config, **not** `install_from_brewfile.sh`, on purpose:

- **CI must be deterministic.** A flaky red on an unrelated commit is expensive and misleading, so the leg is pinned serial.
- **Real-machine `./install` is deliberately left unpinned** — it inherits Homebrew's parallel `auto` default and gets the speedup. This is an explicit speed-vs-reliability tradeoff: a real bootstrap **can** hit the same race, but a failed `brew bundle` can be re-run (nondeterministically — the colliding pair changes, so it's not a guaranteed fix) and it's not blocking a merge.
- **Escape hatch:** pin the same var in `install_from_brewfile.sh` if deterministic local installs are ever required (at the cost of the parallel speedup).

## The general lesson

- **"already locked" ⇒ concurrency.** If you see a Cellar lock error, something is running two `brew` processes at once. Find the parallelism source before assuming a package is broken.
- **Check the tool's *current* default, not what you remember.** The parallelism here came from Homebrew's own `HOMEBREW_BUNDLE_JOBS=auto` default (6.x), not from a runner injection as first assumed. A wrong root-cause ("the runner defaults differ") sends you looking in the wrong place and misleads the next reader — verify the default in the installed version.
- **A re-run is not a fix for a race.** It just re-rolls the dice. Only removing the concurrency (serial install) fixes it deterministically.

## Sites

- `.github/workflows/install-matrix.yml` — macOS job `env:` block declaring `HOMEBREW_BUNDLE_JOBS: '1'`
- `helpers/install_from_brewfile.sh` — the plain `brew bundle --file=...` invocation (no `--jobs`; inherits the env var)

## Verification

PR #98's macOS log had **zero `already locked` lines** after the pin (the fix's signal), with the `brew bundle` failure count dropping to 1 — and that 1 was the unrelated dead-`adoptopenjdk`-tap failure (removed in PR #96, see related doc). Once both fixes were on master, PRs #97 and #95 — rebased onto the fixed master — passed the full install-matrix (linux **and** macOS) green.

## When to remove the pin

**Do not remove it based on the upstream fix.** The original guidance here — "drop the pin once [Homebrew/brew#22293](https://github.com/Homebrew/brew/issues/22293) / #22297 lands in the runner image" — was **wrong**, and this section supersedes it.

### Update 2026-07-14 — the upstream fix does NOT cover this race

The #22297 fix shipped in Homebrew 5.1.12 (2026-05-16) and the `macos-15` runner already carries it: the failing run [`29301199411`](https://github.com/villavicencio/dotfiles/actions/runs/29301199411) (2026-07-14) used image `20260706.0213.1`, which ships **Homebrew ≥ 6.0.5** — well above 5.1.12 — and it *still* logged `A `brew install --formula gitleaks` process has already locked /opt/homebrew/Cellar/go.` and the same for `luarocks`/`luajit`. So #22297 does not eliminate **this Brewfile's** shared-dependency contention.

Two corrections to the analysis above:
- The claim that "Homebrew's upstream default is `--jobs=1` (serial)" is **outdated**. Current Homebrew (6.x) defaults `HOMEBREW_BUNDLE_JOBS` to `auto` (parallel, up to 4). The runner isn't "injecting" parallelism so much as running Homebrew's own default — and so do **real machines**, which are exposed to the same race (the helper doesn't pin jobs).
- Removal is therefore **unsafe** and would reintroduce intermittent red macOS legs. Keep `HOMEBREW_BUNDLE_JOBS: '1'` in CI until the race is root-caused at the Brewfile level (shared-dep fan-out; the P1-3 curation may reduce but is not expected to eliminate it). Only then, verify removal with **repeated** parallel runs, not a single green leg.

(Verified while executing roadmap packet P0-4, which had proposed removing the pin; the proposal was reversed on this evidence.)
