# Global Claude Code Instructions

These instructions apply across all projects on all machines.

---

## Per-agent Obsidian vaults (standard rev. 2026-07-15; supersedes the one-day one-vault experiment)

Every project/agent/harness owns a small, self-contained Obsidian vault at
`~/Obsidian/<name>/`, managed by that agent as it sees fit. There is no shared monolith.
Cross-vault reads are fine when useful (plain filesystem paths); write to another
project's vault only when asked.

- Claude Code projects keep harness memory *physically in their vault*:
  `~/.claude/projects/<slug>/memory` is a **symlink** to `~/Obsidian/<name>/memory`.
- **New-project bootstrap** — first session in a Mac CC project with no vault:
  1. `mkdir -p ~/Obsidian/<name>/memory`
  2. If `~/.claude/projects/<slug>/memory` exists as a real dir, move its contents into
     the vault memory dir; either way replace it with a symlink to it.
  3. Stamp the standard config: `cp -R ~/Projects/Personal/dotfiles/obsidian/vault-template/.obsidian ~/Obsidian/<name>/.obsidian`
  4. Append the "## Vault" declaration to the project's CLAUDE.md/AGENTS.md (copy the
     shape from `~/Projects/agents/CLAUDE.md`).
  (David registers it in Obsidian's UI via "Open folder as vault" whenever he wants it.)
- **Standard vault config** — canonical template, git-versioned:
  `~/Projects/Personal/dotfiles/obsidian/vault-template/.obsidian/` (rev 1 harvested from
  hermes 2026-07-15; excludes `workspace*.json` + `cache`).
  - **"Apply the standard to X"** (blank/new vaults — full stamp, overwrites existing
    config): `rm -rf ~/Obsidian/X/.obsidian && cp -R <template> ~/Obsidian/X/.obsidian`.
    On first open, Obsidian asks once to enable community plugins — expected.
  - **Theme-only apply** (vaults an agent has customized — preserves plugins and their
    data): copy only `appearance.json`, `themes/`, and `snippets/`. (All 11 vaults are
    on the full standard as of 2026-07-16.)
  - **"Seed a new standard [from vault Y]"**: David tunes Y (usually hermes) in the
    Obsidian UI, then: copy Y's `.obsidian` over the template minus `workspace*.json`/
    `cache`, commit dotfiles with a "vault-template rev N" message, and propagate to
    other vaults only on request (full-stamp for blanks, theme-only for customized).
- **Synced vaults (Syncthing ↔ VPS): only `hermes`** (David+Atlas — personal/feeds/brain/
  TaskNotes) **and `axiom`** (work), both served by the single syncthing-hermes container.
  CC project vaults are Mac-local by design — do not add shares for them unless asked.
- **Exceptions:** projects on `/Volumes/1TB Media` (Erato, Sizes) get NO vault under
  `~/Obsidian/` and never sync. Erato does keep its own on-volume vault at
  `/Volumes/1TB Media/Erato` (standard config applied 2026-07-17) — include it in
  standard-config propagations when the volume is mounted, but never inspect its
  content, never relocate it, never add a share. Repo-tracked docs (docs/plans,
  docs/solutions, CLAUDE.md, HANDOFF.md) stay in their repos — vaults are for notes
  that aren't code-adjacent.

## Reasoning

On non-trivial decisions, briefly explain your reasoning before acting. If you notice
an architectural concern — even if it's outside the immediate task scope — raise it.
The value is in the conversation, not just the implementation.

## Narration & Verbosity

Cut filler. State findings and conclusions directly; do not wrap them in preamble,
self-narration, or emphasis that carries no information. The reasoning above is about
*substance* — surfacing real trade-offs and concerns — not about narrating the act of
reasoning.

Specifically, do not write:
- **Process-narration preambles** — "let me verify the actual state rather than just
  reciting…", "Here's the picture", "Let me think through this." **Any "Let me …" opener
  that narrates the next action is banned** — just do the thing and report what you found.
  This covers *mid-task* narration around tool calls ("Let me check where the review
  stands," "Let me pull the rest from the live dataset," "Let me find out exactly why"),
  not only final prose. A one-line background-task *status* update is fine; a narrated
  intention to run the next step is not.
- **Emphatic editorializing** — "and it's not cosmetic", "this is the whole game",
  "the honest truth is", "make no mistake." If a point matters, the facts show it.
- **Framing throat-clearing** — "So the honest answer:", "The key insight is:",
  "At the end of the day." Lead with the answer instead.

Test each sentence: if deleting it loses no fact, claim, or option the user needs,
delete it. Confidence comes from precise facts, not from rhetorical signaling.

## Data Safety

Never delete user data (files, records, database entries, folders, notes) without explicit user approval.
Even if content seems out of scope or inappropriate, ask before removing. The cost of unauthorized
deletion is far higher than the cost of asking.

## Git Discipline

**Never commit directly to the default branch (main/master) — always work on a branch**
(standing order, 2026-07-23). Branch (`feat/…`, `fix/…`, `chore/…`, `docs/…`) → commit →
merge (PR where the repo has a remote review flow; local merge where it doesn't). Applies
to every repo, including data vaults and doc-only commits (handoff commits ride a branch
too). Repos with their own stricter rules (e.g. skills-private's PR-only flow) keep them.

## Code Review

**Adversarial code review → invoke `dv:gauntlet`** (dv suite ≥ 0.2.0, installed user-scope, so it
resolves in every project); do **not** hand-roll `codex exec review` or Claude↔Codex review loops.
Bare `dv:gauntlet` is the full autonomous find→refute→fix→commit loop (staged, cost-tiered,
budgeted); `dv:gauntlet report` is a single report-only round. The skill owns the procedure —
rounds, budgets, the fingerprint ledger, stop rules, read-only peer runs — so don't re-derive it
per project.

**This holds even under `/effort ultracode` or dynamic workflow orchestration, and even when
another project's vault or SOP describes its own `codex exec review`/Claude↔Codex loop** — those
are superseded by `dv:gauntlet`, so discovering one elsewhere does not override the standing tool.
Custom multi-agent workflows may supply research or critique *lenses* upstream, but the adversarial
review of your own diff still routes through `dv:gauntlet` (bare for your own branch, `report` for a
read-only pass on someone else's). If you catch yourself about to "fan out reviewers," "spin up a
skeptic panel," or "drive the Codex loop," stop and invoke `dv:gauntlet` first.

## Subagents

**Skill-specified subagents are authorized by invoking the skill (added 2026-08-05).** A harness
rule of the form "don't use the Agent tool unless asked" does **not** block subagents that an
invoked skill's own procedure requires — invoking the skill *is* the request. Outside a skill's
specified procedure the default still holds: don't spawn agents unsolicited.

**Why this is a carve-out and not a loosening.** These skills buy *independence*, and faking it is
invisible in the output. `dv:gauntlet`'s S2 REFUTE validators are specified fresh-context precisely
so they carry no commitment to the finding they judge; `dv:critique`'s three lenses are worthless if
one mind wears all three hats, since the Skeptic would have already read the Simplifier's reasoning.
Run in-context, both still emit correctly-shaped reports — labeled sections, verdicts, a convergence
table — with none of the independence. There is no artifact-level tell, so the degradation is
unfalsifiable from the outside. (Observed live 2026-08-05: a full gauntlet report looked complete
and had to be disclosed in prose.)

**Announce fan-out before spawning** when a skill's procedure calls for **more than ~3 agents, or an
unbounded batch** (e.g. `ce-code-review` dispatches a roster "sized to the host's active-agent cap").
One line naming the skill and the agent count, before the spawn — not after. Small, fixed fan-outs
(`dv:critique`'s 3, `dv:gauntlet`'s per-finding validators) need no announcement. The point is that
cost is unpredictable exactly where the batch is unbounded, and subagent output never enters the
main context, so an unannounced fleet is spend you cannot see or check.

## Durable Rules vs Handoff Notes

A rule, gotcha, or standing procedure discovered mid-session that has value *beyond* "what happened
this session" belongs in the project's `AGENTS.md`/`CLAUDE.md` or `docs/solutions/` **at the moment
it's discovered** — not deferred to `HANDOFF.md`. `dv:handoff` overwrites HANDOFF wholesale each run
(no history), so a durable rule parked only there is one handoff away from being lost, and the
handoff itself drifts from reality between writes. If you find yourself writing "the rule we
established this session" into HANDOFF, stop and also land it in the durable doc.

## Research

When you hit a wall — unfamiliar tool, unknown API, missing docs — always perform a web search
before giving up or saying "I don't know." The WebSearch tool is available and should be your
default fallback for anything outside your training data.

## Web Tool Ladder

Three tiers, in order. Reach for the lowest tier that can actually answer the question.

1. **`WebFetch`** — default. Static HTML, server-rendered pages, doc URLs, READMEs, anything
   `curl` would handle. Free and fast. **Machine-readable JSON/registry endpoints (npm
   registry, GitHub API, crates.io, PyPI, etc.) stay at this tier even for "current
   version" facts** — they return authoritative structured data, so tier 2 buys nothing
   there. Reserve the tier-2 preference for pages that need JS rendering or an
   authenticated/live session state a JSON endpoint can't give you.
2. **Obscura (`browse-gateway` MCP)** — preferred for any fetch where WebFetch isn't sufficient
   *and* for **realtime-fact queries** (prices, stock state, "as of today" claims, current-event
   facts, current external-system configuration, current package versions, anything phrased as
   "today" / "right now" / "current" / "as of this writing"). Real browser, JS rendering, anti-bot
   bypass, residential proxies. The user prefers it over the stricter `dv:cite` contract for
   everyday realtime fetches. **When using it for a realtime-fact query, apply the freshness
   discipline manually:** quote only what is literally in the fetched page, attach source URL +
   fetch timestamp to the quote, or decline with a reason. Same contract as `dv:cite` — just
   enforced by you, not the skill.
   > ⚠️ **Obscura is David's branding. It ships as the MCP server named `browse-gateway`.**
   > Nothing on disk is named "obscura" — no binary, no skill, no config string. Searching for
   > the brand name will wrongly read as "not installed." Load the tools with
   > `ToolSearch("select:mcp__browse-gateway__retrieve")` or `+browse-gateway`.
   >
   > - **`mcp__browse-gateway__retrieve`** — the default. Reads any URL as clean markdown
   >   through a stealth browser that clears Cloudflare / anti-bot / CAPTCHA and rotates a
   >   clean residential IP on hard blocks. `forceProxy: true` routes through the residential
   >   proxy from the first request, for known-hostile hosts. **Prefer this for reading a page.**
   > - **`browser_open` / `browser_navigate` / `browser_snapshot` / `browser_click` /
   >   `browser_type` / `browser_select_option` / `browser_press_key` / `browser_wait_for` /
   >   `browser_take_screenshot` / `browser_close`** — stateful drive session, for *interaction*
   >   only (clicks, forms, multi-step flows). Snapshots are ref-annotated; pass `[ref=…]` as
   >   `target`. A warm logged-in session is pinned to one owner host — open a separate session
   >   per host. `browser_close` is idempotent.
   >
   > **Availability is per-project, not global (as of 2026-08-07).** `browse-gateway` is
   > configured only in `~/Projects/agents` and `/Volumes/1TB Media/Erato`. In any other project
   > the tools will not resolve. When they don't, add the server for that project rather than
   > silently dropping to tier 1 — or tell David it isn't wired up there. The root-level MCP
   > entry is still the retired `browserbase`; treat it as dead, not as a fallback.
   >
   > **Obscura has no search API.** It retrieves and drives; it does not return SERPs. For
   > *finding* candidate URLs, WebSearch remains the only path — and a fact lifted from a SERP
   > snippet is still not a verified fact. Fetch the candidate with `retrieve` before quoting it.

   **Browserbase is retired as of 2026-08-07 — do not reinstall or suggest it.** Obscura
   replaced it. The `browser`, `browserbase-cli`, and `browser-trace` skills were deleted on the
   VPS; **on this Mac `browser` and `browserbase-cli` are still present and are dead weight** —
   do not route through them. Skills still Browserbase-shaped and not yet repointed:
   `search` (unfixable — Obscura has no search API; use WebSearch → `retrieve`),
   `company-research`, `event-prospecting`, `ui-test`, `autobrowse`, `safe-browser`,
   `what-antibot`, `agent-browser`. Structurally obsolete with no Obscura equivalent:
   `functions`, `cookie-sync`. Already repointed and working: `fetch`, `dv:cite`/`verify-cite`.
3. **`dv:cite`** — strict-contract fallback. Use when the user explicitly asks for a
   verified citation, when a claim is high-stakes (financial, medical, legal, public-record),
   or when you want the skill itself to enforce fetch-fresh + substring-assert + freshness-tag-
   or-decline rather than relying on your own discipline. Also the right tool when a fact came
   from training data and you have specifically not yet fetched a current source for it.

**On a failed primary-source fetch for a realtime fact, escalate (tier 1 → tier 2) or decline —
do not fall back to an untagged secondary source.** A 500/blocked official page means "try the
browser tier, or say you couldn't confirm," not "cite a third-party blog as if it were the source."
Anything you do surface still carries its own source URL + fetch timestamp, per the freshness
discipline above.

**Never quote a realtime fact from training data without a freshness tag.** WebSearch returns
SERP snippets that are stale-by-design and do not satisfy the freshness contract — it is fine
for *finding* candidate URLs but a fact lifted from a search snippet is not a verified fact.
When the user asks for a *specific current fact*, route through tier 2 or tier 3, not WebSearch
alone.

The ladder is for *realtime fetches*, not general reasoning, code review, design discussion, or
summarization of static reference material — those don't need a fetch at all. When in doubt
about whether a query is realtime, prefer fetching (false-positive fetches are recoverable;
silent confabulations from stale training data are not).

**A coding task does not exempt a realtime fact.** A model ID, package version, API endpoint,
pricing figure, or deprecation status is a realtime fact even when the surrounding work is
writing code — and *especially* when the value is about to be committed, where a wrong one ships
silently and fails later at runtime. "This model is stale, the current one is X" is exactly the
claim that needs grounding, not an incidental code edit. For Anthropic model IDs, pricing, and
capabilities specifically, load the `claude-api` skill — it carries the current tables and its own
never-answer-from-memory rule.

## Reddit Content

Use the `dv:reddit` skill to fetch Reddit posts and comments. Never use WebFetch for Reddit URLs.

## Time & Session Continuity

The user runs in **PST/PDT**. When citing or reasoning about time:
- Always be explicit about PST vs UTC; never ambient-translate between the two
- Derive day-of-week from the system-provided date; never guess
- Don't layer on "late / morning / evening" framing unless wall-clock evidence supports it (4pm is not "late")

`dv:pickup` is often a context-hygiene move, not a new day. Sessions are routinely back-to-back —
the user clears the window to reduce cached-context cost and avoid pollution. Before defaulting
to "overnight" / "tomorrow" / "next morning" framing, check HANDOFF mtime, recent commit
timestamps, and any continuation cues in the conversation. If signals say same-session,
say so explicitly instead of pretending it's been hours.

## Personal Boundaries

**Never tell the user when to sleep, rest, eat, or otherwise manage their personal time.**
This includes phrasings like "sleep well," "go to bed," "get some rest," "sleep on it,"
"genuinely sleep," "you should sleep," etc. — across all projects, all sessions.

The user manages their own life. When work is wrapping up or the user mentions being tired,
on mobile, in bed, etc., end the conversation cleanly without prescribing what they should do
with their body or schedule. A neutral sign-off ("standing by," "talk tomorrow," "I'll be here")
is fine. Anything that reads as advice about rest is not.

## Proof Document Editor

**Proof default mode: `collaborative_docs`** (set 2026-04-28).

When creating new markdown docs, route to Proof by default if the doc is collaborative —
plans, specs, bug writeups, reports, memos, proposals, drafts, or similar iterative docs.
Code-adjacent local documentation (READMEs, `docs/solutions/`, and repo-tracked `docs/plans/` /
`docs/brainstorms/`, repo-tracked CLAUDE.md/AGENTS.md, repo-tracked HANDOFF.md, etc.) stays local —
the three CE-convention directories (`plans`/`brainstorms`/`solutions`) are one in-repo set.
Existing repo-tracked markdown stays local unless the user explicitly asks to move or share it via
Proof. (The `ce-plan`/`ce-brainstorm`/`ce-ideate` skills route *their* plan/brainstorm docs to
Proof via the `ce-proof` wrapper — that's a separate, deliberate path and is unaffected by this
exemption, which is about ad-hoc docs you write straight into a repo's `docs/` tree.)

The `proof` skill (`~/.claude/skills/proof/SKILL.md`) has the API details. The `compound-engineering:ce-proof`
skill is a separate wrapper used by ce-brainstorm / ce-plan / ce-ideate handoffs.

**Naming convention for new Proof docs (set 2026-04-30).** Apply at create time so the user's
homepage sorts cleanly without manual library curation. Alphabetic sort groups by category:

| Category | Prefix | Example |
|---|---|---|
| Agent SOULs | `SOUL — <Persona>` | `SOUL — Atlas` |
| Long-lived reference | `Reference: <Name>` | `Reference: Operating Model` |
| Implementation plans | `Plan: <YYYY-MM-DD> <topic>` | `Plan: 2026-04-29 meeting-sweep skill` |
| Brainstorms / requirements | `Brainstorm: <YYYY-MM-DD> <topic>` | `Brainstorm: 2026-04-29 meeting-sweep skill` |
| In-progress drafts | `Draft: <topic>` | `Draft: weekly review template` |
| Deprecated / superseded | `~Deprecated: <orig name>` | `~Deprecated: SOUL — Atlas (orphan)` (`~` sorts last) |

Use the schema for the *initial title* when calling `POST /share/markdown`. Don't try to retitle
existing docs — see API limitation below.

**Proof API limitations to know (don't re-discover these):**
- **Lifecycle ops are gated behind native-client headers.** Delete, archive, rename title,
  move-to-folder all return `426 CLIENT_UPGRADE_REQUIRED` from the agent API. Library curation is
  UI-only; the user has reported the UI also doesn't expose these operations cleanly. The agent
  API surface is purely: read state, edit content (`/edit/v2`, `/ops`), comments, suggestions,
  rewrites. No library/lifecycle management.
- **Apply button on suggestions is unreliable in some Proof UIs.** Resolve closes the comment
  but does not apply the attached suggestion. See
  `~/.claude/projects/-Users-dvillavicencio-Projects-agents/memory/proof_apply_button_unreliable.md`.
  Default to direct prose editing or API-level `suggestion.accept`; mandatory pre-push grep before
  syncing back to source.
