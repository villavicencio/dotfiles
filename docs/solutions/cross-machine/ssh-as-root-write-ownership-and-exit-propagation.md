---
title: "ssh-as-root writes to container-shared volumes: first-write ownership trap and `find -exec` exit-code suppression"
date: 2026-04-27
category: cross-machine
tags:
  - ssh
  - vps
  - openclaw
  - forge
  - permissions
  - chown
  - find
  - exit-code
  - exec
  - container-volumes
  - shell-pitfalls
severity: Medium
component: "claude/commands/handoff.md, claude/commands/pickup.md — every ssh-as-root write to /var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/"
symptoms:
  - "Forge agent (running as node, uid 1000 inside the container) silently fails to update a project file (`cadence-log.md`, `pending/done/<ticket>.md`) that the dotfiles host wrote first"
  - "`ls -la` on the host shows the offending file owned by `root:root` even though every other file in the directory is `1000:1000`"
  - "An `&&` chain like `mv ... && chown ...` in an ssh-as-root one-liner returns success even when the `mv` failed, because a downstream command (here, `chown`) succeeded and overwrote the failure exit code"
  - "`find -exec mv {} \\;` masks the mv's exit code entirely — find returns its own success even when every individual mv invocation failed"
  - "The `.forge-pending` fallback in `/handoff` Step 5 never fires despite an actual append failure, because the failure was swallowed by the chown that ran after it"
problem_type: "permissions trap + exit-code suppression in ssh one-liners"
module: "cross-machine SOP shell scripts"
related_solutions:
  - "docs/solutions/cross-machine/vps-dotfiles-target.md — VPS bridge runbook that owns these ssh-as-root call sites"
  - "docs/solutions/cross-machine/tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md — adjacent Tailscale/SSH learning"
---

# ssh-as-root writes to container-shared volumes: ownership trap and exit-code suppression

Two defects in the same class — both invisible until they aren't, both fixed across PRs #48 / #51 / #53 — that any future ssh-as-root write to a container-shared volume must defend against.

## Defect A — The first-write ownership trap

### Symptom

The Forge agent (running as `node`, uid 1000, inside the openclaw container) silently fails to update a project file that the dotfiles host wrote first via ssh:

```
$ docker exec -u node openclaw-... touch /workspace-forge/projects/dotfiles/cadence-log.md
touch: cannot touch '/workspace-forge/projects/dotfiles/cadence-log.md': Permission denied
```

`ls -la` on the host:

```
-rw-r--r-- 1 root root 6079 Apr 24 18:19 cadence-log.md
                ^^^^ ^^^^   ← every other file in this dir is 1000:1000
```

Forge's container UID (1000) cannot write a root-owned file. The dotfiles `/handoff` SOP keeps appending to it from the host (uid 0 over ssh) without trouble, so nobody notices until Forge tries.

### Root cause

`ssh root@openclaw-prod 'cat >> /var/lib/.../cadence-log.md'` does two distinct things on the very first invocation against an absent path:

1. The shell-redirection operator `>>` **creates the file if it does not exist**, with the effective uid of whoever ran the redirect. Over ssh-as-root, that's uid 0.
2. `cat` then writes content to the now-root-owned fd.

Subsequent invocations are appends to an existing file, and ownership of an existing file is *preserved* across writes. So the bug only fires once per target — silently, with no failure signal — and then sits dormant until a different writer (the in-container Forge agent) tries to touch it.

This is the trap: every site that does `ssh root@host '... >> $FILE'` against a path that *might not exist yet* is a latent first-write ownership bomb.

### Compare to the path that *worked*

`workspace-forge/projects/openclaw-forge/cadence-log.md` was `1000:1000` on the host the whole time — not because the ssh SOP got it right, but because the openclaw container agent happened to touch it first. Pure ordering luck.

`workspace-forge/projects/dotfiles/cadence-log.md` had no in-container writer that came first, so the host-side ssh SOP won the first-write race and the file froze as root-owned.

### Fix — establish the invariant on every write

Trailing-`chown 1000:1000` after every ssh-as-root write to a container-shared volume:

```bash
ssh root@openclaw-prod 'DEST=/var/lib/.../cadence-log.md; cat >> "$DEST" && chown 1000:1000 "$DEST"'
```

The chown is a no-op when ownership is already correct, and self-healing when it has drifted. It costs nothing and turns a class of latent ownership traps into a property that holds by construction.

Same pattern for directory creation via `mkdir -p`:

```bash
ssh root@host "mkdir -p $DIR && ... && chown -R 1000:1000 $DIR"
```

The `-R` matters because `mkdir -p` may create multiple intermediate dirs, all of which inherit root ownership.

### Sites where this is now invariant

- `claude/commands/handoff.md:111` — Step 5.3 `_shared/*.md` write-back
- `claude/commands/handoff.md:129` — Step 5.5 Forge-bridge sync log to `shared/comms/`
- `claude/commands/handoff.md:164` — Step 6.2 cadence-log append
- `claude/commands/pickup.md:94` — Step 2c Forge inbox archival
- `claude/commands/pickup.md:110` — Step 2c pending-ticket archival into `pending/done/`

## Defect B — Exit-code suppression in `&&` chains and `find -exec`

The fix for Defect A introduces a second pitfall, because every chown sits *downstream* of the actual write.

### Symptom

```bash
ssh root@host 'cat >> "$DEST"; chown 1000:1000 "$DEST"'
```

If `cat >>` fails (disk full, permission denied, file locked) and `chown` succeeds, the ssh command returns 0. The append failure is silently swallowed. Any caller that branches on `$?` to fire a fallback (e.g. `/handoff` Step 4 writing `.forge-pending` on append failure) never sees the failure and never fires the fallback.

The bug feels obvious in isolation — it's basic POSIX semantics — but it sneaks back in every time someone writes a one-liner that does "the work, then a side-effect cleanup."

### Root cause

A semicolon between commands runs them sequentially and returns the **last** command's exit code. The earlier failure is overwritten.

`&&` instead returns the first failure's exit code and short-circuits subsequent commands. When you want failure to *propagate* — and you usually do, because the caller's failure handling depends on it — `&&` is the right operator.

### Fix

```bash
# WRONG — chown's success masks cat's failure
ssh root@host 'cat >> "$DEST"; chown 1000:1000 "$DEST"'

# RIGHT — failure of cat propagates; chown still runs only on success
ssh root@host 'cat >> "$DEST" && chown 1000:1000 "$DEST"'
```

This was the whole story of PR #53: three lines flipped from `;` to `&&` in `claude/commands/handoff.md`, which is what makes the `.forge-pending` fallback in `/handoff` Step 4 actually fire when an append fails.

### The `find -exec` variant of the same pitfall

`find -exec CMD {} \;` (semicolon form) silently discards CMD's exit code. Find returns its own success based on whether the find walk succeeded — not whether any of the exec'd commands did.

```bash
# WRONG — every mv could fail and find still returns 0
find $INBOX -name '*.md' -exec mv {} $ARCHIVE \;
```

The fix is `+` form, which aggregates all matched paths into a single CMD invocation and propagates that CMD's exit code:

```bash
# RIGHT — mv's exit code becomes find's exit code
find $INBOX -name '*.md' -exec mv -t $ARCHIVE {} +
```

Note the `mv -t DEST {}` shape: the `-t` flag tells mv that the next arg is the destination (so all the trailing `{}`-substituted source paths can be passed as one batch). Without `-t`, the plus-form expansion produces `mv src1 src2 ... srcN destdir` which mv interprets correctly anyway, but `-t` makes the intent explicit and survives a destination that contains a space.

This was caught by reviewer P2 on PR #51 — the original `find -exec mv {} \;` looked correct and was inside an `&&` chain that *would* have propagated, but the `\;` form swallowed mv's exit before it ever reached the `&&`.

## The compound failure mode

The two defects collide in any ssh-as-root write that does *both* a stage-then-cleanup chain and a find walk:

```bash
# WRONG — two layers of exit-code suppression
ssh root@host "find $INBOX -name '*.md' -exec mv {} $ARCHIVE \; ; chown -R 1000:1000 $ARCHIVE"
```

The `\;` swallows mv's failure. The `;` between the find and the chown swallows whatever the find returned. The chown succeeds. The whole ssh returns 0. Every file in the inbox failed to move and you have no idea.

Fixed shape:

```bash
ssh root@host "find $INBOX -name '*.md' -exec mv -n -t $ARCHIVE {} + && chown -R 1000:1000 $ARCHIVE"
```

`+` propagates mv's exit through find. `&&` propagates find's exit through to ssh. The chown runs only on success and self-heals ownership when it does.

(`-n` on mv = no-clobber, separate concern: makes the move idempotent when the same archival runs twice.)

## Invariants for future ssh-as-root sites

When adding any new `ssh root@openclaw-prod '...'` call site that writes to `/var/lib/docker/volumes/...`:

1. **Trailing-chown every write.** Files: `chown 1000:1000 "$DEST"`. Directories created by `mkdir -p`: `chown -R 1000:1000 "$DEST"`. No-op when correct, self-healing when drifted.
2. **Use `&&` between work and cleanup**, never `;`. The cleanup is *contingent on* the work succeeding, and you need the work's failure exit to reach the caller.
3. **Use `find -exec CMD ... {} +`**, never `\;`, when failure must propagate. Pair with `mv -t DEST` for the canonical batch-move shape.
4. **Treat `mkdir -p` as a write.** It creates intermediate dirs as the ssh session's uid (root). Trailing-chown the leaf path with `-R`.

## Why this catches a real failure mode and not a hypothetical one

The trigger that surfaced Defect A was the multi-day session straddling 2026-04-24 → 2026-04-26: dotfiles' `/handoff` SOP wrote `cadence-log.md` for the dotfiles project before any in-container Forge agent had touched it, freezing it as root-owned. Forge then couldn't update it, and the bug stayed silent until a Forge inbox message tried to land in dotfiles' project log.

The trigger that surfaced Defect B was PR #51 review — reviewer noticed the `find -exec ... \;` shape inside an `&&` chain and asked whether the chain would actually short-circuit on mv failure. Empirical answer was no, the `\;` form swallowed the failure before it ever reached the `&&`. Same review caught a sibling `;`-vs-`&&` defect at handoff.md:108 and :151 (the Step 5.3 / Step 6.2 sites that became PR #53), which were inside #48's diff and missed at #48 review time.

Both defects are easy to ship: each one *looks* correct under casual reading, and each one gives you a green checkmark on the smoke test (the work usually succeeds, the cleanup usually succeeds, the exit usually returns 0). They only show up under the failure mode you weren't testing — which is exactly when you most need the exit code to be honest.

## Verification recipe

Smoke-test the trailing-chown invariant on a throwaway path:

```bash
ssh root@openclaw-prod '
  T=/tmp/ownership-test-$$
  echo "first" > "$T" && chown 1000:1000 "$T"
  ls -la "$T"
  echo "second" >> "$T" && chown 1000:1000 "$T"
  ls -la "$T"
  rm "$T"
'
```

Both lines should show `1000 1000`.

Smoke-test the `+` form vs `\;` form:

```bash
mkdir -p /tmp/exit-test/{src,dst}
touch /tmp/exit-test/src/file
chmod 0 /tmp/exit-test/dst   # make mv fail

# semicolon form: expect 0 (BAD — masks failure)
find /tmp/exit-test/src -type f -exec mv {} /tmp/exit-test/dst \;
echo "exit (semicolon): $?"

# plus form: expect non-zero (GOOD — propagates)
find /tmp/exit-test/src -type f -exec mv -t /tmp/exit-test/dst {} +
echo "exit (plus): $?"

chmod 755 /tmp/exit-test/dst && rm -rf /tmp/exit-test
```

## Cross-project reach

The `_shared/patterns.md` file on the openclaw VPS already carries the one-liner version of both learnings (entries dated 2026-04-24 and 2026-04-26, sourced to dotfiles#47 and dotfiles#51 review). This document is the long-form companion: when a future `/pickup` surfaces a permission-denied error in a Forge project log, this is the page to read for the why and the prevention pattern.

PRs that established the invariant: #48, #49, #51, #53. Issues closed: gh#47, gh#50, gh#52.
