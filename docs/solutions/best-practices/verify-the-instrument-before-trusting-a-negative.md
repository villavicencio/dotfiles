---
title: "Verify the instrument before trusting a negative — in-band probes beat blind outside observers"
date: 2026-08-18
category: best-practices
module: debugging-methodology
problem_type: best_practice
component: tooling
severity: Medium
applies_when:
  - "About to conclude a negative — 'env var absent', 'event never fires', 'X is dead' — from absence of evidence in a log or an outside observer"
  - "Using `ps eww` (or any outside-process observer) to read another process's environment on modern macOS"
  - "Inferring dispatch/spawn behavior from a server log that may not log that event class at all"
  - "Debugging a launchd/Homebrew service whose spawned commands silently do nothing (bare launchd PATH lacks /opt/homebrew/bin)"
  - "About to file an upstream bug report on the strength of a negative observation"
symptoms:
  - "`ps eww <pid>` shows only 2-3 environment variables for a process you know has a full environment"
  - "A configured binding or hook appears to never dispatch — no log line — but the server never logs that event class at all"
  - "A bound command works with an absolute path yet 'silently fails' with a bare command name"
  - "Successive contradictory conclusions in one debugging session, each 'proven' by a different measuring instrument"
root_cause: observability_gap
related_components:
  - development_workflow
  - verification
  - herdr
tags:
  - debugging-methodology
  - testing-methodology
  - silent-failure
  - false-negative
  - in-band-probe
  - launchd
  - herdr
  - macos
---

# Verify the instrument before trusting a negative — in-band probes beat blind outside observers

## Context

Three false negative conclusions were reached in one day (2026-08-18) while wiring the herdr 0.8.0 agent multiplexer (Homebrew install, server under launchd via `brew services start herdr`) on macOS arm64. All three had the same shape: an outside observer that was silently blind to the thing it was supposed to measure, producing "the feature is dead" verdicts that in-band probes later overturned.

**Artifact 1 — "HERDR_AGENT env pinning is dead."** `ps eww <pid>` showed no `HERDR_*` variables in herdr-spawned pane processes, so the conclusion was that `layout.apply`'s `env` block never reaches pane processes. The measurement was `ps eww <pid> | tr ' ' '\n' | grep -c '^HERDR_AGENT=hermes$'` returning 0 — and when a `/usr/bin/env HERDR_AGENT=hermes …` argv wrapper was tried as an alternative delivery path, the *same* `ps eww` probe judged it too, yielding "isn't landing even via `env(1)`" (session history). Two measurements through one blind instrument corroborated nothing; they just made the wrong conclusion look robust. On modern macOS, `ps eww` cannot read *other* processes' environments and silently prints nothing — the calibration check that exposed this was running `ps eww` against our own live shell, which reported only 2 variables (obviously wrong). An in-band probe — a pane spawned via `layout.apply` running `printenv` and read back through herdr's own `pane.read` API — showed `HERDR_AGENT=hermes` plus all herdr context variables delivered correctly. Truth: env delivery works fine. And in a final twist discovered during this doc's own grounding validation: the env-pin feature the probe seemed to disprove *does* exist — `HERDR_AGENT` is documented upstream as a detection hint scoped to host-visible wrapper foregrounds (sandbox wrappers like `fence`/`nono`) — it just doesn't fire for ssh-attach panes on 0.8.0 (re-verified: ssh foreground + env hint → pane not detected at all). The probe had proven *delivery*; the "no such feature" generalization outran what it measured. The false finding landed in HANDOFF.md and CLAUDE.md the same day it was made (the interim docs mislabeled its origin as 2026-08-07; session history dates the flawed measurement to the 2026-08-18 morning session) and was nearly filed upstream as a bug; it became feature request herdrdev/herdr#2961 instead, and the repo docs were corrected in PR #141.

**Artifact 2 — "`herdr server reload-config` silently no-ops on `[[keys.command]]`."** Custom keybindings appeared dead after a config reload. The evidence: no dispatch lines in `~/.config/herdr/herdr-server.log` at keypress time — and built-in bindings *did* log (e.g. `client detach requested via keybind`), which made the absence look meaningful. Reality: herdr does not log `type="shell"` command spawns or their failures at all — the log was blind to that entire event class, so absence proved nothing. The bindings dispatched every time; the spawned `sh -c "herdr agent focus atlas"` died instantly on command-not-found, because a brew-services (launchd) daemon PATH lacks `/opt/homebrew/bin`. Detached spawn, failure surfaced nowhere. This was mis-filed upstream as herdrdev/herdr#2960 (the maintainer bot could not reproduce — their environment had a sane PATH), a wrong "bindings load only at server startup" gotcha briefly entered CLAUDE.md/AGENTS.md, and a server restart was performed partly to "activate" bindings that were never inactive.

**Artifact 3 — the decisive experiment.** Change the bound command to the absolute path `/opt/homebrew/bin/herdr agent focus axiom`, run `herdr server reload-config`, press the key → works instantly. One A/B toggle simultaneously proved the root cause (PATH), disproved the reload-no-op theory (reload applies key changes fine), and disproved the startup-only theory. Upstream #2960 was corrected and retitled the same day; repo docs were corrected in PR #142.

A suspected fourth instance from the same morning (session history, unconfirmed): the original session recorded the `prefix+a` binding as "verified working" right after adding it, but the skeleton does not show how that test was driven — if the jump was triggered through the socket API rather than an actual keypress, the verification exercised the wrong path entirely. When testing a keybinding, confirm the dispatch path being tested is the one being claimed.

## Guidance

**A negative conclusion ("var absent", "event never fires", "feature dead") is only as good as the instrument that produced it.** Before trusting a negative, do two things: calibrate the instrument against a known-true case, and re-run the measurement with an in-band probe — a mechanism that reports from *inside* the system under test.

**1. Calibrate the instrument against a known-true case.** If it can't see a thing you know exists, its silence about the thing you're testing means nothing.

```bash
# Can ps read environments at all? Point it at YOUR OWN shell first.
ps eww $$
# Expected: your full environment (dozens of vars).
# Observed on modern macOS: ~2 vars → ps is blind to env; any
# "var is absent" conclusion drawn from it is void.
```

For log-absence arguments, the calibration question is: *does this log record the event class even when it succeeds?* Provoke a case you know fires (here: a built-in binding did log) — but confirm the log covers the *same class* as the thing under test. Herdr logs built-in key actions but not `type="shell"` spawns, so the two classes are not comparable and absence in one says nothing about the other.

**Corollary: a second measurement through the same blind instrument is not corroboration.** Artifact 1's `env(1)` argv-wrapper "alternative" was judged by the same `ps eww` probe that judged the original mechanism — so it could never have exonerated either. Independent confirmation requires an independent channel, not a second run of the blind one.

**2. Prefer in-band probes.** Have the suspect code path itself emit evidence, and read it back through the system's own channels.

In-pane `printenv` via `layout.apply` + `pane.read` (the probe that settled artifact 1):

```bash
# Spawn a pane through the exact mechanism under test, with a
# self-reporting command:
#   /bin/sh -c 'echo PROBE_START; printenv | grep -E "^HERDR" \
#     || echo NO_HERDR_VARS; echo PROBE_END; sleep 120'
# (declared as the pane command in the layout.apply payload)

# Then read the pane's own screen back through herdr's API
# (pane.read, source=visible). Output observed:
#   PROBE_START
#   HERDR_AGENT=hermes
#   HERDR_...=...        # full herdr context delivered
#   PROBE_END
```

The probe runs *inside* the spawned process and is read back through the system's own screen-read API — no intermediary that can silently drop the answer. The same idea generalizes: a marker-file write (`touch /tmp/probe-$$`) from the suspect code path, an `echo` into a file you control, an `env > /tmp/env-dump` in the bound command.

**3. When two theories compete, design the single toggle that separates them** (the absolute-path A/B from artifact 3):

```toml
# BEFORE (looks dead — dies on launchd PATH, failure invisible):
[[keys.command]]
key = "a"
command = "herdr agent focus atlas"

# AFTER (works instantly after a plain reload-config):
[[keys.command]]
key = "a"
command = "/opt/homebrew/bin/herdr agent focus atlas"
```

One variable changed (path resolution), everything else held constant. The result answers three questions at once: the binding dispatches (reload works), the command fails on PATH (root cause), and no restart was ever needed (startup-only theory dead).

**4. Bound your conclusion to the probe's actual question.** A probe answers exactly what it poses, no more. The `printenv` probe settled *delivery* of the env var; concluding "the feature doesn't exist" was a second claim the probe never tested — and it turned out to be wrong (the hint is documented for wrapper foregrounds; only the ssh case fails). Before asserting a feature's nonexistence, the missing instrument is usually the vendor's documentation, not another measurement.

## Why This Matters

Falsified negatives are expensive, and this session paid the full bill:

- **A wrong upstream bug report** — herdrdev/herdr#2960 was filed claiming reload-config silently no-ops on custom bindings; the maintainer bot could not reproduce (its environment had a sane PATH), and the issue had to be corrected and retitled the same day the A/B probe ran.
- **Wrong durable documentation** — the "HERDR_AGENT is not delivered" finding entered HANDOFF.md and CLAUDE.md, and the "bindings load only at server startup" gotcha entered CLAUDE.md/AGENTS.md. Durable docs are exactly where a false negative compounds: every future session inherits it as fact. Corrections shipped in PR #141 (env-pin claim) and PR #142 (reload claim).
- **Wasted operational churn** — a server restart was performed partly to "activate" bindings that were dispatching the whole time.
- **A right decision carrying a wrong rationale** — abandoning env pinning for the argv[0] ssh-shim was the correct engineering pivot (herdr 0.8.0 has no env pin feature; detection is process-name only, per the manifest read that followed), but the *recorded reason* was the ps-eww artifact. Decisions can outlive their rationales in docs; a false rationale invites someone to "fix" a working mechanism later (session history).

Each false conclusion survived until an in-band probe ran; each was overturned within minutes once one did. The probes were cheap — a `printenv` pane and a one-line config toggle. The asymmetry is the lesson: minutes of probe design against days of wrong docs and an upstream filing that burned maintainer time.

## When to Apply

- Any conclusion of the form "X is dead / absent / never fires / not delivered" — negatives claim the non-existence of something, and non-existence is exactly what a blind instrument reports for free.
- Anything measured through an *outside* observer: `ps` output, log absence, screen-scraping, `--dry-run` listings, another process's view of state. First ask: can this observer see the event class at all? Calibrate against a known-true case before trusting its silence.
- Before filing an upstream bug from negative evidence. If your reproduction is "I don't see it happen," run an in-band probe first — your environment (here: launchd PATH) may be the variable, not their code.
- Before writing a negative finding into durable docs (CLAUDE.md, AGENTS.md, docs/solutions/). A false positive in docs gets caught the next time someone tries the thing; a false negative teaches everyone to never try it.
- When a detached/daemon-spawned process "does nothing" — spawn failures under launchd surface nowhere by default. Add a marker-file or output-capture probe to the spawned command itself.

## Examples

**Artifact 2 → 3, the before/after that turned "dead feature" into "PATH bug":**

Before — relative-path binding, judged dead by log absence:

```toml
[[keys.command]]
key = "a"
command = "herdr agent focus atlas"   # spawned as sh -c under launchd
```

Observation: keypress → nothing happens, nothing in `herdr-server.log`. What it *seemed* to prove: the binding never dispatched, therefore reload-config (and maybe anything short of a server restart) doesn't load `[[keys.command]]`. What it *actually* proved: nothing — herdr doesn't log shell-command spawns or their failures, so the log was structurally incapable of distinguishing "never dispatched" from "dispatched and died instantly."

After — absolute path, same reload mechanism:

```toml
[[keys.command]]
key = "a"
command = "/opt/homebrew/bin/herdr agent focus atlas"
```

Observation: `herdr server reload-config`, press the key → focus jumps immediately. What it proved: the binding dispatches (so reload-config applies key changes fine, and no restart is needed); the only difference between dead and working was PATH resolution, so the failure was `command-not-found` inside a launchd daemon whose PATH lacks `/opt/homebrew/bin`.

The instrument (log absence) supported the wrong theory for a full debugging arc — including an upstream filing (#2960) and a restart — because its silence was mistaken for evidence. The in-band probe (making the suspect command itself the reporter, by removing its one failure mode) settled it in a single keypress.

## Related

Instrument-trust siblings in this repo:

- [trufflehog's silent false negative](../security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md) — the audit was nearly declared clean from the scanner's negative alone; a manual in-band `git log -p | rg` probe found the missed token.
- [Claude Code Bash tool strips PUA glyphs](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md) — silent alteration by the tool in the middle; the standing prevention rule is byte-level `xxd` verification of on-disk content before declaring success.
- [`zsh -i -c exit` false-positive health check](../code-quality/zsh-dash-i-c-exit-false-positive-health-check.md) — the inverse failure: the probe itself was broken. Validate that a probe measures what you think it measures before trusting its verdict in either direction.
- [sudo in no-TTY agent shells](../security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md) — the same launchd/no-TTY environment family, including its own false-negative pre-flight trap (`topgrade --dry-run | grep sudo` predicts nothing).
- [dot doctor heredoc pipe deadlock](../runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md) — isolated reproductions came back clean; only in-band looping of the real command (and `sample` on the hung pid) exposed it.
- Weaker kin: [bash pipeline traps hidden by short-circuits](../best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md) (green signal is not proof), [install-matrix IPv6 misattribution](../cross-machine/install-matrix-ipv6-fallback-misattribution-2026-05-05.md) (measurement led to a wrong durable conclusion via causal misattribution), [brew shellenv PATH clobbering](../code-quality/brew-shellenv-clobbers-path-via-path-helper.md) (PATH divergence only visible by probing each context directly).

Upstream artifacts of this incident: [herdrdev/herdr#2960](https://github.com/herdrdev/herdr/issues/2960) (corrected + retitled), [herdrdev/herdr#2961](https://github.com/herdrdev/herdr/issues/2961) (env-pin feature request; closed as already-supported via the documented wrapper-foreground `HERDR_AGENT` hint — the ssh-attach case is reproduced as not firing on 0.8.0 in the issue thread). Repo corrections: PR #141, PR #142.
