---
created_at: "2026-08-24T13:05:00-07:00"
branch: "master"
head: "2b96e3a"
resume_focus: "Seed the Linear Dotfiles backlog with the carried items (pane rebuild is done)"
---

# HANDOFF — 2026-08-24 (PDT)

Tail of the 08-20→08-24 arc (prior handoff #162 covers Linear migration, the
eleven-agent fleet, Moshi/Conduit, and the ShipSigma KPI design — read that PR's
version for the full arc; this refresh adds the last two days and marks a
deliberate model-switch boundary: David is clearing to move Fable 5 → Opus 5).

## What We Built (since #162)

- **Moshi connect failure diagnosed** — not Moshi: the iPhone was off the tailnet
  (last seen 22h). Fix = toggle Tailscale on the phone. Mac side verified healthy
  (sshd, moshi key, mosh-server, firewall disabled).
- **Stale Tailscale Funnel on this Mac found and cleared** — Funnel was publicly
  mapping `zs-macbook-pro.tail31dc0a.ts.net` → 127.0.0.1:18789 with *nothing
  listening*: a loaded gun (any future bind of 18789 would've been public).
  `tailscale serve reset` with David's approval; serve config now empty.
- **ce-handoff adoption verdict (ce-pov, Tier 1): Reject supersede.** dv:handoff
  + dv:pickup stay the daily ritual (repo-tracked, PR'd, zero-question orient);
  ce-handoff's default store is impermanent /tmp and its resume ceremony is
  friction here — but it owns the cross-boundary-transfer lane (another
  agent/machine, resume-from-anything).
- **Four piecemeal adoptions specced for the dv plugin** (source: ~/Projects/skills,
  the skills ⚒ agent's turf): (A) frontmatter metadata + commit-anchored staleness
  in pickup — *this very handoff demonstrates the frontmatter*, (B) prose
  redaction pass, (C) pointer-first bodies, (D) drift-led orientation. Spec is a
  SETUP-ONLY mission (orient → create Linear project "Skills" + tickets A–E →
  report and stop); David pastes it to the skills agent (last copied to clipboard
  2026-08-24).

## What's Next (recommended order for the fresh session)

1. ~~Rebuild the `dotfiles ~` pane (w1)~~ — **done 2026-08-24 (#165).** The real
   state was worse than "old `exec claude` shape": the exported pane node had no
   `command` at all (bare shell with claude started inside), so it detected fine
   but a server restart would have returned an empty shell. Rebuilt via
   `layout.apply` onto the existing tab; diagnosis + exact invocation are now in
   CLAUDE.md's Herdr section. **Verify after this pickup:** `layout.export` for
   w1 should show the template `command`, and the workspace label should still
   read `dotfiles ~`.
2. **Seed the Linear "Dotfiles" project backlog** — the backlog is empty while
   carryovers live in handoff prose, which is exactly what Linear was adopted to
   fix. Ticket the known items: statusline `BAR_CELLS` 10→20 (+ optional
   `refreshInterval`) from the 08-20 accuracy discussion; Touch ID `sudo_local`
   on the work Mac; the CLAUDE.md time-continuity rule update (prefer HANDOFF
   frontmatter `head`/`created_at` over mtime — gated on skills ticket A
   shipping).
3. **Externally gated, act when they arrive:** ShipSigma KPI report-back from
   Brittanie's machine (VIL-17→20 — ask about the blockers first; suspects: M365
   admin consent, task↔Project attachment, connector gaps); skills agent's
   setup-loop report (then David gates implementation ticket-by-ticket).
4. Passive: herdr upstream #2960/#2961/#2966.

## Gotchas & Watch-outs

- Model-switch mechanics: cache is per-model; the boundary (clear → switch →
  pickup) is the cheap path. Done deliberately this session.
- shipsigma-kpi repo rule stands: structure/names in git, never target values;
  `HANDOFF-brittanie-setup.md` is generated from `package/` — edit sources,
  regenerate, re-pbcopy.
- Orrery repo: PR flow, never force-add `src/data/dashboard.json`, no pre-commit
  hook there.
- Do NOT reintroduce a phone gateway (Moshi is SSH/mosh direct; Conduit teardown
  reversal tarball: `/home/node/.hermes/backups/conduit-teardown-20260821-144904.tgz`).
- Linear MCP tools are deferred (ToolSearch first); real newlines in markdown
  params. Fleet roster + jump keys: table in CLAUDE.md Herdr section.
