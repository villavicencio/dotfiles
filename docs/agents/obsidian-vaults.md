# Per-agent Obsidian vaults (Mac)

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

Standard rev. 2026-07-15; supersedes the one-day one-vault experiment.

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
- **Repo-tracked docs** (docs/plans, docs/solutions, CLAUDE.md, HANDOFF.md) stay in
  their repos — vaults are for notes that aren't code-adjacent.
