---
title: "actions/checkout writes a regular ~/.gitconfig that Dotbot's relink: true won't replace"
date: 2026-05-04
category: cross-machine
tags:
  - github-actions
  - actions-checkout
  - dotbot
  - install-matrix
  - gitconfig
  - relink
  - first-write-trap
severity: Medium
component: ".github/workflows/install-matrix.yml — Linux + macOS legs, the `Clean actions/checkout side effects in $HOME` step"
symptoms:
  - "`./install` aborts on the `~/.gitconfig: git/gitconfig` link entry with: `already exists but is not a symlink (delete it manually first or set `relink: true`)`"
  - "`relink: true` does not unblock it — the apply step fails with the same message even though Dotbot is supposed to replace existing links"
  - "`ls -l ~/.gitconfig` shows a regular file, not a symlink, on the runner"
problem_type: "actions/checkout side effect collides with Dotbot link semantics"
module: "install-matrix CI workflow"
related_solutions:
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md — companion validation evidence for the same workflow"
---

## TL;DR

`actions/checkout` writes a **regular file** at `$HOME/.gitconfig` during its setup phase (it persists `safe.directory` settings into the runner's home). Dotbot's `relink: true` only replaces existing **symlinks**, not regular files. The install step then aborts on the `~/.gitconfig: git/gitconfig` link entry. Fix: `rm -f "$HOME/.gitconfig"` after checkout and before `./install`. The same trap also affects `safe.directory` writes — keep them at `--system` scope, not `--global`.

## Symptom

Both legs of `install-matrix.yml` failed at the apply step (`./install`) with the same message:

```
ERROR: ~/.gitconfig: already exists but is not a symlink — set `relink: true` to replace
```

`relink: true` is set on that link entry. Adding it didn't help. Dotbot's link plugin is intentionally conservative: it will replace a *symlink* it owns, but it will not silently delete a *regular file* that the user (or the environment) has put in place — that's data the user might not want destroyed. See `dotbot/src/dotbot/plugins/link.py` `_link()` flow: `relink=True` triggers `_unlink()` only when the existing path `os.path.islink()` is true.

## Root cause

`actions/checkout@v4` configures git auth/safe.directory by writing a **regular** `$HOME/.gitconfig`. Visible in the post-step cleanup log line:

```
Copying '/github/home/.gitconfig' to '/__w/_temp/<...>'
```

(checkout's "Restore the cached HOME directory" subroutine — it backs up its own `$HOME/.gitconfig` so a *next* checkout step in the same run can restore it cleanly.) The file ends up on the runner before Dotbot ever runs.

This is a regular file, not a symlink — `actions/checkout` doesn't know or care that the user's eventual install pipeline expects `~/.gitconfig` to be a symlink to `git/gitconfig`. From its perspective the file is its own scratch state.

When Dotbot then walks the link directives in `install.conf.yaml` and gets to:

```yaml
- link:
    ~/.gitconfig: { path: git/gitconfig, relink: true, force: false }
```

it sees a regular file at `$HOME/.gitconfig`. `relink: true` only handles the symlink-replacement case. `force: true` *would* clobber a regular file, but enabling it globally is the wrong fix — it sacrifices the safety property on every machine that runs `./install`, just to paper over a CI-only side effect.

## Fix

Remove `$HOME/.gitconfig` explicitly between checkout and apply:

```yaml
- name: Checkout
  uses: actions/checkout@<sha>

- name: Clean actions/checkout side effects in $HOME
  run: rm -f "$HOME/.gitconfig"

- name: Apply (./install)
  run: ./install
```

Both legs of `install-matrix.yml` carry this step. The `-f` matters because the file may not exist on a future runner image revision — checkout's behavior here is implementation detail, not contract — and a hard error on a missing file would red-CI the workflow on the *next* runner-image rotation that drops the side effect.

## The companion trap: `safe.directory` scope

The Linux container leg also needs `git config --add safe.directory $GITHUB_WORKSPACE` so the install pipeline's `git submodule update --init --recursive` doesn't trip on "fatal: detected dubious ownership in repository" (the workspace is owned by the host's actions-runner uid, not the container's root uid).

`--global` writes `$HOME/.gitconfig`. The `rm -f $HOME/.gitconfig` step *after* the safe.directory step would then nuke the very setting we just added, and the apply step would fail again with dubious-ownership.

Fix: write to `--system` scope (`/etc/gitconfig`) which lives outside `$HOME` and survives the cleanup:

```yaml
- name: Mark workspace safe for git inside container
  run: git config --system --add safe.directory "$GITHUB_WORKSPACE"

- name: Clean actions/checkout side effects in $HOME
  run: rm -f "$HOME/.gitconfig"
```

This is only needed for the Linux container leg. macOS-15 runs as the runner user, where actions/checkout's safe.directory setup is sufficient and dotbot doesn't trip on submodule ownership.

## Why not `force: true` in install.conf.yaml

Tempting, and wrong. `force: true` tells Dotbot to delete *any* existing path at the link target — symlink, regular file, or directory — before linking. Enabling that on `~/.gitconfig` means every `./install` on every machine silently nukes whatever the user had at that path. The whole point of the `relink: true` / `force: false` split is "replace links you already own, but never silently destroy a user's regular file." That guarantee is worth preserving across all consumers of `install.conf.yaml`. Solve the problem at the workflow level (delete the *known-CI-specific* file before applying), not at the dotfiles-config level.

## Why not avoid the side effect entirely

`actions/checkout` does not expose a flag to suppress the `$HOME/.gitconfig` write. The `persist-credentials: false` option only controls auth credential persistence; safe.directory state still gets written. Working around it by setting `HOME=$RUNNER_TEMP/...` for the checkout step has its own footguns (every subsequent step would inherit the override, and you'd need to reset it back, etc.). The `rm -f` is the cheapest and most local fix.

## Detection / future-proofing

If a future runner image, checkout-action major version, or Dotbot version changes the underlying behavior, the apply step itself will surface the regression — Dotbot's error message names the exact path. There's no silent-failure mode here; the assertion shows up loudly at the right step. So the `rm -f "$HOME/.gitconfig"` step can stay as documented preventative cleanup without need for a separate sentinel check.

The R3 assertions don't need to know about this — they run against the dry-run output, which doesn't actually create symlinks (so doesn't trip the regular-file collision).

## Sites where this pattern lives

- `.github/workflows/install-matrix.yml` Linux leg, between `Mark workspace safe` and `Apply`
- `.github/workflows/install-matrix.yml` macOS leg, between `R2 + R3` and `Apply` (no `safe.directory` step — actions/checkout already configures the runner-user equivalent)

Both step bodies are duplicated across legs and tracked under issue #59 (extract install-matrix duplicated step bodies into a composite action).
