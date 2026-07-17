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
- **Exceptions:** projects on `/Volumes/1TB Media` (Gooner, Sizes) get NO vault under
  `~/Obsidian/` and never sync. Gooner does keep its own on-volume vault at
  `/Volumes/1TB Media/Gooner` (standard config applied 2026-07-17) — include it in
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
  reciting…", "Here's the picture", "Let me think through this." Just do the thing and
  report what you found.
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

## Research

When you hit a wall — unfamiliar tool, unknown API, missing docs — always perform a web search
before giving up or saying "I don't know." The WebSearch tool is available and should be your
default fallback for anything outside your training data.

## Web Tool Ladder

Three tiers, in order. Reach for the lowest tier that can actually answer the question.

1. **`WebFetch`** — default. Static HTML, server-rendered pages, doc URLs, READMEs, anything
   `curl` would handle. Free and fast.
2. **`browser` skill (Browserbase)** — preferred for any fetch where WebFetch isn't sufficient
   *and* for **realtime-fact queries** (prices, stock state, "as of today" claims, current-event
   facts, current external-system configuration, current package versions, anything phrased as
   "today" / "right now" / "current" / "as of this writing"). Real browser, JS rendering, anti-bot
   bypass, residential proxies. The user has generous Browserbase usage and prefers it over the
   stricter `/verify-cite` contract for everyday realtime fetches. **When using `browser` for a
   realtime-fact query, apply the freshness discipline manually:** quote only what is literally
   in the fetched page, attach source URL + fetch timestamp to the quote, or decline with a
   reason. Same contract as `/verify-cite` — just enforced by you, not the skill.
3. **`/verify-cite`** — strict-contract fallback. Use when the user explicitly asks for a
   verified citation, when a claim is high-stakes (financial, medical, legal, public-record),
   or when you want the skill itself to enforce fetch-fresh + substring-assert + freshness-tag-
   or-decline rather than relying on your own discipline. Also the right tool when a fact came
   from training data and you have specifically not yet fetched a current source for it.

**Never quote a realtime fact from training data without a freshness tag.** WebSearch returns
SERP snippets that are stale-by-design and do not satisfy the freshness contract — it is fine
for *finding* candidate URLs but a fact lifted from a search snippet is not a verified fact.
When the user asks for a *specific current fact*, route through tier 2 or tier 3, not WebSearch
alone.

The ladder is for *realtime fetches*, not general reasoning, code review, design discussion, or
summarization of static reference material — those don't need a fetch at all. When in doubt
about whether a query is realtime, prefer fetching (false-positive fetches are recoverable;
silent confabulations from stale training data are not).

## Reddit Content

Use the `/reddit` command to fetch Reddit posts and comments. Never use WebFetch for Reddit URLs.

## Time & Session Continuity

The user runs in **PST/PDT**. When citing or reasoning about time:
- Always be explicit about PST vs UTC; never ambient-translate between the two
- Derive day-of-week from the system-provided date; never guess
- Don't layer on "late / morning / evening" framing unless wall-clock evidence supports it (4pm is not "late")

`/pickup` is often a context-hygiene move, not a new day. Sessions are routinely back-to-back —
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
Code-adjacent local documentation (READMEs, docs/solutions/, repo-tracked CLAUDE.md, repo-tracked
HANDOFF.md, etc.) stays local. Existing repo-tracked markdown stays local unless the user
explicitly asks to move or share it via Proof.

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
