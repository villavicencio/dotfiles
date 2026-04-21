---
title: "Tailscale tag + ACL + expiry interactions that broke SSH to a tagged node"
date: 2026-04-15
last_updated: 2026-04-20
category: cross-machine
tags:
  - tailscale
  - ssh
  - acl
  - tags
  - oauth
  - vps
  - deploy
  - bug-fix
severity: High
component: "Tailscale admin console, ACL policy file, tailscaled on VPS"
symptoms:
  - "`tailscale ssh root@host` returns 'tailnet policy does not permit you to SSH to this node' after tagging the host"
  - "`tailscale ssh` to VPS times out after running `tailscale up --advertise-tags=...`"
  - "SSH worked yesterday, breaks today with no policy file changes (key expiry)"
  - "`tailscale status --json` shows `Tags: null` on a node that displays a tag badge in the admin UI"
  - "ACL edit saved but the rule doesn't seem to apply"
related_issues:
  - "PR #22 VPS dotfiles sync target — Phase A Tailscale setup, 2026-04-15"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md (operational runbook)"
status: Resolved
---

# Tailscale tag + ACL + expiry interactions that broke SSH to a tagged node

## Symptom

Setting up a GitHub Actions → Tailscale → VPS deploy pipeline required
tagging the VPS with `tag:prod` and adding an SSH ACL rule. Over the course
of one setup session, SSH to the VPS broke **three distinct ways**:

1. Immediately after `tailscale up --advertise-tags=tag:prod` — session
   timed out entirely (`Operation timed out`).
2. After re-establishing connectivity — "tailnet policy does not permit
   you to SSH to this node" from a user that previously had access.
3. After adding an apparently-correct `ssh` ACL block — still denied.

Each step took 5–20 minutes to diagnose. Documenting the full chain so
next time it's 2 minutes.

## The three distinct failure modes

### Failure 1: Node expired right before you touched it

**What happened:** `tailscale up` on the VPS silently re-validated the
node's auth state. The node had been **expired for a day** (Tailscale's
default node key expiry is 90 days; for a headless server this is a
foot-gun). The admin UI badge said *"Expired 1 day ago"* next to
`tag:prod`. Tailscale blocks most operations on expired nodes.

**Why you don't notice until you touch it:** an expired node sometimes
continues answering to already-established WireGuard tunnels. New SSH
sessions fail, but if you had a long-running `mosh` open you wouldn't
know. `tailscale up` re-negotiates, at which point expiry blocks you.

**Fix:** disable key expiry for servers. Admin UI → Machines → host row
→ ⋮ → **Disable key expiry**. This is the Tailscale-recommended setting
for always-on infra. User devices (laptops, phones) *should* expire;
servers *should not*.

**Prevention:** on every new VPS, **disable key expiry as step one of
provisioning**, before you ever depend on the node. Tailscale does not
expose this via CLI on older clients — must be done in the admin UI.

### Failure 2: `autogroup:self` stops matching a tag-owned node

**What happened:** before tagging, the VPS was "user-owned" by your
account. The default ACL has an entry like:

```json
{
  "action": "check",
  "src":    ["autogroup:member"],
  "dst":    ["autogroup:self"],
  "users":  ["autogroup:nonroot", "root"]
}
```

This says "any member can SSH to devices they own." `autogroup:self` means
"source user identity matches destination node's user-owner." As user-
owner of the node, you matched this rule.

Applying `tag:prod` changed the node's ownership semantics. Tailscale still
shows your email in the owner column of the machine list, but **ACL
evaluation treats a tagged node as owned by the tag's `tagOwners`**, not
by the user. `autogroup:self` no longer matches the destination.

No implicit rule replaces it. Without an explicit accept rule from your
user to `tag:prod`, SSH is denied.

**Fix:** add an explicit `ssh` ACL block granting your user (or
`autogroup:admin`, or a specific group) access to the tag:

```json
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:admin"],
    "dst":    ["tag:prod"],
    "users":  ["root"]
  },
  // ... then the pre-existing check/autogroup:self block, after ...
]
```

**Critical detail:** Tailscale SSH rules are **first-match-wins**. If the
old `autogroup:self` check rule comes before your new accept rule in the
file order, you might still get blocked (the check rule matches and
requires interactive re-auth, which scripted SSH can't satisfy). **Put
your accept rules first.**

### Failure 3: Self-advertised tag isn't authoritative until approved

**What happened:** `tailscale up --advertise-tags=tag:prod` on the VPS
successfully reported the desired tag to the Tailscale coordinator. The
machine list in the admin UI showed `tag:prod` next to the host row.

But `tailscale status --json | jq .Peer[].Tags` on another tailnet member
reported `Tags: null` for that host. Coordinator state disagreed with the
UI badge. SSH ACL rules keyed on `tag:prod` matched nothing.

**Root cause:** there are **two distinct ways** a tag can apply to a node:

1. **Self-advertised** — the node requests a tag via
   `tailscale up --advertise-tags=...`. Coordinator records the request
   and marks the tag as "pending admin approval." The admin console shows
   the tag with a warning indicator.
2. **Admin-assigned** — tailnet admin explicitly adds the tag via the UI
   or API. Coordinator treats it as authoritative immediately.

If the `tagOwners` block in your ACL policy isn't live (or if the OAuth
client/API request that advertised the tag doesn't own that tag), the
self-advertisement gets stuck in "pending" state. The node sees the tag;
the coordinator doesn't grant it.

**Fix:** bypass the self-advertise-then-approve flow. Admin UI →
Machines → host row → ⋮ → **Edit ACL tags** → add `tag:prod` → Save.
Admin-assigned tags take effect immediately.

**How to tell which path you're on:**

```bash
# From any tailnet member (not the host itself):
tailscale status --json | jq '.Peer | to_entries[]
  | select(.value.HostName == "my-vps")
  | .value.Tags'
```

- `["tag:prod"]` → authoritative, ACLs will key on it.
- `null` → coordinator hasn't accepted the tag yet; ACL rules referencing
  it won't match.

If it's `null` despite the UI showing the tag, you're in the
pending-approval limbo. Admin-assign the tag directly to move past it.

### Failure 4: `grants` block missing for raw OpenSSH over tailnet

Discovered later (2026-04-20) and documented in its own page because it
sits in a different ACL block and fails with a different symptom surface.
Summarized here for parallel discoverability:

**What happened:** after the three fixes above, `tailscale ssh root@host`
from the user's laptop worked perfectly. But a GitHub Actions workflow
joining the tailnet as `tag:gh-actions` could not reach the VPS — the
target didn't even appear in the runner's tailnet peer list. Symptom
surface was DNS failure (`lookup openclaw-prod on 127.0.0.53:53: server
misbehaving`), which looked nothing like an ACL problem.

**Root cause:** the `ssh` block governs only **Tailscale SSH** (a
separate auth layer invoked as `tailscale ssh <host>`). Raw OpenSSH over
tailnet — what the workflow actually uses (`ssh root@openclaw-prod` on
port 22) — requires a `grants` block entry. Missing a grant is strictly
stronger than "access denied" — the destination node is entirely
invisible in the source's peer list, so MagicDNS has no record to return.

**Fix:** add a `grants` entry AND a regression test:

```json
"grants": [
  {"src": ["tag:gh-actions"], "dst": ["tag:prod"], "ip": ["tcp:22"]}
],
"tests": [
  {"src": "tag:gh-actions", "accept": ["tag:prod:22"]}
]
```

**Full writeup:**
[tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md](tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md).

## Why these failure modes stack

Setting up a tagged host for the first time exercises the full chain:

1. You `tailscale up --advertise-tags=tag:prod` on the VPS.
2. The coordinator detects the node's key is expired → blocks operation.
3. You disable key expiry in the admin UI → operation succeeds.
4. The advertised tag is now "pending" because `tagOwners` for `tag:prod`
   isn't live yet.
5. You edit the ACL to add `tagOwners` + an `ssh` accept block → save.
6. The tag is still pending because the node hasn't re-advertised post-
   ACL-save. You try to SSH → "policy does not permit."
7. You admin-assign the tag from the UI → coordinator makes it
   authoritative.
8. SSH still fails because the `autogroup:self` rule comes first in the
   policy and demands interactive check.
9. You reorder ACL rules to put the accept rule before the check rule.
10. SSH finally works.

Every step feels like the "last" fix. Each revealed the next failure.

## Fix: do it in the right order the first time

A clean bring-up for tagging a new production node:

```
0. Admin UI — confirm your user role is Owner or Admin
   (autogroup:admin only matches those roles, not plain members).

1. Admin UI — Disable key expiry on the target node.

2. ACL policy file (admin console) — add:
   "tagOwners": {
     "tag:prod": ["autogroup:admin"]
   }
   Save.

3. ACL policy file — add an ssh block ABOVE any pre-existing
   autogroup:self check rule:
   "ssh": [
     { "action": "accept",
       "src": ["autogroup:admin"],
       "dst": ["tag:prod"],
       "users": ["root"] },
     ... existing rules ...
   ]
   Save.

4. Admin UI — Edit ACL tags on the target node → add tag:prod → Save.
   (Do NOT use `tailscale up --advertise-tags` — it goes through the
   pending-approval dance.)

5. Verify from your laptop:
   tailscale status --json | jq '.Peer | to_entries[]
     | select(.value.HostName == "the-node") | .value.Tags'
   # Must print ["tag:prod"], not null.

6. Smoke test SSH:
   tailscale ssh root@the-node 'echo ok'
```

Each step is independently verifiable. If one fails, the next is
meaningless — diagnose before proceeding.

## Prevention strategies

1. **Disable key expiry on every provisioned server immediately.** Add
   it to your VPS provisioning checklist.
2. **Never use `tailscale up --advertise-tags` for initial tag assignment
   on a node you're actively debugging.** Admin-assignment from the UI is
   surgical and avoids the pending-approval limbo.
3. **Treat any ACL edit involving tags as a three-part change** —
   `tagOwners`, the `ssh` or `grants` rules that reference the tag, and
   the tag assignment on affected nodes. Save the ACL **before**
   assigning the tag, so the coordinator has a valid rule to apply the
   moment the tag lands.
4. **When debugging "policy does not permit" on Tailscale SSH, check
   `tailscale status --json`'s `Tags` field first.** If it's `null` when
   you expect a tag, the rest of the ACL doesn't matter — fix
   authoritativeness before tweaking rules.
5. **Know your rule evaluation order.** Tailscale SSH rules are
   first-match-wins. A `check` rule that matches before your `accept`
   rule will demand interactive re-auth that scripts can't satisfy.

## Diagnostic cheat sheet

```bash
# Is the node's tag authoritative with the coordinator?
tailscale status --json \
  | jq '.Peer | to_entries[] | select(.value.HostName == "HOSTNAME") | .value.Tags'

# Is the node key expired?
tailscale status | grep HOSTNAME
# Look for "expired" in the output; if present, fix via admin UI.

# Does the ACL's ssh block grant your user access to the target tag?
# (No CLI equivalent — must read the policy file in admin UI.)

# Is Tailscale SSH enabled on the target?
tailscale status --json \
  | jq '.Peer | to_entries[] | select(.value.HostName == "HOSTNAME") | .value.SSHEnabled'
# null or false means tailscaled on the host isn't running with --ssh.

# Verbose SSH from the client side to see where handshake fails:
ssh -v root@HOSTNAME 'echo ok' 2>&1 | tail -40
# "tailnet policy does not permit you to SSH to this node" confirms the
# denial is server-side policy, not a local SSH config problem.
```

## Related

- [tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md](tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md)
  — Failure 4 in full detail: `grants` vs `ssh` block distinction for raw
  OpenSSH over tailnet.
- [VPS dotfiles sync target](vps-dotfiles-target.md) — operational runbook
  that references this ACL/tag setup.
- Tailscale docs: [Grants](https://tailscale.com/kb/1324/acl-grants),
  [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh),
  [ACL tags](https://tailscale.com/kb/1068/acl-tags).

## Sources

- PR #22 VPS sync target setup session, 2026-04-15.
- `tailscale up` man page — self-advertisement behavior.
- Tailscale KB article on `autogroup:self` matching semantics for tagged
  nodes.
