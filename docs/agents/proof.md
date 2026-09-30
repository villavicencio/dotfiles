# Proof document editor

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

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

The `proof` skill (`~/.claude/skills/proof/SKILL.md`, also in `~/.agents/skills/proof/`) has the API details. The `compound-engineering:ce-proof`
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
