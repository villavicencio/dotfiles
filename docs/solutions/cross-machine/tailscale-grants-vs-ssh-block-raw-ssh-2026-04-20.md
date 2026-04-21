---
title: "Tailscale ACL: raw OpenSSH over tailnet needs a `grants` entry, not just an `ssh` rule"
date: 2026-04-20
category: cross-machine
module: sync-vps workflow, Tailscale ACL policy
problem_type: workflow_issue
component: tooling
severity: high
applies_when:
  - "Tailscale ACL is in grants mode (the newer schema — all new tailnets default to this)"
  - "A tagged source needs to reach another node via anything other than `tailscale ssh`"
  - "Adding CI/CD access (GitHub Actions, GitLab runners, Buildkite) to production nodes"
  - "Restructuring an existing ACL and the diff touches `grants`, `ssh`, or `tests`"
tags:
  - tailscale
  - acl
  - grants
  - github-actions
  - ssh
  - vps
  - sync-vps
  - magicdns
related_issues:
  - "GH issue #42 — sync-vps workflow: tag:gh-actions cannot see tag:prod in tailnet peer list (filed + closed 2026-04-20)"
  - "docs/solutions/cross-machine/tailscale-tag-acl-ssh-failure-modes.md (companion — different ACL failure modes in the same family)"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md (operational runbook — its ACL snippet teaches an incomplete pattern, see Refresh Notes)"
verification_run: "https://github.com/villavicencio/dotfiles/actions/runs/24694912948"
status: Resolved
---

# Tailscale ACL: raw OpenSSH over tailnet needs a `grants` entry, not just an `ssh` rule

## Context

Tailscale's grants-mode ACL has two authorization surfaces that look similar
but govern different things. A workflow running on a `tag:gh-actions` GitHub
runner needs to OpenSSH into `tag:prod` on port 22 (raw sshd, for
`rsync`/`scp`-style deploys). The initial ACL was:

```json
"grants": [
    {"src": ["autogroup:admin"], "dst": ["*"], "ip": ["*"]}
],
"ssh": [
    {"action": "accept", "src": ["tag:gh-actions"], "dst": ["tag:prod"], "users": ["root"]}
]
```

— no corresponding entry in `grants` for `tag:gh-actions → tag:prod`. The
`sync-vps.yml` workflow failed intermittently at the `Join tailnet` step with
what looked like DNS / MagicDNS flakiness:

```
error looking up IP of "openclaw-prod": lookup openclaw-prod on 127.0.0.53:53: server misbehaving
```

Three successive fixes on `fix/sync-vps-dns-race` (SSH-retry loop with
`ConnectTimeout=5`, `tailscale ip -4` hostname pinning to `/etc/hosts`, and
finally a full diagnostic dump) made the real cause visible. The handoff had
mis-labeled this as "tailnet ping flakiness" and recommended pinning the
action version or adding retries — both theory-based fixes that would never
have worked.

Session history shows this workflow also failed twice in the 2026-04-17 →
2026-04-18 window and was both times dismissed as "ephemeral OAuth tailscale
join flakiness on the runner" — direct SSH from the Mac still worked (the
Mac sits in `autogroup:admin` with the wildcard grant), so the VPS appeared
healthy and the runner failure was misread as transient noise. The carry-
forward list from both prior handoffs had "investigate sync-vps tailnet
ping flakiness" at the top. _(session history)_

The diagnostic commit that finally cracked it printed `tailscale status`
from inside the runner. Ground truth:

```
100.96.253.112  github-runnervmeorf1   (self)
100.94.39.11    iphone181
100.66.203.8    mac-q4hmv2qrcx
100.94.140.44   zs-macbook-pro
```

`openclaw-prod` was **absent from the runner's tailnet peer list**. From
the user's laptop the same moment, `tailscale status` listed
`100.75.213.64 openclaw-prod` healthy and tagged `tag:prod`. The VPS was
up, tagged correctly, reachable from every other node — it was just
invisible to `tag:gh-actions`.

## Guidance

Two rules for any Tailscale ACL managing machine-to-machine access in
grants mode:

**1. If a source needs raw IP connectivity to a destination (port 22
OpenSSH, HTTP, database, anything that isn't `tailscale ssh`), it MUST
appear in `grants`.**

The `ssh` block only authorizes Tailscale SSH — a separate auth layer
invoked via `tailscale ssh <host>`. It does **not** grant raw IP
reachability and does **not** cause the destination to appear in the
source's tailnet peer list. Missing a grant is strictly stronger than
"access denied" — the node doesn't appear in the peer list at all, which
surfaces as DNS lookup failures for the tailnet short name.

**2. Add a regression test every time you add a grant.**

Tailscale validates `tests[]` at save-time and refuses to save an ACL where
a test fails. A one-line test is how you prevent a future ACL refactor
from collaterally removing the grant — which is exactly what happened on
2026-04-17, during an unrelated `tests[].src requires concrete user, not
autogroup` restructure.

Concrete fix for the sync-vps case:

```json
"grants": [
    {"src": ["autogroup:admin"], "dst": ["*"], "ip": ["*"]},
    // ↓ add this:
    {"src": ["tag:gh-actions"], "dst": ["tag:prod"], "ip": ["tcp:22"]}
],
"ssh": [
    {"action": "accept", "src": ["tag:gh-actions"], "dst": ["tag:prod"], "users": ["root"]}
],
"tests": [
    {"src": "villavicencio.david@gmail.com", "accept": ["tag:prod:22"]},
    // ↓ add this regression guard:
    {"src": "tag:gh-actions", "accept": ["tag:prod:22"]}
]
```

Scope the grant minimally: `"ip": ["tcp:22"]`, not `"ip": ["*"]`. The
runner only needs sshd; no reason to widen the blast radius.

## Why This Matters

The silent failure mode is what makes this high-value to document. If a
missing grant produced `connection refused` or `permission denied`, nobody
would misdiagnose it — the error message would point at authorization.
Instead, a missing grant strips the destination from the source's peer
list *before any connection attempt happens*. The MagicDNS resolver
(100.100.100.100) has no record to return for `openclaw-prod`, and
`getent hosts openclaw-prod` fails.

From the runner's perspective, this is **indistinguishable from a real DNS
problem.** Every diagnostic you'd run against a DNS race — retry loops,
hostname pinning, resolver debug — appears to confirm the DNS hypothesis
while being orthogonal to the actual fix. The sync-vps team (me) burned
three commits on `fix/sync-vps-dns-race` before adding an observation-only
diagnostic step that printed `tailscale status` on the runner itself and
revealed the peer-list gap.

The silent failure also contaminates prior handoffs. The 04-17 and 04-18
failures were dismissed as "OAuth tailscale join flakiness" because direct
SSH from the Mac still worked — but `autogroup:admin` had the wildcard
grant all along, so the Mac was never a valid control. The asymmetric
observability between admin-user and tag:gh-actions masked the bug's
nature for three days. _(session history)_

### Meta-pattern

When a handoff labels a bug with a timing/race/flakiness hypothesis and
two theory-driven fixes fail in the same ~30ms window, **stop theorizing
and add an observation step** before writing fix #3. Print runtime state —
`tailscale status`, peer list, resolver config, whatever is closest to
ground truth. The cost is one CI run; the payoff is ground truth instead
of another collision with the real cause.

This reinforces two earlier shared learnings:

- **2026-04-14 reproduce-then-attribute** — when compounding a fix,
  reproduce the failure before attributing a root cause.
- **2026-04-16 inspect runtime truth** — for claims of the form "config
  knob X causes runtime behavior Y", identify a source of runtime truth
  and inspect it before documenting causation.

Observation-first is cheaper than a fourth wrong fix, every time.

## When to Apply

Apply the **grants-not-just-ssh rule** whenever:

- A Tailscale ACL uses grants mode (all new tailnets default to this)
- A machine, tagged source, or service account needs to reach another
  node via anything other than `tailscale ssh`
- You're adding CI/CD access (GitHub Actions, GitLab runners, Buildkite
  agents) to production nodes
- You're restructuring an existing ACL and the diff touches `grants`,
  `ssh`, or `tests` — re-verify each tagged source still has every grant
  it needs

Apply the **regression-test-every-grant rule** whenever you add or modify
any `grants` entry. The test is cheap (one line) and the validator runs
it at save-time for free.

Apply the **observe-before-third-fix meta-pattern** whenever:

- A handoff hands you a hypothesis (especially timing/race/flakiness)
- Two fixes based on that hypothesis fail with identical symptoms
- You're about to write fix #3 against the same theory

## Examples

### Example 1 — the failure this documents

Runner's `tailscale status` on the failing run (24694134310) showed 4
peers: itself, two iPhones, one Mac. `openclaw-prod` was absent. Same
moment, from the user's laptop, `tailscale status` showed
`100.75.213.64 openclaw-prod` listed healthy and tagged. The VPS was up,
tagged correctly, reachable from every other node — just invisible to
`tag:gh-actions`. Adding the `tcp:22` grant restored visibility; run
[24694912948](https://github.com/villavicencio/dotfiles/actions/runs/24694912948)
went green in 15 seconds.

### Example 2 — what the regression test catches

On 2026-04-17 the ACL was edited to fix a separate validation error
(`tests[].src requires concrete user, not autogroup` — documented in
cross-project Forge learnings). During the restructure, the
`tag:gh-actions` grant was collaterally removed. Had the ACL already
contained `{"src": "tag:gh-actions", "accept": ["tag:prod:22"]}` in
`tests`, Tailscale's save-time validator would have rejected the save
with a clear message, and the regression would never have shipped.

The VPS cgroup-OOM incident on 2026-04-18 forced a full reboot. Prior to
that, the runner may occasionally have succeeded against a cached peer
table; post-reboot the gap became consistent. The test prevents both
modes of regression — permanent and cached-lag. _(session history)_

### Example 3 — generalizing to other protocols

The same pattern applies to any non-Tailscale-SSH access. If
`tag:monitoring` needs to scrape Prometheus on `tag:prod:9090`:

```json
"grants": [
    {"src": ["tag:monitoring"], "dst": ["tag:prod"], "ip": ["tcp:9090"]}
],
"tests": [
    {"src": "tag:monitoring", "accept": ["tag:prod:9090"]}
]
```

An `ssh` block for that pair would be meaningless — Prometheus doesn't
speak Tailscale SSH.

### Example 4 — applying the meta-pattern

Next time a handoff says "flaky DNS" or "timing race" and fix #1 and
fix #2 both fail in the same ~30ms window, the next commit should not
be fix #3. It should be a diagnostic step:

```yaml
- name: Diagnose tailnet state (TEMP)
  run: |
    echo "=== tailscale status ==="
    tailscale status 2>&1 || true
    echo "=== tailscale status --json (peers only) ==="
    tailscale status --json 2>&1 \
      | jq '.Peer | to_entries | map({host: .value.HostName, dns: .value.DNSName, ips: .value.TailscaleIPs, online: .value.Online})' \
      || true
    echo "=== resolvectl status ==="
    resolvectl status 2>&1 | head -40 || true
    echo "=== tailscale ip -4 ${{ inputs.host }} ==="
    tailscale ip -4 "${{ inputs.host }}" 2>&1 || true
    echo "=== getent hosts ${{ inputs.host }} ==="
    getent hosts "${{ inputs.host }}" 2>&1 || true
```

One CI run, ~5 seconds, reveals whether the target is even in the peer
list. Revert the step after the real fix lands.

## Related

- [`docs/solutions/cross-machine/tailscale-tag-acl-ssh-failure-modes.md`](./tailscale-tag-acl-ssh-failure-modes.md)
  — companion doc covering three other ACL failure modes (key expiry,
  `autogroup:self` on tagged nodes, self-advertised-tag approval limbo).
  This doc is effectively a fourth failure mode in the same family, but
  distinct enough to warrant its own page: different ACL block (`grants`
  vs `ssh`), different symptom surface (peer-invisibility vs explicit
  "policy does not permit"), and different affected path (raw OpenSSH
  vs `tailscale ssh`).
- [`docs/solutions/cross-machine/vps-dotfiles-target.md`](./vps-dotfiles-target.md)
  — operational runbook. **Note:** its "Tailscale OAuth + ACL setup"
  section currently shows an `ssh`-only ACL snippet that reproduces this
  bug on fresh setup. See Refresh Notes below.
- Tailscale docs:
  [Grants](https://tailscale.com/kb/1324/acl-grants),
  [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh),
  [ACL tags](https://tailscale.com/kb/1068/acl-tags).

## Refresh Notes

The Related Docs Finder flagged
[`vps-dotfiles-target.md`](./vps-dotfiles-target.md) as a high-priority
refresh candidate — its ACL snippet teaches the `ssh`-only pattern that
caused this incident. A future operator following that runbook would
reintroduce issue #42. Suggested next action:

```
/ce:compound-refresh vps-dotfiles-target
```

The
[`tailscale-tag-acl-ssh-failure-modes.md`](./tailscale-tag-acl-ssh-failure-modes.md)
doc would also benefit from a short "Failure 4" cross-reference pointing
here, so someone hitting the grant-gap symptom finds both docs.
