# HANDOFF — 2026-05-27 (PDT)

Same-session continuation of the browse-gateway arc. The prior sitting took it research → brainstorm → requirements doc → 6-persona doc review → spike → plan, all committed to `dotfiles`, ending at "the implementation repo does not exist yet." **This sitting created that repo, seeded it public-safe, and handed implementation off to a distinct Claude Code instance.** dotfiles itself got no new commits this session — all work landed in the new `browse-gateway` repo.

## What We Built

- **Created the implementation repo: `browse-gateway`** — public, at https://github.com/villavicencio/browse-gateway, local checkout `~/Projects/browse-gateway` (branch `main`, personal git identity). One commit: `8783da4 chore: bootstrap browse-gateway repo`.
- **Seeded three public-safe files** (verified zero fleet internals via leak scan before push):
  - `README.md` — generic gateway description (Node/TS, real-Chrome-under-Xvfb stealth core, outcome verbs, scoped proxy, allowlist). No hostnames/agent names/paths.
  - `CLAUDE.md` — project conventions + intended `src/` layout + "build the kill-gate first" order; routes the implementing agent to private context.
  - `.gitignore` — Node + `.env*` + a load-bearing `*.local.md` rule (keeps the bridge file private).
- **Wrote `CONTEXT.local.md` in browse-gateway (gitignored, never pushed)** — the private bridge: absolute paths to the real plan/requirements/handoff in dotfiles, the validated spike facts, reusable spike-stack locations (`/root/bgw-spike`, `/tmp/bgw-spike`), deployment guardrails (don't disturb `hermes`/`axiom`), and the op gotchas. Verified on-disk-but-untracked.
- **Left the dotfiles planning docs untouched** — the requirements brainstorm and the 7-unit plan stay private in dotfiles; browse-gateway references them via the bridge file rather than copying them.

## Decisions Made

- **Distinct CC instance for implementation, not this one.** Rationale: context hygiene (dotfiles' CLAUDE.md is ~400 lines of Homebrew/dotbot/zsh rules irrelevant to a Node gateway), and CE memory/`docs/solutions/` should compound in the gateway repo. The plan already assumed a separate repo.
- **Repo is public, but the planning docs stay private.** The user chose public for the repo; on reading the docs I flagged that they contain fleet hostnames (`openclaw-prod`/Hetzner), agent/account names (`hermes`/`axiom`/Atlas/`node`), file paths (`/home/node/.openclaw/bin/*`), and a complete threat-model-with-named-attack-surface (R18's prompt-injection note) — a public push would publish the fleet's operational security posture. User chose **"docs stay private; seed generic only."** Resolved via the gitignored `CONTEXT.local.md` bridge: CE convention (docs travel with code) is satisfied locally without leaking.
- **No LICENSE committed.** Public + no license = "all rights reserved" by default. Left unpicked deliberately — MIT would fit the spike's MIT-Steel lineage if the user wants it actually open-source.

## What Didn't Work

- Nothing relitigated or dead-ended this session. The one course-correction: the original "push everything verbatim" reading of "public repo" was caught before any push — the leak scan + the docs-stay-private decision happened pre-commit, so no internals ever reached GitHub.

## What's Next

1. **In the `browse-gateway` instance** (`cd ~/Projects/browse-gateway && claude`): read `CONTEXT.local.md` → the plan it points to → start **U1, the stealth kill-gate** (Dockerize Chrome + Xvfb + Patchright, reproduce the spike bypass through the shipping vehicle; ≥3/3 on CF-challenge + DataDome). Everything U2→U7 is blocked on U1 passing.
2. **Commit the CE config sitting uncommitted in browse-gateway** (see Gotchas) — mirrors dotfiles commit `60fb677`.
3. Optional: add a LICENSE to browse-gateway if open-sourcing for real.
4. Optional (deferred from ce-plan): deeper doc review on the plan before coding.
5. **dotfiles' role for this project is now just custody of the private planning docs** — no further dotfiles work is implied. Implementation lives entirely in the other repo.

## Gotchas & Watch-outs

- **⚠️ Uncommitted changes in `~/Projects/browse-gateway`:** `M .gitignore` + untracked `.compound-engineering/` (CE project config the user added post-bootstrap). Not committed by this session — it's the user's change in the other repo. The new instance should commit it (pattern: dotfiles `60fb677`).
- **The `*.local.md` gitignore rule is load-bearing.** `CONTEXT.local.md` carries all the fleet internals; if that rule is ever weakened, internals leak to the public repo. Any future private file in that repo must match `*.local.*` or `.env*`.
- **Don't disturb the live agents** on openclaw-prod: `hermes` (Atlas, `node` user) and `axiom` (kernel-isolated). The gateway must be capped and additive.
- **Auto-mode classifier blocks compound prod-mutating SSH** (`apt && npm && …` in one `ssh openclaw-prod '…'`). Use atomic single-purpose commands, or run setup via `! <cmd>`. Read-only SSH recon is fine.
- **Spike stacks are pre-installed and reusable:** `/root/bgw-spike` on openclaw-prod (Xvfb + Chrome + Patchright, headful, `--no-sandbox`) and `/tmp/bgw-spike` on the Mac (throwaway).
- Browserbase downgrades Developer → Free on **2026-06-07** — no managed stealth/proxy/CAPTCHA after that. Soft pressure, not a hard deadline; it's why the self-hosted stealth core is load-bearing.
- This HANDOFF lives in **dotfiles**. The browse-gateway instance gets its own orientation from `CONTEXT.local.md`, not from here.
