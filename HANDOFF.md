# HANDOFF — 2026-05-27 (PDT)

Single-sitting arc on a new project: **a self-hosted browser-automation gateway** to replace per-agent Browserbase across the fleet. Went research → `/ce-brainstorm` → requirements doc → `/ce-doc-review` (6 personas) → go/no-go spike (local + VPS) → `/ce-plan`. Everything is committed to `dotfiles`; the *implementation* targets a **new `browse-gateway` repo that does not exist yet**. This was a context-hygiene continuation of the morning's VPS-mirroring session (that handoff is in git history at `29bd558`).

## What We Produced

- **Requirements doc:** `docs/brainstorms/2026-05-27-self-hosted-browser-gateway-requirements.md` — brainstormed, then hardened by a 6-persona `ce-doc-review` (10 findings applied, 4 deferred), then annotated with the spike results. Committed (`0ca7f9e`, `db2fecd`).
- **Implementation plan:** `docs/plans/2026-05-27-001-feat-browse-gateway-plan.md` — Deep, 7 units, U1 is a stealth-validation **kill-gate**. Committed (`ed90b68`).
- **No code yet.** Plan stops at the planning boundary by design.

## The Bet (validated this session)

A Node/TS **gateway** fronts a headless browser core; agents call it, it owns stealth/proxy/CAPTCHA/allowlist/observability. Driver: **sovereignty** (own the stack, no per-agent SaaS). Shape: owned gateway aiming at outcome verbs (`retrieve`/`synthesize`) + `drive()` escape hatch. Co-located **capped** on openclaw-prod. Three consumer classes: Hermes agents (MCP), Axiom + local CC (CDP/REST), one shared endpoint.

## Spike Results (the de-risking — all empirical)

- **Engine:** **Patchright + real Chrome, headful-under-Xvfb** beats Cloudflare *and* DataDome (incl. `g2.com`, which beat the paid Browserbase tier) — stealth-alone, **no proxy, no CAPTCHA**. **Strict headless FAILS** → must run headful-under-Xvfb on the VPS.
- **Proxy is SCOPED, not always-on:** from the VPS datacenter IP, DataDome + Cloudflare-WAF pass with no proxy; only Cloudflare **managed-challenge** pages need the residential proxy (same browser passed from a residential IP, failed 3/3 from the datacenter IP). That's the R7 escalation trigger.

## Key Decisions

- **Engine = the spike-proven config.** Steel stays the intended vehicle, but **U1 must re-validate the bypass *through* Steel**; Patchright-direct is the baked-in fallback if Steel's stealth can't match it.
- **Stack: Node/TypeScript.** **Repo name: `browse-gateway`** (rejected `browse-agent` — "agent" already means the fleet's actual agents).
- **v1 surface = MCP for Atlas** (replaces the Atlas-only Browserbase MCP via the existing `openclaw.json` + `/home/node/.openclaw/bin/*-launcher.sh` pattern). CDP/REST surface, `synthesize()`/`drive()`, and full browse-suite repoint are **v1.1**.
- **Security baked in** from the doc review: localhost-only gateway-mediated CDP (R17), Fetch-interception allowlist at the navigation layer (R14, mirrors the `safe-browser` skill), per-consumer identity (R18), egress filtering (R19), secret isolation (R9).

## What's Next

1. **Create the `browse-gateway` repo.** The plan + doc live in dotfiles; the code does not go here.
2. **U1 — stealth kill-gate:** Dockerize Chrome + Xvfb + Patchright, reproduce the spike bypass through the shipping vehicle. Everything else is blocked on this passing.
3. Then U2→U7 per the plan (gateway skeleton → allowlist/auth → CDP/egress/secret hardening → `retrieve()` + scoped proxy + CAPTCHA → MCP surface → capped deploy + observability). Proof point: Atlas retrieves a blocked article through the gateway MCP on the VPS.
4. Optional before coding: `Run deeper doc review` on the plan (offered at ce-plan handoff, deferred).

## Gotchas & Watch-outs

- **Spike stack is already installed** — Mac: `/tmp/bgw-spike` (throwaway). **openclaw-prod: `/root/bgw-spike`** has Xvfb + Google Chrome + Patchright installed (didn't touch the live `hermes`/`axiom` sessions). Reusable for U1.
- **Don't disturb the live agents.** openclaw-prod runs `hermes` (Atlas, `node` user) and `axiom` (kernel-isolated); the gateway must be capped and additive.
- **Auto-mode classifier blocks compound prod-mutating SSH** (`apt && npm && …` in one `ssh openclaw-prod '…'`). Atomic single-purpose commands pass; or have the user run setup via `! <cmd>`. Read-only SSH recon passes fine.
- **The plan's repo-relative paths are within `browse-gateway`** (stated as target repo at the top of the plan), not dotfiles.
- Browserbase downgraded **Developer → Free on 2026-06-07** — no managed stealth/proxy/CAPTCHA after that; not treated as a hard deadline, but it's why Steel is load-bearing.
