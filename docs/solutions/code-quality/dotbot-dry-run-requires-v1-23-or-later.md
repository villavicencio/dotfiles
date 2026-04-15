---
title: "Dotbot's `--dry-run` flag requires vendored submodule ≥ v1.23.0"
date: 2026-04-15
category: code-quality
tags:
  - dotbot
  - dry-run
  - submodule
  - bug-fix
  - deploy
  - dotfiles
severity: Medium
component: "dotbot submodule, install wrapper, any pipeline passing --dry-run through Dotbot"
symptoms:
  - "`./install --dry-run` exits with `dotbot: error: unrecognized arguments: --dry-run`"
  - "`./install --dry-run` silently mutates a fresh HOME (creates real symlinks + directories) instead of previewing"
  - "Helper scripts honor DOTFILES_DRY_RUN but Dotbot's built-in `link`/`create`/`clean` directives still execute for real"
  - "Plan documented that dry-run was safe; reviewer reproduced mutations on a fresh $HOME"
related_issues:
  - "PR #22 VPS dotfiles sync target review — 2026-04-15"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md (consumer of --dry-run behavior)"
  - "Upstream Dotbot commit 67aeaf7 'Add support for dry run' — landed in v1.23.0"
status: Resolved
---

# Dotbot's `--dry-run` flag requires vendored submodule ≥ v1.23.0

## Symptom

A dotfiles repo using Dotbot (via a pinned submodule) documents
`./install --dry-run` as a safe preview of what the installer would do.
Two failure modes depending on how the wrapper is written:

**Failure A — visible error:** if the wrapper passes `--dry-run` straight
through, invocation fails loudly:

```
dotbot: error: unrecognized arguments: --dry-run
```

**Failure B — silent mutation:** if the wrapper strips `--dry-run` and
relies on Dotbot's built-in idempotency to make link/create/clean safe,
the claim holds on an **already-bootstrapped host** (symlinks already
exist, Dotbot no-ops) but **fails silently on a fresh host**. The
"dry-run" creates real directories and real symlinks.

Both outcomes break the preview contract the repo documents.

## Reproduction

Fresh home directory, forced Linux config:

```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c install-linux.conf.yaml --dry-run 2>&1 | head -5
```

- On Dotbot **< v1.23.0:** `dotbot: error: unrecognized arguments: --dry-run`.
- On Dotbot **≥ v1.23.0:** emits "Would create path …" / "Would create
  symlink …" lines; `find "$FAKE" -mindepth 1 | wc -l` = 0 (truly
  mutation-free).

The wrapper-strips-flag workaround fails even more quietly:

```bash
# wrapper.sh that strips --dry-run before invoking old Dotbot:
FAKE=/tmp/dotbot-strip-$$; mkdir -p "$FAKE"
HOME="$FAKE" ./install --dry-run
find "$FAKE" -mindepth 1 | head
# Directories + symlinks created. dry-run was a lie.
```

## Root cause

Upstream Dotbot commit [`67aeaf7`](https://github.com/anishathalye/dotbot/commit/67aeaf7)
("Add support for dry run") landed in release **v1.23.0**. Prior releases
have no such flag; the built-in `link` / `create` / `clean` / `shell`
plugins always execute unconditionally.

Many dotfile repos vendor Dotbot as a git submodule and never bump it.
If the submodule was pinned several years ago, it predates native dry-run
support. The repo's `./install --dry-run` convention then becomes either
(a) broken and loud, or (b) "idempotent no-op" reasoning that silently
fails on fresh bootstrap.

### Why the idempotent-no-op reasoning is wrong

"Dotbot's `relink: true` makes link/create/clean idempotent no-ops on
re-run, so dry-run = safe preview" is **true for steady-state hosts**:
the symlinks already point where Dotbot wants them, no mutation occurs.

It is **false for fresh-host bootstrap**, which is exactly the path
operators use to *validate* a new target machine. On a fresh `HOME`,
Dotbot creates directories and symlinks — that IS mutation. Any doc
claiming dry-run safety without qualification will mislead.

## Fix

Two-part: bump the submodule, then correct the wrapper.

### 1. Bump the Dotbot submodule

```bash
cd dotbot
git fetch --tags
git checkout v1.24.1        # or any tag >= v1.23.0
git submodule update --init --recursive
cd ..
git add dotbot              # pin the parent repo's index to the new SHA
```

Commit this as a distinct change from functional edits.

Verify:

```bash
./dotbot/bin/dotbot --help 2>&1 | grep dry-run
# → -n, --dry-run    print what would be done, without doing it
```

### 2. Correct the wrapper to pass `--dry-run` through

Old shape (strip and rely on idempotency) — **do not use**:

```bash
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ]; then
    export DOTFILES_DRY_RUN=1
    # intentionally drop from args — idempotent no-op assumption (WRONG)
  else
    NEW_ARGS+=("$arg")
  fi
done
exec ./dotbot/bin/dotbot -d "$BASEDIR" -c "$CONFIG" "${NEW_ARGS[@]}"
```

New shape (pass through + keep env var as defense-in-depth):

```bash
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
    export DOTFILES_DRY_RUN=1
    break
  fi
done
exec ./dotbot/bin/dotbot -d "$BASEDIR" -c "$CONFIG" "$@"
```

Rationale:

- Dotbot's native `--dry-run` covers all built-in directives
  (link/create/clean/shell) and emits clean "Would create …" preview
  lines.
- `DOTFILES_DRY_RUN=1` still propagates to helper scripts — useful when
  someone invokes a helper directly (`bash helpers/install_omz.sh`)
  outside Dotbot, where Dotbot's dry-run can't reach.
- With Dotbot-native dry-run skipping the `shell:` plugin entirely, the
  env-var guards in helpers become defense-in-depth rather than the
  primary mechanism.

## Verification

After both changes:

```bash
FAKE=/tmp/dotbot-dryrun-post-$$; mkdir -p "$FAKE"
HOME="$FAKE" ./install --dry-run >/tmp/dryrun.log
find "$FAKE" -mindepth 1 | wc -l           # must be 0
grep -c "^Would " /tmp/dryrun.log          # should be > 0
rm -rf "$FAKE"
```

Also test the already-bootstrapped case doesn't regress:

```bash
# On your real $HOME (already set up):
find ~/.config ~/.claude ~/.hushlogin ~/.gitconfig ~/.zshenv -type l 2>/dev/null | sort > /tmp/before.txt
./install --dry-run >/dev/null
find ~/.config ~/.claude ~/.hushlogin ~/.gitconfig ~/.zshenv -type l 2>/dev/null | sort > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt        # empty = dry-run mutation-free
```

## Prevention strategies

1. **Periodically bump vendored tool submodules.** Pin-and-forget works
   until a feature lands upstream that your docs now promise. Quarterly
   or annual audit of submodule versions catches this.
2. **Never claim dry-run semantics you haven't tested on a fresh
   environment.** On a steady-state machine, bugs hide. Dry-run claims
   should be verified against an empty `HOME` or scratch VM.
3. **On any Dotbot submodule bump, re-run the fresh-HOME dry-run
   verification.** Bake it into CLAUDE.md / README for future edits.
4. **Prefer passing tool flags through over reimplementing their
   semantics in your wrapper.** If you catch yourself building a
   `--dry-run` implementation in a wrapper script because the underlying
   tool doesn't support one yet, assume upstream has shipped or will
   ship native support — check first.

## Related

- [VPS dotfiles sync target](../cross-machine/vps-dotfiles-target.md) —
  consumer of the dry-run contract; ran into this during PR #22 review.
- Upstream: [Dotbot v1.23.0 release notes](https://github.com/anishathalye/dotbot/releases/tag/v1.23.0).
- Upstream commit: [`67aeaf7` "Add support for dry run"](https://github.com/anishathalye/dotbot/commit/67aeaf7).

## Sources

- PR #22 reviewer repro on fresh `HOME=/tmp/...` — 2026-04-15.
- Dotbot CLI `--help` output on v1.24.1 confirming `-n, --dry-run`.
- Dotbot git log grep for "dry" surfacing `67aeaf7` and its release tag.
