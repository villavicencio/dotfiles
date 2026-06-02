---
title: "Stale dotbot `link:` entries for renamed files break only the macOS CI leg"
date: 2026-06-02
category: cross-machine
tags:
  - dotbot
  - install-matrix
  - ci
  - cross-machine
  - darwin-linux-parity
  - symlinks
  - migration
  - stale-config
severity: High
component: "install.conf.yaml, install-linux.conf.yaml, .github/workflows/install-matrix.yml, claude/commands/"
problem_type: "ci failure / cross-machine config drift"
module: "install pipeline (dotbot)"
related_solutions:
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-r3b-2026-05-06.md — controlled seeded-failure proof of this exact mechanism (a link: entry to a nonexistent target aborting dotbot); this is the real-world incident it predicted"
  - "docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md — dotbot dry-run behavior used in the detection recipe below"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md — why install-linux.conf.yaml exists as a separate config"
---

# Stale dotbot `link:` entries for renamed files break only the macOS CI leg

> Fixed in PR #86. Introduced by commit `3a898a8` ("migrate reddit/twitter/critique to the dv plugin").

## Problem

The macOS leg of the CI install-matrix workflow fails during `./install` — Dotbot aborts with a "nonexistent source" error on three `link:` entries pointing at command files that no longer exist at those paths. The Linux CI leg stays green, masking the breakage entirely.

## Symptoms

- The macOS matrix job fails before exercising the PR under test; `./install` on Linux passes in the same run.
- Dotbot exits with a nonexistent-source error referencing `claude/commands/reddit.md`, `claude/commands/critique.md`, or `claude/commands/twitter.md`.
- `./install` aborts at the first missing source — no later symlinks or shell steps are processed.
- The failure *looks* PR-introduced, but it lives in the base-branch (`master`) macOS config; the PR under test merely inherited it.

## What Didn't Work

- **Treating it as a PR-introduced regression.** The breakage is in the base-branch config. Commit `3a898a8` renamed `claude/commands/{reddit,critique,twitter}.md` to `*.deprecated` (the commands moved to the dv plugin) but left their `link:` entries in `install.conf.yaml` untouched. Diagnosing it against the PR's diff finds nothing.
- **Checking Linux CI to confirm macOS health.** The two platforms use separate Dotbot configs — `install.conf.yaml` (Darwin) and `install-linux.conf.yaml` (Linux), selected by `uname` in the `install` wrapper. The `commands/` link entries exist only in the Darwin config; the Linux config carries none of them. A green Linux run is evidence about the Linux config *only*.

## Solution

PR #86 removed the three stale `link:` entries from `install.conf.yaml`:

```yaml
# removed — these files were renamed to *.deprecated in commit 3a898a8
~/.claude/commands/reddit.md: claude/commands/reddit.md
~/.claude/commands/critique.md: claude/commands/critique.md
~/.claude/commands/twitter.md: claude/commands/twitter.md
```

The `*.deprecated` tombstone files remain in `claude/commands/` (they are tombstones, not live commands). The `~/.claude/commands` directory is still created by Dotbot's `create:` step — a harmless empty dir, no other change needed.

## Why This Works

Dotbot resolves a `link:` directive's **source** path at install time. When the source does not exist, Dotbot treats the entry as an error and aborts the entire run rather than skipping it. Renaming a file that is the *source* of a symlink does not update the Dotbot config that *declares* that symlink — they are two independent places in the repo. Removing the link entries removes the only thing Dotbot checks: whether the declared source exists.

The Linux-passes / macOS-fails split exists because this repo maintains two separate Dotbot configs. Entries in one have no effect on the other, and the CI matrix runs both legs independently — so each leg reports its *own* config's health. A green Linux job is not a proxy for macOS config correctness, and vice versa.

## Prevention

**Rule — update the link entry in the same commit as the file change.** When renaming, moving, or removing any file referenced by a `link:` entry in a Dotbot config, update or delete that entry in the same change. Renaming the file alone silently breaks `./install` on the next run.

**Rule — audit both configs.** Any change to linked files or link entries must be checked against `install.conf.yaml` **and** `install-linux.conf.yaml`. Green CI on one platform does not prove the other is sound — this is the asymmetry that hid the breakage here.

**Local lint recipe** — lists any dangling link sources before you push (run for each config):

```bash
for cfg in install.conf.yaml install-linux.conf.yaml; do
  echo "== $cfg =="
  awk '/^- link:/{f=1;next} /^[^ ]/{f=0} f && /: /{sub(/^[[:space:]]*[^:]*:[[:space:]]*/,"");print}' "$cfg" \
    | while read -r src; do [ -e "$src" ] || echo "MISSING: $src"; done
done
```

**Dry-run recipe** — exercises Dotbot's own source-resolution logic without mutating `$HOME` (`./install --dry-run` is mutation-free per `CLAUDE.md`):

```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c install.conf.yaml --dry-run
find "$FAKE" -mindepth 1 | wc -l   # must stay 0
rm -rf "$FAKE"
```

A non-zero Dotbot exit or a non-zero find count means the config has a dangling source. Re-run with `-c install-linux.conf.yaml` to cover the Linux config.

## Related

- **`docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-r3b-2026-05-06.md`** — the controlled seeded-failure round (issues #60/#61) that deliberately injected a `link:` entry to a nonexistent target and proved Dotbot exits non-zero on it. That was the lab proof; this doc is the real-world incident the guard was built to catch.
- **`docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md`** — dotbot dry-run semantics behind the detection recipe above.
- **`docs/solutions/cross-machine/vps-dotfiles-target.md`** — context for why `install-linux.conf.yaml` exists as a separate (now retired-target) config, and the source of the Darwin/Linux config-parity blind spot.
