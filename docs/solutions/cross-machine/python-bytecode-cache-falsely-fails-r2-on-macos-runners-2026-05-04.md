---
title: "PYTHONDONTWRITEBYTECODE is required when $GITHUB_WORKSPACE is inside $HOME (macos-15 runners)"
date: 2026-05-04
category: cross-machine
tags:
  - github-actions
  - macos-runner
  - python
  - bytecode
  - dotbot
  - pyyaml
  - install-matrix
  - r2-assertion
severity: Medium
component: ".github/workflows/install-matrix.yml — workflow-level `env:` block + R2 (mutation-free dry-run) assertion on the macOS leg"
symptoms:
  - "R2 assertion fails on the macOS leg only — Linux container leg passes"
  - "Delta-diff shows new entries under `dotbot/lib/pyyaml/__pycache__/` and `dotbot/src/dotbot/__pycache__/` (e.g. `__init__.cpython-313.pyc`, `loader.cpython-313.pyc`)"
  - "Re-running the same dry-run twice in a row from the same checkout still fails — bytecode is regenerated each run because $HOME (and therefore the workspace, on macOS) is fresh per job"
problem_type: "Python bytecode cache leaks into $HOME on macOS runners; absent on Linux containers"
module: "install-matrix CI workflow"
related_solutions:
  - "docs/solutions/cross-machine/actions-checkout-leaves-regular-gitconfig-2026-05-04.md — sibling macOS-vs-container divergence on the same workflow"
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md — R2/R3/R4 assertion family this docs an edge case of"
---

## TL;DR

`./install --dry-run` invokes Dotbot, which is a Python script that imports pyyaml at startup. Python writes `__pycache__/*.pyc` next to the imported source. On macos-15 runners, `$GITHUB_WORKSPACE = /Users/runner/work/<repo>/<repo>` lives **inside** `$HOME = /Users/runner` — so those .pyc writes show up as new entries under `$HOME` and falsely fail R2 (the mutation-free dry-run assertion). On Linux containers, `$HOME = /github/home` (or `/root`) and the workspace is at `/__w/...` — outside `$HOME` — so the leak is invisible. Fix: set `PYTHONDONTWRITEBYTECODE=1` at workflow `env:` level. Cheap, zero-runtime-cost, applies to both legs uniformly.

## Symptom

R2 — the assertion that `./install --dry-run` mutates nothing under `$HOME` — failed on the macOS leg with:

```
< /Users/runner/work/dotfiles/dotfiles/dotbot/lib/pyyaml/__pycache__
< /Users/runner/work/dotfiles/dotfiles/dotbot/lib/pyyaml/__pycache__/__init__.cpython-313.pyc
< /Users/runner/work/dotfiles/dotfiles/dotbot/src/dotbot/__pycache__
< /Users/runner/work/dotfiles/dotfiles/dotbot/src/dotbot/__pycache__/__init__.cpython-313.pyc
< /Users/runner/work/dotfiles/dotfiles/dotbot/src/dotbot/__pycache__/cli.cpython-313.pyc
...
##[error]dry-run mutated $HOME
```

(The `<` lines are post-snapshot entries absent from pre-snapshot — i.e., things the dry-run created.)

The Linux container leg passed the same assertion, same code, same Dotbot version.

## Root cause

Two compounding facts:

**Fact 1 — Dotbot is Python.** `./install` invokes `dotbot/bin/dotbot`, which is a Python entry point. Dotbot imports pyyaml at module-load time. CPython writes bytecode caches (`__pycache__/<module>.cpython-<ver>.pyc`) next to the source files of any module it imports, by default. This is normal Python behavior and harmless in isolation — the cache speeds up subsequent imports.

**Fact 2 — macOS runner $HOME contains $GITHUB_WORKSPACE.** On `macos-15` runners:

| | macos-15 | Linux container |
|---|---|---|
| `$HOME` | `/Users/runner` | `/github/home` (root) or `/root` |
| `$GITHUB_WORKSPACE` | `/Users/runner/work/<repo>/<repo>` | `/__w/<repo>/<repo>` |
| Workspace under $HOME? | **yes** | **no** |

Dotbot's `__pycache__` writes happen inside the workspace (next to the imported `pyyaml/` and `dotbot/` source dirs). On macOS that's inside `$HOME`. On Linux containers it's not. So the same dry-run produces the same .pyc files in both environments, but only the macOS leg's `$HOME`-snapshot picks them up.

This is exactly the cross-platform divergence class that R2 is supposed to catch — except in this case the "mutation" is harmless transient bytecode, not a real install-pipeline bug.

## Why pruning `$HOME/work` isn't the only fix needed

The R2 snapshot helper already prunes some runner-noise subtrees:

```bash
snapshot_home() {
  find "$HOME" -mindepth 1 \
    \( -path "$HOME/actions-runner" -o -path "$HOME/work" -o -path "$HOME/Library" \) -prune \
    -o -print 2>/dev/null \
    | sort
}
```

`$HOME/work` does cover the workspace dir on macOS (since `$GITHUB_WORKSPACE = $HOME/work/...`), so in the current shape of the helper, `__pycache__` writes inside the workspace *would* be pruned. **But that's belt-and-suspenders coexistence, not redundancy.** Two reasons to keep `PYTHONDONTWRITEBYTECODE=1` regardless:

1. **The flag is the actual fix; the prune is for unrelated noise.** PYTHONDONTWRITEBYTECODE landed first (commit `f59851a`, "suppress .pyc writes"). The runner-noise prune landed later (commit `703e865`) for a different problem entirely — actions-runner's `_diag/` log rotation and `Library/` cache churn during the dry-run. They evolved independently to fix independent regressions. Removing PYTHONDONTWRITEBYTECODE would re-introduce the original bug at every prune-list change that isn't paired with re-validating Python behavior.
2. **The prune list is hand-maintained scope; the env flag is install-pipeline-truth.** A future refactor that drops `$HOME/work` from the prune list (say, because someone adds tighter scoping per macOS path layout) would silently re-expose .pyc writes. The env flag is invariant: as long as Dotbot is Python, the flag suppresses the writes everywhere, no scope-list to drift.

The same reasoning applies in reverse — the prune covers cases the env flag can't (e.g., actions-runner's own `_diag/` writes during the dry-run window). Both protections cover different failure modes.

## Fix

Set the env var at workflow scope so both legs inherit it:

```yaml
env:
  PYTHONDONTWRITEBYTECODE: '1'

jobs:
  linux: { ... }
  macos: { ... }
```

The flag tells CPython to skip writing `.pyc` files entirely. Modules import slightly slower on the second invocation (no cache to load from), but Dotbot only runs twice per CI run (once for `--dry-run`, once for `./install`), so the cost is negligible. No behavior changes — Python works fine without bytecode caches.

This is one of the rare workflow-`env:` settings that should genuinely be at workflow level, not job level: it applies to every Python invocation in every step in every leg, and the *intent* is "this is install-pipeline policy," not "this is one job's quirk."

## What this catches that the prune doesn't

- Future Python tools added to the install pipeline (e.g., a helper that imports `requests`) would also skip bytecode under PYTHONDONTWRITEBYTECODE, even if they import from a path outside `$HOME/work`.
- Any path where Python writes `__pycache__/` outside the prune list — e.g., a dotbot plugin that imports a sibling module from `~/.config/...` — wouldn't trip R2.

## What the prune catches that this doesn't

- actions-runner's own background log rotation under `$HOME/actions-runner/_diag/`.
- macOS background services rotating caches under `$HOME/Library/Caches/`.
- Anything else GitHub's runner agents write into `$HOME` during the dry-run window that isn't a Python bytecode artifact.

So both protections coexist in the current workflow as intentional defense-in-depth. Don't remove either when refactoring for issue #59 (composite-action extraction).

## Sites

- `.github/workflows/install-matrix.yml:93-94` — workflow-level `env:` block declaring `PYTHONDONTWRITEBYTECODE: '1'`
- `.github/workflows/install-matrix.yml` `snapshot_home()` helper — prune list (duplicated across legs; tracked under #59)

## Verification

To reproduce locally: `cd` into a fresh clone, ensure `$HOME` and the clone are on the same volume layout as `macos-15` (workspace inside `$HOME`), then:

```bash
unset PYTHONDONTWRITEBYTECODE
find "$HOME" -path "$HOME/actions-runner" -prune -o -path "$HOME/work" -prune -o -print | sort > /tmp/pre
./install --dry-run > /dev/null
find "$HOME" -path "$HOME/actions-runner" -prune -o -path "$HOME/work" -prune -o -print | sort > /tmp/post
diff /tmp/pre /tmp/post
```

If the workspace is *not* under `$HOME`, the diff is empty (Linux-container case). If it is and you remove the prune, the diff shows the `__pycache__/*.pyc` adds. Re-run with `PYTHONDONTWRITEBYTECODE=1` exported: diff is empty regardless of layout.
