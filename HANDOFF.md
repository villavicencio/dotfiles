---
created_at: "2026-08-24T13:15:58-07:00"
branch: "master"
head: "078c75c"
resume_focus: "Backlog seeded (VIL-82, VIL-83) and ShipSigma closed — next real work is picking one of the two open tickets"
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
   CLAUDE.md's Herdr section. **Verified 2026-08-24 at pickup:** `layout.export`
   for w1 returns pane `w1:p7` carrying the full template `command`
   (`/bin/zsh -l -c "claude; exec /bin/zsh -il"`) with the dotfiles cwd, and the
   workspace label still reads `dotfiles ~`. Not degraded; survives a restart.
2. ~~Seed the Linear "Dotfiles" project backlog~~ — **done 2026-08-24.** Two
   tickets, not three: **VIL-82** (statusline — a live side-by-side against the
   app's usage panel confirmed `5h 3%` / `7d 44%` are *accurate*, so the ticket
   is coverage, not correctness: add the missing third meter, the premium-model
   weekly bar the app shows at 76%, plus the `BAR_CELLS` 10→20 widening and
   optional `refreshInterval`) and **VIL-83** (CLAUDE.md session-continuity
   rule). Touch ID `sudo_local` on the work Mac was dropped as not needed.
   VIL-83's premise was corrected while writing it: prefer the frontmatter
   `head` *commit timestamp* — verifiable, survives checkout — over both mtime
   and `created_at`, because this very handoff's `created_at` was ~9 minutes
   ahead of reality and less accurate than its own mtime.
3. **Pick up VIL-82 or VIL-83.** VIL-82 opens with a verification step: capture
   one live statusline stdin payload and confirm which `rate_limits` key backs
   the app's "Fable" row (`seven_day_opus` is the plausible but unconfirmed
   candidate; `seven_day_sonnet` / `seven_day_overage_included` /
   `seven_day_oauth_apps` are the other siblings the 2.1.241 bundle exposes).
   VIL-83 is coupled to skills ticket A, which is underway now.
4. Passive: herdr upstream #2960/#2961/#2966.

## Gotchas & Watch-outs

- Model-switch mechanics: cache is per-model; the boundary (clear → switch →
  pickup) is the cheap path. Done deliberately this session.
- **ShipSigma KPI is closed (2026-08-24).** Work deviated considerably and moved
  onto Brittanie's laptop, so VIL-17→20 are **Canceled** (not Done — it was not
  delivered as specced) and the Linear project is Canceled with a note; VIL-21
  stays Done, it shipped. No report-back is pending; stop treating it as gated.
  The local-only `~/Projects/shipsigma-kpi` package survives as salvage — its
  rule still holds if you ever reopen it: structure/names in git, never target
  values, and `HANDOFF-brittanie-setup.md` is generated from `package/` — edit
  sources, regenerate, re-pbcopy.
- Orrery repo: PR flow, never force-add `src/data/dashboard.json`, no pre-commit
  hook there.
- Do NOT reintroduce a phone gateway (Moshi is SSH/mosh direct; Conduit teardown
  reversal tarball: `/home/node/.hermes/backups/conduit-teardown-20260821-144904.tgz`).
- Linear MCP tools are deferred (ToolSearch first); real newlines in markdown
  params. Fleet roster + jump keys: table in CLAUDE.md Herdr section.
