---
date: 2026-05-27
topic: self-hosted-browser-gateway
---

# Self-Hosted Browser Gateway

## Summary

A standalone, self-hosted browser-automation service — headless Steel running on
openclaw-prod behind a resource-capped container, fronted by an owned *gateway* that
exposes an MCP surface (for Hermes agents) and a CDP/REST surface (for the existing
`browse` skill suite), with stealth, proxy, CAPTCHA, access policy, and observability
centralized in the gateway. Its primary API is outcome-oriented (`retrieve`/`synthesize`
a URL) with a low-level `drive()` escape hatch. v1 proves the bet by having a VPS agent
headlessly pull readable article text from a *named hard-class anti-bot target* — and
the project is gated on a go/no-go stealth spike confirming that bet is reachable before
the gateway is built.

---

## Problem Frame

Browser automation across the fleet is fragmented and weak. The Hermes agents on
openclaw-prod (Atlas the orchestrator and the roster) have only built-in browse
capability — not robust enough to get past modern anti-bot protection. Axiom and the
local Mac Claude Code projects reach browsers through the Browserbase `browse` CLI,
a per-agent SaaS dependency wired up individually.

That dependency is also going away as a capability: the Browserbase account was
downgraded Developer → Free, effective **2026-06-07**. The Free tier has no stealth,
no proxies, and no CAPTCHA solving — so after that date there is no managed path to
protected sources at all. Anything behind Cloudflare/DataDome-class anti-bot, a
metered paywall, or a CAPTCHA becomes unreachable for every agent.

The work the fleet is moving toward — robust automations plus general article
retrieval and synthesis — runs straight into exactly those obstacles. There is no
single owned surface that all three consumer classes can point at, no central place
to hold proxy/CAPTCHA credentials or enforce policy, and no fleet-wide visibility into
what the browsers are doing.

---

## Architecture at a glance

```
   Hermes agents ─┐
   (node user)    ├─ MCP ────┐
                  │          │      ┌────────────────────┐
   Axiom (CC) ────┤          ├────► │   browse gateway    │ ──► Steel (headless,
   local CC ──────┘ CDP/REST ┘      │  • stealth tier     │     capped Docker on
                                    │  • proxy (opt-in)   │     openclaw-prod)
                                    │  • CAPTCHA          │
                                    │  • auth + allowlist │ ──► BYO residential proxy
                                    │  • observability    │ ──► BYO CAPTCHA solver
                                    └────────────────────┘
   verbs:  retrieve(url) → clean markdown   ·   synthesize(url)   ·   drive(url) escape hatch
```

---

## Actors

- A1. Hermes agents (`node` user on openclaw-prod — Atlas + roster): consume browsing as **MCP tools**; need robust headless retrieval their built-in browse can't deliver.
- A2. Axiom (Claude Code PKM session, `axiom` user on openclaw-prod): consumes via the `browse` CLI / skill suite.
- A3. Local Mac Claude Code projects/sessions: consume via the `browse` CLI / skill suite; ad-hoc today, growing toward robust automations.
- A4. The browse gateway service: the single surface all consumers hit; owns session lifecycle, stealth-tier selection, proxy/CAPTCHA decisions, access policy, and observability.
- A5. Headless Steel engine: the browser-execution backend behind the gateway (capped Docker container on openclaw-prod).
- A6. External BYO services: a residential proxy provider and a CAPTCHA solver, invoked by the gateway per-session.

---

## Key Flows

- F1. v1 proof — blocked-article retrieval
  - **Trigger:** A VPS agent (Axiom or Atlas) needs the text of an article on a hard-class anti-bot site that bounces its current built-in browse.
  - **Actors:** A1/A2 → A4 → A5 (→ A6 if needed)
  - **Steps:** Agent calls the gateway with the URL → gateway opens a headless Steel session with stealth on → if the target challenges, gateway escalates (and routes through a residential proxy) → page renders → gateway extracts readable text.
  - **Outcome:** The agent receives clean article text headlessly, no manual intervention.
  - **Covered by:** R6, R7, R10, R11, R14

- F2. Outcome retrieval (the destination verb)
  - **Trigger:** Any consumer calls `retrieve(url)` (or `synthesize(url)`).
  - **Actors:** A1/A2/A3 → A4 → A5
  - **Steps:** Gateway decides stealth tier and whether a proxy is warranted → drives Steel → handles CAPTCHA if encountered → extracts/synthesizes → returns content. Browser, stealth, and proxy mechanics stay hidden from the caller.
  - **Outcome:** Caller gets content, not a browser to drive.
  - **Covered by:** R8, R9, R10, R11

- F3. Proxy escalation decision
  - **Trigger:** A target is hardened or flags the VPS datacenter IP.
  - **Actors:** A4 → A6
  - **Steps:** Default is direct from the VPS IP (no proxy) → on a hardened/blocked target the gateway routes that session through a residential proxy → otherwise stays direct.
  - **Outcome:** Proxy cost/latency is incurred only when the target warrants it.
  - **Covered by:** R7, R9

---

## Requirements

**Project & deployment**
- R1. A standalone, independently maintained project houses the gateway service, the Steel deployment, configuration, and the thin clients. The existing `browse` skill suite become clients of it, not forks.
- R2. Steel runs on openclaw-prod in a Docker container with hard CPU/memory limits and a maximum-concurrent-session cap, so browser bursts cannot degrade or interrupt the live Hermes/Axiom sessions on the same host. The browser runs **headful under Xvfb** (a virtual display), not `--headless` — the 2026-05-27 spike confirmed strict headless fails Cloudflare's challenge while headful clears it. "Headless deployment" is satisfied operationally (no physical display) via Xvfb, not by the browser's headless flag. The cap configuration must address the contention vectors that bare CPU/memory ceilings do not bound: OOM-killer victim selection (e.g., `oom_score_adj` favoring the browser container), IO bandwidth (e.g., `io.max`), and swap behavior.

**Access surfaces**
- R3. One shared endpoint serves all three consumer classes (Hermes agents, the Axiom session, local Mac CC projects) — not per-consumer deployments.
- R4. The gateway exposes an MCP server so Hermes agents consume browsing as MCP tools.
- R5. The gateway exposes a CDP/REST surface so the existing `browse` CLI / skill suite reach it via local-mode CDP-attach, without being rewritten.

**Anti-bot capability**
- R6. The service defeats, headlessly, the anti-bot protection of the v1 proof-class target — a named hard-class anti-bot site (Cloudflare/DataDome-class), not merely a site that blocks the agents' built-in browse. Whether a candidate stealth stack can meet this bar is validated by the go/no-go spike (see Outstanding Questions → Resolve Before Planning) before the gateway is built.
- R7. When a target is hardened or flags the VPS datacenter IP, the gateway routes that session through a residential proxy; otherwise it goes direct. Proxy use is per-session opt-in and off by default *for soft targets*. The v1 proof target is a hardened target and is expected to require the proxy path live — so "off by default" governs soft-target sessions, not the proof itself (see Dependencies / Assumptions).
- R8. When a CAPTCHA is encountered mid-flow, the gateway solves it via a configured solver service and continues the session rather than failing.
- R9. Proxy and CAPTCHA capabilities use bring-your-own third-party service keys, held centrally by the gateway, not built in-house. Those keys are stored in a secrets store readable only by the gateway process user (not the `node` or `axiom` agent users), are never written to session logs or observability output, and have a stated rotation procedure.

**Outcome API**
- R10. The gateway's primary API is outcome-oriented: high-level verbs that return readable content (`retrieve`) and synthesized content (`synthesize`) for a URL, with browser/stealth/proxy mechanics hidden from the caller.
- R11. `retrieve` returns clean, readable text/markdown suitable for direct agent consumption.
- R12. A low-level browser-control escape hatch (`drive`) remains available for interactive automation the high-level verbs don't cover.

**Security & policy**
- R13. The gateway and Steel are reachable only over the private network (Tailscale); raw CDP is never exposed publicly.
- R14. The gateway enforces access authentication and a domain-allowlist policy so consumers cannot drive the browser to unapproved destinations. The allowlist is enforced at the navigation layer (intercepting `Page.navigate` and in-document navigations), not only at the high-level verb layer, so `drive()` (R12) and the CDP-attach path (R5) cannot bypass it.
- R17. Steel's CDP port binds to localhost only and is never directly reachable over the private network; all CDP traffic — including the R5 CDP-attach path — is mediated by the gateway process so authentication (R18) and the allowlist (R14) are enforced unconditionally. Network-level isolation (Tailscale) is a layer, not the sole control.
- R18. The gateway issues per-consumer identity (distinct credentials or Tailscale ACL tags per consumer class), enabling per-consumer allowlist scope and per-consumer audit logging. Tailnet membership alone does not grant browser control — important because some consumers (e.g., Hermes agents that process inbound reddit/telegram content) are plausible prompt-injection targets.
- R19. The Steel container's outbound egress is constrained: cloud-metadata endpoints (e.g., `169.254.169.254`) and internal/private IP ranges are blocked at the host firewall, and the container's network namespace is isolated from the Tailnet interface, so a malicious fetched page cannot pivot to VPS-internal services or other Tailnet nodes.

**Observability & migration**
- R15. v1 provides session-level visibility through Steel's built-in viewer (live view + replay). The replay store has a stated retention window and access control (readable only by authorized users/processes), the viewer endpoint requires authentication if exposed on the Tailnet, and storage location (local disk vs volume vs external) is specified — because replays may capture cookies, tokens, and PII. A cross-fleet aggregated dashboard is deferred.
- R16. The existing `browse` skill suite is repointed at the gateway endpoint (not re-authored) as part of cutover.

---

## Acceptance Examples

- AE1. **Covers R6, R7, R11, R14.** Given an article on a hard-class anti-bot site that returns a challenge to an agent's current built-in browse, when an agent calls `retrieve(url)` through the gateway, the gateway renders the page headlessly — escalating stealth and, if still blocked, routing through a residential proxy — and returns the readable article text.
- AE2. **Covers R7.** Given a public, unprotected documentation page, when an agent calls `retrieve(url)`, the gateway fetches it directly from the VPS IP without engaging a proxy, so no proxy cost is incurred.
- AE3. **Covers R8.** Given an allowlisted target that presents a CAPTCHA mid-flow, when the gateway encounters it, the gateway submits the challenge to the configured solver and continues the session rather than returning a failure.
- AE4. **Covers R2.** Given the browser container hitting its CPU/memory limit under load, when the limit is reached, the live Hermes/Axiom sessions on the same host continue uninterrupted (the OOM-killer does not select a live-agent process, and IO/swap pressure does not stall them).
- AE5. **Covers R2.** Given a concurrent-session spike, when sessions exceed the configured cap, new browser sessions queue or are rejected rather than starving the host — and the live sessions are unaffected.
- AE6. **Covers R14, R17.** Given a consumer attempting to navigate (via `drive()` or raw CDP-attach) to a domain not on the allowlist, when the navigation is issued, the gateway blocks it at the navigation layer rather than allowing the CDP path to bypass the policy.

---

## Success Criteria

- A VPS agent (Axiom or Atlas) retrieves readable article text headlessly from a **named hard-class anti-bot target** (Cloudflare/DataDome-class) — the proof point — with no manual intervention. A soft target (one that merely blocks the built-in browse) does not count as proof.
- The same single endpoint is reachable and usable from all three consumer classes: an MCP tool call from a Hermes agent succeeds, and a `browse env local <gateway-url>` CDP-attach from the browse CLI succeeds without re-authoring the skills.
- The domain allowlist blocks an unapproved-destination navigation issued over the `drive()` / CDP path (not only over the high-level verbs), confirming navigation-layer enforcement.
- The gateway and Steel are not reachable on their control ports from a Tailnet node other than the gateway-mediated path (CDP is localhost-bound).
- A browser-load spike on openclaw-prod never degrades or interrupts the live Hermes/Axiom sessions: a stress test that drives the container to its CPU/memory/session limits shows live-session latency stays within normal bounds (not merely that new sessions are rejected).
- Downstream handoff is clean: `ce-plan` can choose the stealth engine, proxy vendor, CAPTCHA vendor, MCP surface, and wire formats without re-deriving product behavior, the consumer model, or scope.

---

## Scope Boundaries

- **Hard authentication paywalls** (subscriber login walls) are out — only soft/metered paywalls plus anti-bot/CAPTCHA are in scope. (identity)
- **Building proxy or CAPTCHA infrastructure in-house** is out — BYO third-party services instead. (identity)
- **Re-authoring or replacing the `browse` skill suite** is out — it gets repointed only. (identity)
- **High-scale / commercial scraping volume** is out — sized for a personal fleet. (identity)
- **A second dedicated VPS** for browser infra — considered and rejected for v1 in favor of capped co-location. (deferred)
- **A cross-fleet observability dashboard** (aggregated logs/screenshots/sessions) — a named later tier, not v1. (deferred)
- **Full local-Mac dev-parity deployment** of the stack — not a v1 requirement (capped co-location on the VPS was chosen over the portable-image option). (deferred)
- **Keeping Browserbase as a paid fallback tier** — retired; the Free plan remains only incidentally and is not relied on for protected sources. (decision)

---

## Key Decisions

- **Driver is sovereignty/control** — own the full stack, no per-agent SaaS dependency. Justifies investing in real stealth + a shared service rather than the cheapest swap. **This bet is gated on a go/no-go stealth spike** (see Outstanding Questions): if a self-hosted stealth stack cannot reach the hard-class targets the project exists to serve, building the gateway delivers only what local Chrome already does on soft targets, and the sovereignty trade is re-opened.
- **The sovereignty bet carries an ongoing maintenance tax, accepted explicitly.** Self-hosted stealth is an arms race — anti-bot vendors ship detection updates and the stealth stack must be kept current. The operator accepts being the sole maintainer of a load-bearing stealth service, with a re-evaluation trigger and a fallback (see Dependencies / Assumptions).
- **Target shape is an owned gateway (B) designed toward outcome verbs (C).** A single controlled surface serves heterogeneous consumers with consistent policy and observability; outcome verbs match the dominant article-retrieval/synthesis workload better than raw browser control, and keep the browser engine swappable. v1 is reached "the thin way" but lands inside the gateway repo so the proof grows up rather than being thrown away.
- **Co-locate on openclaw-prod, resource-capped.** Cheapest and simplest; hard CPU/memory + concurrency limits (plus OOM/IO/swap controls per R2) protect the live agents from browser bursts; avoids standing up and maintaining a second box. If the stress test shows co-location is unsafe, the rejected "second VPS" option re-opens.
- **Browserbase downgraded Developer → Free, effective 2026-06-07.** Free has no stealth/proxy/CAPTCHA, so there is no managed fallback after that date — Steel is load-bearing for protected sources. This sharpens the rationale but is not treated as a hard deadline (personal project).
- **BYO proxy + CAPTCHA, with per-session opt-in proxying.** Residential proxies cost $/GB and add latency, and the VPS datacenter IP is fine for soft targets but a liability on hardened ones — so pay for a proxy only when the target warrants it. Stealth fixes the browser fingerprint; proxies fix the IP-reputation tell; they are complementary, not redundant.
- **Private-network-only + gateway-mediated CDP + navigation-layer allowlist.** A network-reachable CDP browser is an SSRF/file-read risk, and CDP has no native auth — so Tailscale isolation is one layer, but Steel's CDP is localhost-bound (R17), all CDP is gateway-mediated, and the allowlist is enforced at the navigation layer (R14) so `drive()` and CDP-attach cannot bypass it.

---

## Dependencies / Assumptions

- Steel Browser (MIT) is the chosen browser-execution engine. (Subject of the brainstorm; confirmed by the user.)
- **A residential proxy provider account is likely a v1-blocking dependency, not just an optional escalation** — because the proof target is hard-class and the VPS datacenter IP is pre-flagged, the proof path is expected to require the proxy live. The go/no-go spike confirms whether stealth-alone or stealth-plus-proxy is needed.
- A CAPTCHA solver account (BYO key) is available and affordable at personal-fleet volume.
- **The operator accepts an ongoing stealth-maintenance commitment** as the cost of sovereignty, with an explicit fallback if self-hosted stealth cannot reach (or stops reaching) the hard targets: route those sources elsewhere, accept the gap, or re-open a managed paid tier. The maintenance cadence and a re-evaluation threshold (e.g., hours/quarter, or a sustained failure rate on hard targets) are set during planning.
- openclaw-prod has resource headroom for a capped browser container alongside the live agents. (Assumption — verify the resource budget at planning, given the box already runs kernel-isolated live sessions.)
- A private network (Tailscale) already connects the consumers and the VPS. (Consistent with the dotfiles repo's Tailscale MagicDNS notes.)
- The `browse` CLI's local-mode CDP-attach (`browse env local <url>`) can target the gateway/Steel CDP endpoint. (Verified against the `browser` skill's SKILL.md.)

---

## Outstanding Questions

### Spike Result — 2026-05-27 (go/no-go: conditional GO)

The go/no-go stealth spike ran locally with Patchright + real Chrome (headful), stealth-alone,
from a residential (Mac) IP, with **no proxy and no CAPTCHA solver**:

- **Cloudflare-class: GO** — `scrapingcourse.com/cloudflare-challenge` bypassed 4/4 runs.
- **DataDome-class: GO** — `leboncoin.fr` (pure DataDome) 4/4 with dynamic content; `g2.com`
  (Cloudflare WAF + DataDome — the site that beat the *paid* Browserbase tier in the 2026-05-27
  battle-test) 4/4 rendering the real homepage. (g2's body length was constant across runs —
  worth a deeper full-content check, but real title + zero block markers each run.)
- **Hard constraint discovered:** strict headless **fails** (stuck on the interstitial); only
  **headful** clears it. Production must run headful-under-Xvfb (folded into R2).

**Conclusion:** the core sovereignty bet is validated against both hard anti-bot classes — the
strongest concern the document review raised. The remaining risk has collapsed to **one
variable: the VPS datacenter IP** (all tests used a residential IP; DataDome especially is
IP-reputation-sensitive, and a Hetzner IP may be flagged where the home IP was not).

- [Affects R7] **VPS datacenter-IP test (the one remaining gate).** Reproduce the bypass from
  openclaw-prod's datacenter IP. If it holds, no proxy is needed and R7's proxy path is a
  soft-target-only nicety. If it fails (likely for DataDome), the residential proxy becomes a
  hard v1 dependency — this is the test that resolves the R7 / Dependencies proxy question.

Planning may proceed, front-loading the VPS-IP test before the gateway hardens around it.

### Deferred to Planning

- [Affects R7][Technical] How the per-session proxy-escalation decision is made — a manual per-call flag, automatic on-block detection, or both.
- [Affects R9][Needs research] Which residential proxy provider and which CAPTCHA solver, at personal-fleet pricing.
- [Affects R4][Technical] The MCP tool surface for Hermes agents — which verbs, and how sessions map to MCP calls.
- [Affects R10][Technical] The `retrieve`/`synthesize` extraction approach — readability extraction, and archive-fallback strategy for metered paywalls. Acknowledge extraction quality as an ongoing maintenance surface; define a graceful-degradation contract (return raw rendered HTML or the `drive()` handle when readability extraction fails) rather than silently returning garbage markdown.
- [Affects R16][Technical] The exact repoint mechanism and per-consumer config for the `browse` skill suite (env override vs wrapper).
- [Affects R1][User decision] Project/repo name and where it lives (new standalone repo vs a subdirectory of an existing one).

### From 2026-05-27 document review

- [Affects R3, R4, R5][Sequencing] **v1 access-surface sequencing.** v1 commits both an MCP surface and a CDP/REST surface, but the proof point exercises one consumer. Sequence the second surface as a fast-follow after the proof, without abandoning the all-three-consumers goal. (scope-guardian + product-lens)
- [Affects R10][Scope] **`synthesize()` placement.** The consumers are LLM agents that can synthesize from clean `retrieve()` markdown themselves. Consider shipping `retrieve()` in v1 and sequencing `synthesize()` as a fast-follow, so v1 carries only the surface the proof requires. (scope-guardian + product-lens)
- [Affects R12][Scope] **`drive()` timing.** No v1 flow, acceptance example, or success criterion exercises `drive()`. Consider deferring it to v1.1 while reserving the endpoint path so it isn't a breaking change later. (scope-guardian)
- [Affects R16][Sequencing] **Browse-suite repoint timing.** Repointing the full `browse` skill suite is migration work, not proof-point work — the proof needs only one consumer wired. Consider moving the full-suite repoint to a v1.1 cutover milestone. (scope-guardian)
