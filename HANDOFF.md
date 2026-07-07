# HANDOFF — 2026-07-07

Started with `/pickup` on dotfiles to clear the one dirty file left from last session,
then the session pivoted almost entirely into a **cross-project naming + domain-availability
exercise** for the operator's `ibmcconstruction.com` platform (the "Foreman" SMB-site builder).
The only dotfiles deliverable is PR #95; everything else was scratch research that produced no
repo artifacts (by design — it belongs to a different project).

## What We Built

**dotfiles (the only code change):**
- **PR #95 (OPEN)** — `chore: register openai-codex plugin in Claude settings`, branch
  `chore/register-codex-plugin`, commit `77fb26d`. Separated the two changes that were sitting
  dirty in `claude/settings.json`:
  - **Kept (intentional):** the `codex@openai-codex` plugin the operator installed today via
    slash command, plus its `openai-codex` marketplace (`openai/codex-plugin-cc`) under
    `extraKnownMarketplaces`.
  - **Reverted (runtime churn):** restored the `"model": "opus[1m]"` pin that `/model` had
    stripped at runtime — so the net diff vs. the recorded baseline is *only* the codex addition.
  - Followed the #94 precedent (settings-baseline changes go through a branch/PR, not straight
    to master). Working tree is now clean.

**Cross-project research (NO artifacts written anywhere — pure conversation):**
- Confirmed from memory that we (Claude, in the `browse-gateway` project) **helped name Obscura**
  on 2026-06-11 — picked from a shortlist (Portunus, Heimdall, Janus, Charon, Vantage, Scry,
  Bastion, Iris…), rationale = camera-obscura + "obscured"/stealth. Recorded in
  `~/Projects/browse-gateway/docs/brainstorms/2026-06-11-obscura-brand-and-connect-experience-requirements.local.md`.
- Read the IBMC platform context (`~/Projects/ibmcconstruction.com/{README,AGENTS,docs/design/design-brief}.md`):
  "Foreman" names the **productizable agent-operable SMB-site platform**, not the client GC.
- Generated **10 Greek/Roman/mythological alternatives** to "Foreman": Daedalus, Talos,
  Hephaestus/Vulcan, Tekton, Faber, Vesta/Hestia, Terminus, Janus, Vitruvius, Opus — each mapped
  to the builder/agentic-maker thesis.
- Ran an **exhaustive Vercel domain sweep (~150+ lookups)** — all 10 names × 14 TLDs
  (`.com .ai .co .io .build .app .work .pro .team .studio .dev .run .us .contractors`) + the full
  Foreman variant set (the-/get-/try-/my-/hire- prefixes, -hq/-app/-ai suffixes).

## Decisions Made
- **Platform name = Foreman (FINAL).** Operator chose to stick with it after seeing the mythic
  alternatives and the domain reality. Rationale: construction-native double meaning (runs the
  *job* site / runs the *web* site); plainspoken. Mythic names ruled out — don't relitigate.
- **`claude/settings.json` churn handling:** the model-pin removal is `/model` runtime noise and
  gets reverted on commit; only genuine additions (plugins/marketplaces) are the real diff. This
  is the standing pattern for that file.
- **Naming/domain work stays out of the repos** — it was exploratory; nothing was written to
  dotfiles or ibmcconstruction. The two offered follow-ups (record the name / buy a domain) were
  left for the operator to trigger, not done.

## What Didn't Work
- **Every clean domain for Foreman is taken** — bare `foreman.*` gone on all 14 TLDs; every
  strong `.com` variant (the/try/my/hire/get-foreman, foreman-hq/app/ai) also gone. There's an
  established open-source **Foreman** (theforeman.org infra tool + the `foreman` Ruby process-
  manager gem) holding the namespace — different category, not a blocker, but you share search
  results.
- **The mythic names are no better** — none of the 10 has a clean premium TLD available either
  (`.com/.ai/.io/.co/.app/...` all taken across the board). The dictionary/mythic-word well for
  ownable domains is dry.

## What's Next
1. **Merge PR #95** (`gh pr merge 95 --squash --delete-branch` once CI is green) — the one open
   dotfiles item. Currently on branch `chore/register-codex-plugin`; switch back to master after.
2. **(ibmcconstruction, optional)** Record "Foreman" as the platform's official name — its
   `AGENTS.md`/`README` still calls it "a productizable, agent-operable SMB-site platform" with no
   name. Would be a branch/PR in that repo, not dotfiles.
3. **(ibmcconstruction, optional/low-priority)** If locking a domain early matters, the only
   realistic buys are **`theforeman.io`** ($38/yr) or **`foremanhq.ai`** (~$80/yr). No urgency —
   the platform isn't productized and IBMC already lives at `ibmcconstruction.com`.
4. **Carried from prior handoff (davidv.sh / external, unchanged):** measure Ship Sigma aggregate
   daily send volume → plug into `/ops/shipsigma-deliverability` calculator; optional `villavi.dev`
   purchase; Dec 11 2026 calendar event for the 307→308 redirect flip.

## Gotchas & Watch-outs
- **PR #95 is open and unmerged** — you're still on the `chore/register-codex-plugin` branch. Don't
  start new dotfiles work until it's merged and you're back on master, or you'll stack changes.
- **`claude/settings.json` will keep going dirty** as `/model` and `/effort` write to it — expected
  churn. When committing, revert the model-pin removal and keep only real additions (see Decisions).
- **The domain research produced no files** — if you go looking for a saved report, there isn't one.
  The full matrix is in this session's transcript only. The single actionable finding: `.contractors`
  ($9.99) is the one TLD open for every name — on-theme for a contractor platform if you ever want a
  cheap coherent domain, but Foreman itself was the lone name whose `.contractors` was already taken.
- **The Vercel domain-check MCP** (`mcp__plugin_vercel_vercel__check_domain_availability_and_price`)
  caps at 10 names/call — batch accordingly if you re-run any sweep.
