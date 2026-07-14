---
title: "A dead Homebrew tap fails `brew bundle` even when nothing installs from it (adoptopenjdk/openjdk)"
date: 2026-07-13
category: cross-machine
tags:
  - homebrew
  - brew-bundle
  - brewfile
  - macos-runner
  - install-matrix
  - dead-tap
  - adoptopenjdk
  - temurin
severity: Medium
component: "brew/Brewfile — orphaned `tap \"adoptopenjdk/openjdk\"` line; macOS leg of the install-matrix CI"
symptoms:
  - "macOS install-matrix leg fails; Linux leg passes"
  - "`Cask 'adoptopenjdk-jre' definition is invalid: undefined method 'appcast' for Cask 'adoptopenjdk-jre'`"
  - "`Tapping adoptopenjdk/openjdk has failed!` followed by `brew bundle failed! N Brewfile dependencies failed to install`"
  - "No `cask \"adoptopenjdk-*\"` line exists in the Brewfile — the failure comes purely from the `tap` line"
problem_type: "Orphaned/dead Homebrew tap whose cask definitions use removed DSL fails `brew tap`, cascading to `brew bundle` and a red CI leg"
module: "install-matrix CI workflow / Brewfile"
related_solutions:
  - "docs/solutions/cross-machine/brew-bundle-parallel-cellar-lock-race-macos-runner-2026-07-13.md — the OTHER macOS-CI failure discovered in the same red run; both had to land together for green master"
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md — the R2/R3/R4 assertion family this manifested under"
---

## TL;DR

`brew/Brewfile` carried `tap "adoptopenjdk/openjdk"` on line 1 — but **no cask installed from it**. AdoptOpenJDK was retired years ago (→ Eclipse Temurin), and one of the tap's casks (`adoptopenjdk-jre`) still uses the `appcast` stanza that modern Homebrew removed from the Cask DSL. `brew tap` is **not inert**: it clones and loads/audits the tap's cask definitions, so the invalid cask makes the whole tap fail to load (`undefined method 'appcast'`), which `brew bundle` counts as a failed dependency → non-zero exit → red macОS CI (and would break a real fresh-machine `./install`). Fix: **delete the orphaned tap line.** Behavior-preserving — no Java was being installed. (PR #96, commit `f94ab5a`.)

## Symptom

The macOS leg of `install-matrix.yml` failed in the `Apply (./install)` step:

```
==> Tapping adoptopenjdk/openjdk
Cloning into '/opt/homebrew/Library/Taps/adoptopenjdk/homebrew-openjdk'...
##[error]Cask 'adoptopenjdk-jre' definition is invalid: undefined method 'appcast' for Cask 'adoptopenjdk-jre'
Tapping adoptopenjdk/openjdk has failed!
...
`brew bundle` failed! N Brewfile dependencies failed to install
Error: Failed to install packages from Brewfile
Command [bash helpers/install_packages.sh] failed
##[error]Process completed with exit code 1.
```

The Linux leg (apt-based, no Homebrew) passed. Critically, **there is no `cask "adoptopenjdk-jre"` or any `adoptopenjdk-*` cask line in the Brewfile** — grepping the whole repo, `tap "adoptopenjdk/openjdk"` (line 1) was the *only* adoptopenjdk reference, present since the original Dotbot conversion (commit `7c05ea9`).

## Root cause

Three compounding facts:

**Fact 1 — `brew tap` loads the tap's cask definitions.** Tapping is not a lazy bookmark. `brew tap adoptopenjdk/openjdk` clones the tap and, on modern Homebrew, parses/audits its formula and cask definitions. If *any* definition is invalid, the tap fails to load — even casks you never intend to install.

**Fact 2 — the `appcast` stanza was removed from the Cask DSL.** AdoptOpenJDK's casks (including `adoptopenjdk-jre`) declared an `appcast "..."` stanza. Homebrew removed `appcast` from the Cask DSL, so loading that cask now throws `undefined method 'appcast'`. The tap has been unmaintained since AdoptOpenJDK migrated to **Eclipse Temurin**, so nothing upstream will fix it.

**Fact 3 — the tap was orphaned in our Brewfile.** No cask in `brew/Brewfile` installed from `adoptopenjdk/openjdk`. The `tap` line was dead weight — it did nothing but attempt (and now fail) the tap on every fresh install. `brew bundle` treats a failed `tap` as a failed dependency and exits non-zero.

So a line that installed nothing, and had installed nothing for as long as it existed, became a hard failure the moment Homebrew tightened its Cask DSL — silently, on an unrelated commit.

## Fix

Delete the orphaned tap line from `brew/Brewfile`:

```diff
-tap "adoptopenjdk/openjdk"
 tap "rigellute/tap"
 brew "ack"
```

**Behavior-preserving:** no Java was being installed from this tap, so removal changes nothing about what lands on a machine — it only stops the failed `brew tap` attempt. If a JDK/JRE is ever wanted, add it deliberately with the modern successor:

```ruby
cask "temurin"   # Eclipse Temurin — successor to AdoptOpenJDK
```

## The general lesson: orphaned taps are latent landmines

A `tap` line with no corresponding `brew`/`cask` entry is not harmless. It's a standing dependency on a third-party tap's *entire* definition set staying DSL-valid forever. When the tap goes unmaintained and Homebrew evolves its DSL, the tap breaks and takes `brew bundle` down with it — on a commit that never touched the Brewfile. **Audit for orphaned taps:** every `tap "..."` line should have at least one `brew`/`cask` that needs it; if not, delete it.

(While here, `tap "rigellute/tap"` is also orphaned — nothing in the Brewfile installs from it. It currently taps cleanly so it wasn't in scope for the CI fix, but it's the same class of latent risk. Left as-is intentionally; remove if it ever breaks.)

## Sites

- `brew/Brewfile:1` — the removed `tap "adoptopenjdk/openjdk"` line (gone as of `f94ab5a`)
- `helpers/install_from_brewfile.sh` — runs `brew bundle --file=./brew/Brewfile`; a failed tap here fails the whole install step
- `.github/workflows/install-matrix.yml` — macOS leg `Apply (./install)` step where it surfaced

## Verification

After removal, PR #96's macOS CI showed the `adoptopenjdk`/`appcast` error **gone entirely** and the `brew bundle` failure count dropped from 3 to 2 (the remaining 2 were a separate, unrelated Cellar lock-race — see the related doc). Once both fixes landed on master, the full install-matrix (linux + macOS) went green.

Local reproduction of the failure mode (do NOT run on a machine you care about — it clones a dead tap):

```bash
brew tap adoptopenjdk/openjdk   # → "undefined method 'appcast'" / "Tapping ... has failed!"
brew untap adoptopenjdk/openjdk # clean up
```
