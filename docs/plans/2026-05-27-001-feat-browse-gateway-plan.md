---
title: "feat: Self-Hosted Browse Gateway"
type: feat
status: externalized
date: 2026-05-27
origin: docs/brainstorms/2026-05-27-self-hosted-browser-gateway-requirements.md
---

# feat: Self-Hosted Browse Gateway

**Target repo:** `browse-gateway` (new standalone repository — does not yet exist; all repo-relative paths below are within it). The origin requirements doc and this plan live in the `dotfiles` repo as pipeline artifacts; the implementation lands in the new repo.

## Summary

Build an owned browser-automation gateway: a Node/TypeScript service fronting a headful-under-Xvfb browser core (the spike-proven Patchright + real Chrome stealth), exposing an MCP surface to Hermes agents and centralizing the navigation-layer allowlist, scoped-proxy escalation, CAPTCHA, secrets, and observability. Deployed capped on openclaw-prod alongside the live agents. v1 proves out by having a VPS agent retrieve readable text from a bot-blocking site through the gateway, no manual intervention.

---

## Problem Frame

The fleet has no single owned browser surface: Hermes agents have weak built-in browse, Axiom/local CC depend on per-agent Browserbase, and that dependency loses all stealth/proxy/CAPTCHA capability on 2026-06-07 (Free downgrade). The go/no-go spike (recorded in origin) already validated the core bet — self-hosted stealth clears Cloudflare *and* DataDome — so this plan is about *how* to wrap that proven capability into a shared, secure, observable service. See origin Problem Frame for full motivation.

---

## Requirements

- R1. Standalone, independently maintained project; existing `browse` skill suite become clients, not forks.
- R2. Capped Docker on openclaw-prod (CPU/mem + concurrency caps, plus OOM/IO/swap controls) that cannot degrade the live agents; browser runs **headful-under-Xvfb** (strict headless fails).
- R3. One shared endpoint for all three consumer classes.
- R4. MCP server so Hermes agents consume browsing as MCP tools.
- R5. CDP/REST surface so the `browse` CLI reaches it via local-mode CDP-attach, unrewritten *(deferred to v1.1 — see Scope Boundaries)*.
- R6. Defeats hard anti-bot (Cloudflare + DataDome) headlessly — validated by the spike, re-validated through the chosen vehicle in U1.
- R7. Scoped per-session proxy escalation: residential proxy only for Cloudflare managed-challenge from the datacenter IP; off otherwise.
- R8. CAPTCHA solving via a configured solver when encountered.
- R9. BYO proxy/CAPTCHA keys held centrally, isolated to the gateway process user, never logged, with a rotation procedure.
- R10. Outcome-oriented API: `retrieve` (v1) and `synthesize` (v1.1), mechanics hidden from caller.
- R11. `retrieve` returns clean, readable markdown.
- R12. Low-level `drive()` escape hatch *(deferred to v1.1)*.
- R13. Gateway/browser reachable only over Tailscale; raw CDP never public.
- R14. Navigation-layer domain allowlist (intercept `Page.navigate` / requests) so verbs, `drive()`, and CDP-attach all obey it.
- R15. Session-level observability via the browser viewer (live view + replay) with retention + access controls.
- R16. Repoint the `browse` skill suite at the gateway *(deferred to v1.1)*.
- R17. Browser CDP bound localhost-only; all CDP gateway-mediated.
- R18. Per-consumer identity (credentials/ACL tags), per-consumer allowlist scope and audit.
- R19. Container egress filtering (block metadata/internal ranges) + network isolation from the Tailnet.

**Origin actors:** A1 Hermes agents (MCP), A2 Axiom (browse CLI/CDP), A3 local Mac CC, A4 gateway service, A5 browser engine, A6 BYO proxy + CAPTCHA.
**Origin flows:** F1 blocked-article retrieval (the proof), F2 outcome retrieval, F3 proxy escalation.
**Origin acceptance examples:** AE1 (R6,R7,R11,R14), AE2 (R7 no-proxy soft target), AE3 (R8 CAPTCHA), AE4 (R2 CPU/mem), AE5 (R2 session cap), AE6 (R14,R17 allowlist over drive/CDP).

---

## Scope Boundaries

- Hard-authentication paywalls — out (only soft/metered + anti-bot/CAPTCHA).
- In-house proxy/CAPTCHA infrastructure — out (BYO services).
- High-scale / commercial scraping volume — out (personal fleet).
- Cross-fleet aggregated dashboard — out for v1 (browser viewer only).
- Steel's *built-in* stealth as the assumed-good path — superseded; the spike proved Patchright/real-Chrome, which U1 must reproduce through whatever vehicle ships.

### Deferred to Follow-Up Work

- **Second access surface — CDP/REST for the `browse` CLI** (R5): v1.1, after the MCP proof lands.
- **`synthesize()` verb** (R10) and **`drive()` escape hatch** (R12): v1.1 — consumers synthesize from `retrieve()` markdown meanwhile.
- **Full `browse` skill-suite repoint** (R16): v1.1 cutover milestone; v1 wires only the proof consumer.

---

## Context & Research

### Relevant Code and Patterns

- **safe-browser skill** (`~/.agents/skills/safe-browser/`): the canonical allowlist pattern — a tool owns the Playwright/CDP session, enables `Fetch` interception for all requests, and fails any non-allowlisted host. U3 mirrors this for R14 navigation-layer enforcement.
- **browse CLI CDP-attach** (`~/.agents/skills/browser/REFERENCE.md`): `browse env local <port|url>` / `browse env local ws://…` attaches to any CDP target; `BROWSERBASE_API_KEY` sets the default desired mode. The v1.1 repoint (R5/R16) clears that default and points local mode at the gateway CDP URL.
- **Fleet MCP launcher pattern** (`openclaw.json` + stdio launchers in `/home/node/.openclaw/bin/*-launcher.sh`): there is already a `browserbase-mcp-launcher.sh` (`npx -y @browserbasehq/mcp`, Stagehand `navigate/act/observe/extract`, Atlas-only). U6 registers the gateway MCP the same way, replacing the Browserbase MCP.

### Institutional Learnings

- `docs/solutions/.../browserbase-skill-bundle-install-and-trust-2026-05-07.md` — prior browser-skill bundle install/trust learnings.
- **The 2026-05-27 go/no-go spike** (recorded in origin): Patchright + real Chrome, headful-under-Xvfb, cleared Cloudflare (`scrapingcourse`) 4/4 and DataDome (`leboncoin.fr`, `g2.com`) 4/4 from a residential IP; on the VPS datacenter IP, DataDome/CF-WAF passed but the CF managed-challenge failed 3/3 → the scoped-proxy rule in R7.

### External References

- Skipped by decision (Phase 1.2): first-hand spike validation + concrete local patterns; greenfield target. Patchright/Xvfb behavior is already empirically grounded this session.

---

## Key Technical Decisions

- **Engine = the spike-proven config (Patchright-patched Chromium / real Chrome, headful-under-Xvfb).** Steel remains the intended session/viewer vehicle, but U1 is a kill-gate that must reproduce the spike's bypass *through Steel*; if Steel's stealth can't match standalone Patchright, U1 falls back to Patchright + a thin session layer. Rationale: the spike validated the capability, not Steel specifically — de-risk the Steel-specific integration before building on it.
- **Stack = Node/TypeScript.** Patchright is Node; matches the browse CLI and MCP ecosystem the gateway integrates with.
- **v1 surface = MCP for a Hermes agent (Atlas).** Cleanly replaces the existing Atlas-only Browserbase MCP via the established launcher pattern; CDP/REST for the browse CLI is the v1.1 second surface.
- **Allowlist enforced at the navigation layer via Fetch interception** (safe-browser pattern), not at the verb layer — so it can't be bypassed by `drive()` or CDP-attach.
- **Proxy escalation is scoped and trigger-driven**: engage the residential proxy only when a Cloudflare managed challenge fails to clear from the datacenter IP (the spike's finding); direct otherwise.
- **CDP localhost-bound + gateway-mediated**; Tailscale is a layer, not the sole control.

---

## Open Questions

### Resolved During Planning

- Engine/stealth viability: resolved by the spike (Patchright/Chrome/Xvfb clears CF + DataDome).
- Proxy necessity: resolved — scoped to CF-managed-challenge-from-datacenter-IP (R7).
- MCP integration path: resolved — fleet launcher + `openclaw.json` pattern.
- Headless mechanism: resolved — headful-under-Xvfb, not `--headless`.

### Deferred to Implementation

- Whether Steel can drive Patchright-level patched Chromium, or whether the gateway uses Patchright directly — settled empirically in U1.
- Specific residential-proxy provider and CAPTCHA solver (vendor selection + integration shape) — chosen when U5 wires them.
- `retrieve()` extraction library/strategy (readability extraction + graceful degradation to raw HTML / `drive()` handle on failure) — chosen in U5.
- Exact resource-cap values (CPU/mem/session ceilings, `oom_score_adj`, `io.max`) — tuned against measured headroom in U7.
- Final repo name (`browse-gateway` working name).

---

## Output Structure

    browse-gateway/
    ├── docker/
    │   ├── Dockerfile               # Node + Chrome + Xvfb + Patchright
    │   └── compose.yaml             # capped service def (cpu/mem/oom/io), Tailscale-only bind
    ├── src/
    │   ├── gateway/                 # service skeleton, session lifecycle (U2)
    │   ├── browser/                 # engine adapter: Steel-or-Patchright core (U1)
    │   ├── policy/                  # Fetch-interception allowlist + per-consumer auth (U3)
    │   ├── security/                # CDP-localhost binding, egress filter, secret loading (U4)
    │   ├── verbs/                   # retrieve(), proxy escalation, CAPTCHA hook (U5)
    │   ├── mcp/                     # MCP server exposing retrieve as a tool (U6)
    │   └── observability/           # viewer wiring, session retention/access (U7)
    ├── scripts/
    │   └── validate-stealth.mjs     # the go/no-go harness, productionized (U1)
    └── test/

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
 Hermes agent (Atlas) ── MCP (stdio launcher) ─┐
                                               ▼
                                   ┌────────────────────────┐
                                   │  browse-gateway (Node)  │
                                   │  • per-consumer auth    │
   retrieve(url) ──────────────────│  • allowlist (Fetch     │
                                   │    interception)        │
                                   │  • proxy escalation:    │──(only on CF managed
                                   │    CF-challenge+DC-IP    │   challenge)──▶ residential proxy
                                   │  • CAPTCHA hook          │──────────────▶ solver
                                   │  • session lifecycle     │
                                   └───────────┬─────────────┘
                                   localhost CDP (never public)
                                               ▼
                            browser core: real Chrome / Patchright
                            headful under Xvfb  (egress-filtered container)
```

Retrieve flow (F1/F2): consumer → gateway auth + allowlist check → session on browser core → render → on CF-managed-challenge-fail-from-DC-IP, retry via proxy → extract clean markdown → return. Mechanics never surface to the caller.

---

## Implementation Units

### U1. Browser core + stealth validation (kill-gate)

**Goal:** Stand up the browser core in Docker (Chrome + Xvfb + Patchright) and reproduce the spike's bypass *through the shipping vehicle* (Steel if viable, else Patchright directly). Gate: must clear the spike targets before anything else is built.

**Requirements:** R2 (Xvfb), R6.

**Dependencies:** None.

**Files:**
- Create: `docker/Dockerfile`, `src/browser/`, `scripts/validate-stealth.mjs`
- Test: `test/browser-core.test.mjs`

**Approach:**
- Containerize Node + Google Chrome + Xvfb; run headful-under-Xvfb.
- Evaluate Steel driving patched/real Chrome; if its stealth underperforms the standalone Patchright spike, fall back to Patchright + a thin Playwright session layer (Key Technical Decisions).
- Productionize the spike harness as `validate-stealth.mjs`.

**Execution note:** Characterization-first — port the spike harness and confirm parity before layering the service on top.

**Patterns to follow:** the 2026-05-27 spike (`/tmp/bgw-spike/test.mjs`, and `/root/bgw-spike` on openclaw-prod).

**Test scenarios:**
- Covers AE1. Happy path: `scrapingcourse.com/cloudflare-challenge` bypassed headful-under-Xvfb (residential context) → success content, no challenge markers.
- Integration: DataDome (`leboncoin.fr`, `g2.com`) rendered real content, no block markers.
- Edge: strict headless fails (negative control — confirms Xvfb is doing the work).
- Error: if the chosen vehicle can't clear a target the standalone Patchright config cleared, the gate fails loudly and triggers the fallback decision.

**Verification:** the chosen vehicle clears CF + DataDome targets reproducibly (≥3/3 each), matching the spike.

---

### U2. Gateway service skeleton + session lifecycle

**Goal:** The Node/TS service that owns browser-session create/use/destroy and exposes an internal API the surfaces build on.

**Requirements:** R1, R3.

**Dependencies:** U1.

**Files:**
- Create: `src/gateway/`, `docker/compose.yaml`
- Test: `test/gateway-session.test.mjs`

**Approach:** session manager over the U1 core; config loading; one internal request path the MCP/CDP surfaces share so policy lives in one place.

**Patterns to follow:** safe-browser's "tool owns the CDP session" ownership model.

**Test scenarios:**
- Happy path: create session → retrieve a public page → session closes cleanly.
- Edge: concurrent session requests respect a max-session ceiling (sets up R2/AE5).
- Error: browser-core crash surfaces a clean error, no leaked session.

**Verification:** the service starts, manages a session end-to-end, and tears down without orphaning browser processes.

---

### U3. Navigation-layer allowlist + per-consumer auth

**Goal:** Enforce the domain allowlist at the navigation layer via Fetch interception, and authenticate per consumer with per-consumer allowlist scope + audit.

**Requirements:** R14, R18, AE6.

**Dependencies:** U2.

**Files:**
- Create: `src/policy/`
- Test: `test/policy-allowlist.test.mjs`

**Approach:** mirror safe-browser — enable `Fetch` interception on every request, fail non-allowlisted hosts; enforce below the verb layer so `drive()`/CDP-attach (future) can't bypass. Per-consumer identity via tokens or Tailscale ACL tags; audit log per consumer.

**Patterns to follow:** `~/.agents/skills/safe-browser/` Fetch-interception allowlist.

**Test scenarios:**
- Covers AE6. Happy path: allowlisted host navigation proceeds.
- Covers AE6. Error path: non-allowlisted host (including via a raw CDP `Page.navigate`, simulating the future drive()/attach path) is blocked at the navigation layer.
- Edge: per-consumer scopes differ — consumer A's allowlist blocks a host consumer B is allowed.
- Integration: unauthenticated/unknown consumer is rejected before any session opens; the attempt is audited.

**Verification:** off-allowlist navigation is blocked regardless of entry path; each consumer's actions are attributable in the audit log.

---

### U4. CDP hardening, egress filtering, secret isolation

**Goal:** Bind the browser CDP to localhost (gateway-mediated only), filter container egress, and isolate BYO secrets.

**Requirements:** R9, R13, R17, R19.

**Dependencies:** U2.

**Files:**
- Create: `src/security/`, egress/network config in `docker/compose.yaml`
- Test: `test/security-boundary.test.mjs`

**Approach:** browser CDP on 127.0.0.1 only; container egress filter blocks `169.254.169.254` + internal/private ranges; network namespace isolated from the Tailnet interface; proxy/CAPTCHA secrets loaded from a store readable only by the gateway user, never logged.

**Test scenarios:**
- Happy path: gateway reaches the browser CDP on localhost; an external Tailnet node cannot.
- Error path: a page attempting to fetch `169.254.169.254` or an internal IP is blocked by the egress filter.
- Edge: secrets are absent from logs and session/observability output (grep assertion).
- Integration: secret rotation swaps the key without a full redeploy where feasible.

**Verification:** CDP unreachable off-localhost; metadata/internal egress blocked; no secret material in any log surface.

---

### U5. Outcome API — `retrieve()` + scoped proxy + CAPTCHA

**Goal:** The primary `retrieve(url) → clean markdown` verb, with trigger-driven proxy escalation and CAPTCHA solving.

**Requirements:** R6, R7, R8, R10, R11.

**Dependencies:** U2, U3, U4.

**Files:**
- Create: `src/verbs/`
- Test: `test/retrieve.test.mjs`

**Approach:** render via the core → readability extraction to markdown, with graceful degradation (raw rendered HTML when extraction fails); proxy escalation engaged only when a Cloudflare managed challenge fails to clear from the datacenter IP; CAPTCHA solver invoked on encounter.

**Test scenarios:**
- Covers AE1. Happy path: `retrieve()` on a hard target returns readable article markdown.
- Covers AE2. Edge: public/soft target retrieved direct from the VPS IP — proxy NOT engaged (assert no proxy traffic).
- Covers AE3. Error path: a mid-flow CAPTCHA is submitted to the solver and the session continues rather than failing.
- Edge: a CF managed-challenge target that fails direct from the datacenter IP triggers proxy escalation and then succeeds.
- Error: extraction failure degrades to raw HTML rather than returning empty/garbage.

**Verification:** `retrieve()` returns clean content for hard targets; proxy engages only on the scoped trigger; CAPTCHA path doesn't dead-end.

---

### U6. MCP surface for Hermes (v1 proof consumer)

**Goal:** Expose `retrieve` as an MCP tool to a Hermes agent (Atlas), registered via the fleet launcher pattern, replacing the Atlas-only Browserbase MCP.

**Requirements:** R3, R4, R10.

**Dependencies:** U5.

**Files:**
- Create: `src/mcp/`, a stdio launcher (deployed to `/home/node/.openclaw/bin/` on the VPS), `openclaw.json` entry
- Test: `test/mcp-surface.test.mjs`

**Approach:** stdio MCP server mirroring `browserbase-mcp-launcher.sh`; expose `retrieve` (map toward the Stagehand-style verb surface the fleet already knows). Register in `openclaw.json`; preserve the Atlas-only scoping the Browserbase MCP had.

**Patterns to follow:** `/home/node/.openclaw/bin/browserbase-mcp-launcher.sh` + `openclaw.json` MCP registration.

**Test scenarios:**
- Covers F1. Integration (the proof point): Atlas calls the `retrieve` MCP tool for a bot-blocking article on the VPS and gets readable text, no manual intervention.
- Happy path: MCP `tools/list` exposes the gateway tool; a basic retrieve round-trips.
- Edge: the replaced Browserbase MCP no longer loads; no duplicate/conflicting tool names.
- Error: gateway-down surfaces a clean MCP error to the agent, not a hang.

**Verification:** AE1/F1 proof — a Hermes agent retrieves a blocked article through the gateway MCP on the VPS.

---

### U7. Capped deployment + observability on openclaw-prod

**Goal:** Productionize on openclaw-prod with hard resource caps and session-level observability, without disturbing the live agents.

**Requirements:** R2, R15, AE4, AE5.

**Dependencies:** U6.

**Files:**
- Modify: `docker/compose.yaml` (caps), `src/observability/`
- Test: `test/deploy-caps.test.mjs`

**Approach:** CPU/mem limits + max-session cap; `oom_score_adj` favoring the browser container; `io.max`/swap controls so a browser spike can't starve `hermes`/`axiom`. Wire the browser viewer (live view + replay) with a retention window + access control; viewer auth if exposed on the Tailnet.

**Test scenarios:**
- Covers AE4. Integration: drive the container to its CPU/mem ceiling; measure that live-session latency stays within normal bounds (not merely that new sessions are rejected).
- Covers AE5. Edge: sessions beyond the cap queue or are rejected; host unaffected.
- Happy path: a completed session is visible/replayable in the viewer.
- Edge: replays honor the retention window and are not world-readable.

**Verification:** the proof runs on the VPS under caps with the live agents unaffected; sessions are observable; retention/access controls hold.

---

## System-Wide Impact

- **Interaction graph:** the MCP surface replaces the Atlas-only Browserbase MCP in `openclaw.json`; other agents' MCP configs are untouched in v1.
- **Error propagation:** gateway-down / browser-crash must surface clean errors to MCP callers (no hangs) and never leak secrets in error text.
- **State lifecycle risks:** orphaned browser processes / sessions on crash (U2 teardown); replay store growth (U7 retention).
- **API surface parity:** the v1.1 CDP/REST surface (R5) must enforce the *same* U3 allowlist/auth — parity is the whole point of nav-layer enforcement.
- **Integration coverage:** the proof (F1) is an end-to-end MCP→gateway→browser→target path that unit mocks won't prove; U6/U7 carry the real integration test on the VPS.
- **Unchanged invariants:** the live `hermes`/`axiom` tmux sessions and their kernel isolation must not be disturbed; the gateway is additive and capped.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Steel's built-in stealth underperforms the standalone Patchright spike | U1 is a kill-gate with a Patchright-direct fallback baked in |
| Co-located browser degrades the live agents | Hard CPU/mem/session caps + `oom_score_adj`/`io.max`; AE4 stress test gates U7 |
| Anti-bot evolves and breaks stealth post-launch | Accepted maintenance tax (origin Key Decision); viewer + validation harness make regressions detectable; fallback to proxy/managed tier documented |
| Residential-proxy cost creep | Proxy is scoped to CF-managed-challenge-from-DC-IP only; AE2 asserts no-proxy on soft targets |
| Secret exposure on a shared host | U4 gateway-user-only secret store, never logged, rotation procedure |
| CDP/allowlist bypass via future drive()/CDP surface | U3 enforces at the navigation layer; v1.1 surfaces inherit it (System-Wide Impact parity note) |

---

## Phased Delivery

### v1 (this plan)
U1 (kill-gate) → U2 → U3 → U4 → U5 → U6 → U7. Outcome: Atlas retrieves a blocked article through the gateway MCP, on the VPS, under caps — the origin proof point.

### v1.1 (deferred follow-ups)
CDP/REST second surface (R5), `synthesize()` + `drive()` (R10/R12), full `browse` skill-suite repoint (R16), and a cross-fleet dashboard.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-27-self-hosted-browser-gateway-requirements.md](../brainstorms/2026-05-27-self-hosted-browser-gateway-requirements.md)
- Patterns: `~/.agents/skills/safe-browser/` (allowlist), `~/.agents/skills/browser/REFERENCE.md` (CDP-attach), `/home/node/.openclaw/bin/browserbase-mcp-launcher.sh` + `openclaw.json` (MCP)
- Spike harness: `/tmp/bgw-spike/` (Mac), `/root/bgw-spike/` (openclaw-prod)
- Learning: `docs/solutions/.../browserbase-skill-bundle-install-and-trust-2026-05-07.md`
