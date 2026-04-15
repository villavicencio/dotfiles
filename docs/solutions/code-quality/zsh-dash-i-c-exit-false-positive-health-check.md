---
title: "`zsh -i -c exit` is a false-positive health check"
date: 2026-04-15
category: code-quality
tags:
  - zsh
  - health-check
  - smoke-test
  - deploy
  - bug-fix
  - cross-platform
severity: High
component: "scripts/post-deploy-smoke.sh, any shell init health check"
symptoms:
  - "Deploy workflow's health check fails with exit 1 even though zsh inits successfully"
  - "`zsh -i -c exit` returns non-zero on VPS but exit 0 on developer Mac"
  - "Healthy deploys get rolled back by auto-rollback logic"
  - "Interactive zsh sessions open fine manually, but scripted probes fail"
related_issues:
  - "PR #22 (VPS dotfiles sync target) rollback drill — 2026-04-15"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md (contains inline explanation in post-deploy-smoke.sh)"
  - "docs/solutions/code-quality/zsh-configuration-audit-19-issues.md (adjacent zsh-init territory)"
status: Resolved
---

# `zsh -i -c exit` is a false-positive health check

## Symptom

A post-deploy health check invokes a common idiom to verify the target host's
interactive shell still initializes cleanly:

```bash
if ! zsh -i -c exit >/dev/null 2>&1; then
  echo "FAIL: zsh init aborted"
  exit 1
fi
```

The check passes on the developer's Mac. It fails on the production VPS with
exit status `1` despite `zsh -i -c "echo OK"` printing `OK` on the same host.
Scripted health probes false-positive; interactive sessions are fine.

If the check is wired into an auto-rollback pipeline (as it was in this
session's `.github/workflows/sync-vps.yml`), **every healthy deploy gets
rolled back**.

## Reproduction

On the VPS where the failure manifests:

```bash
zsh -i -c exit          ; echo "status: $?"    # → status: 1
zsh -i -c "echo OK"     ; echo "status: $?"    # → OK ; status: 0
zsh -i -c true          ; echo "status: $?"    # → status: 0
zsh -i -c "exit 0"      ; echo "status: $?"    # → status: 0
```

`exit` with no args returns non-zero; `true` and `exit 0` work fine. The
shell itself is healthy; the **test** is broken.

## Root cause

Zsh's `exit` builtin, when called with **no arguments**, exits with the
status of the last command the shell executed. From `zshbuiltins(1)`:

> **exit** [ *n* ]
> Exit the shell with the exit status specified by *n*; if none is
> specified, use the exit status from the last command executed.

In a `zsh -i -c exit` invocation, the chain is:

1. `.zshenv` sources
2. `.zshrc` sources (through OMZ, starship init, plugin inits, and any
   conditional tool integrations)
3. `-c` command runs — just the literal word `exit`
4. `exit` reads `$?` from step 3's predecessor — which is the final
   side-effect statement in `.zshrc` — and propagates it

Many `.zshrc` templates — including this repo's — end with a cluster of
guarded tool integrations:

```zsh
[[ -f /root/.local/bin/env ]] && source "/root/.local/bin/env"
[[ -d /root/.antigravity/antigravity/bin ]] && export PATH=...
[[ -f /root/.openclaw/completions/openclaw.zsh ]] && source ...
[[ -f /root/.google-cloud-sdk/path.zsh.inc ]] && source ...
```

On a host where those paths **don't exist**, the final `[[ -f ... ]]` test
returns `1`. `.zshrc` returns `1`. `exit` with no args returns `1`.
`zsh -i -c exit` returns `1` — even though initialization completed
successfully and the shell is fully functional.

On a host where those paths **do exist** (or where `.zshrc` ends with a
line that returns 0), the check appears to pass. That's why the bug is
environment-specific and usually caught by a cross-machine rollout.

### Why `zsh -i -c "echo OK"` masks the bug

`echo OK` always returns 0 before `exit` implicitly closes the shell.
Writing `-c "echo OK"` accidentally works; writing `-c exit` accidentally
fails. Neither is a reliable probe.

## Fix

Replace `zsh -i -c exit` with `zsh -i -c true`:

```bash
# scripts/post-deploy-smoke.sh
if ! zsh -i -c true >/dev/null 2>&1; then
  echo "FAIL: zsh -i -c true non-zero (shell init aborted)"
  exit 1
fi
```

`true` always returns 0. A non-zero exit now genuinely means `.zshenv`
or `.zshrc` itself errored — a real regression worth rolling back for.

Add a **code comment** explaining the rationale so the next person doesn't
"clean it up" back to `-c exit`:

```bash
# NOTE: use `-c true`, NOT `-c exit`. The `exit` builtin without args
# returns the last command's exit status. If zshrc ends with conditional
# tests like `[[ -f /some/path ]]` that return false, `exit` inherits
# that non-zero status even though initialization completed successfully.
```

## Equivalent forms that also work

- `zsh -i -c "exit 0"` — explicit; arguably the clearest about intent.
- `zsh -i -c ":"` — `:` is the null command; always returns 0.
- `zsh -i -c true` — what this repo chose; most common in SRE literature.

All three are correct. `-c exit` is the one that isn't.

## Prevention strategies

1. **Never use `-c exit` as a health probe.** Treat it as an anti-pattern.
   The shell's "did I initialize cleanly?" signal is NOT `exit`'s return
   value; it's whether `.zshrc` raised a trap or caused a syntax error.
2. **Test health probes on a host whose `.zshrc` ends with a false
   conditional** before relying on them. Trivially reproduces the bug.
3. **Code-review health checks for return-status correctness** — not just
   "does the command run?" but "does its exit status encode the signal I
   think it does?"
4. If you inherit a repo using `-c exit`, flag it for fix regardless of
   whether it currently appears to work. It's environment-dependent and
   will silently rot the day someone removes a conditional source from
   `.zshrc`.
5. **Apply the same reasoning to bash**: `bash -i -c exit` has the same
   behavior. Same fix: `bash -i -c true`.

## Testing guidance

To verify a fixed probe actually detects a broken shell:

```bash
# Temporarily add a syntax error near the top of .zshrc
echo 'if [ 1 -eq' >> ~/.zshrc    # intentional syntax error

zsh -i -c true; echo "status: $?"
# Expected: non-zero; the `if` parse error aborts .zshrc

# Clean up:
sed -i '' -e '$d' ~/.zshrc       # remove the last line (macOS sed)
# or on Linux: sed -i '$d' ~/.zshrc
```

If the probe still returns 0 with broken `.zshrc`, it's not actually
testing anything.

## Impact in this codebase

- `scripts/post-deploy-smoke.sh:23-31` — fixed in commit
  [`305f478`](https://github.com/villavicencio/dotfiles/commit/305f478).
- `.github/workflows/sync-vps.yml` — invokes the smoke script; now
  rollback-safe against this class of false positive.
- Documented inline in the smoke script itself with a comment so future
  edits don't regress it.

## Related

- [VPS sync target runbook](../cross-machine/vps-dotfiles-target.md) —
  references this health check as part of the workflow's verification
  pipeline.
- [Zsh configuration audit](zsh-configuration-audit-19-issues.md) —
  broader zsh-init hygiene; this one is a specific trap they didn't cover.

## Sources

- `zshbuiltins(1)` — POSIX `exit` semantics: "if none is specified, use
  the exit status from the last command executed."
- PR #22 rollback drill that surfaced this — 2026-04-15.
