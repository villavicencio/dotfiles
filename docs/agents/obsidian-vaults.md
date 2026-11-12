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
  3. Stamp the standard config: `cp -R ~/Projects/obsidian-scriptorium/standard/.obsidian ~/Obsidian/<name>/.obsidian`
  4. Append the "## Vault" declaration to the project's CLAUDE.md/AGENTS.md (copy the
     shape from `~/Projects/agents/CLAUDE.md`).
  (David registers it in Obsidian's UI via "Open folder as vault" whenever he wants it.)
- **Standard vault config and theming** belong to the private repo
  `villavicencio/obsidian-scriptorium` (`~/Projects/obsidian-scriptorium`, agent Scribe,
  Linear project Scriptorium) since 2026-11-11. The standard is its `standard/.obsidian/`;
  rev 1 is the template that used to be `obsidian/vault-template/` here (harvested from
  hermes 2026-07-15), copied byte for byte. Changing a theme, snippet, plugin or plugin
  setting, applying the standard to a vault, and seeding a new standard are Scribe's work:
  the procedures and rules are in that repo's `CLAUDE.md`. This file keeps what dotfiles
  still owns: where vaults live, the memory symlink, the bootstrap, and the hal mirror.
  - 17 vaults on 2026-11-11. 15 are on the standard, `hermes` is the standard plus
    `gridexplorer`, and `syd` has its own config and is outside Scribe's scope.
- **Synced vaults (Syncthing ↔ VPS): only `hermes`** (David+Atlas — personal/feeds/brain/
  TaskNotes) **and `axiom`** (work), both served by the single syncthing-hermes container.
  CC project vaults are Mac-local by design — do not add shares for them unless asked.
- **Projects that live on hal** (as `david`: `skills`, `bryancola.com`, `hal-bench`) write memory on hal,
  at `/Users/david/.claude/projects/<slug>/memory/`, which is a real folder there (hal has no
  Obsidian). The LaunchAgent `com.dvillavicencio.hal-memory-pull` copies each one hourly into
  `~/Obsidian/<vault>/memory/` on the personal Mac (`skills` → `skills`, `bryancola.com` →
  `bryancola`, `hal-bench` → `hal-bench`). It's one-way: the vault is a read-only mirror, and an edit made there is
  replaced on the next run, even if nothing changed on hal. The replaced folder moves to
  `~/Obsidian/<vault>/.sync-backup/<UTC stamp>.<suffix>/memory/` rather than being
  deleted. A project moved to hal gets a row in the table in `helpers/hal_memory_pull.sh`, then
  `bash helpers/install_hal_memory_pull.sh` (personal Mac only, from the main checkout). The
  installer creates the vault with the standard config and reloads the job. Log:
  `~/Library/Logs/hal-memory-pull.log`. Not rsync: the Mac's `/usr/bin/rsync` is openrsync,
  which exited 0 without updating a changed file when tested (2026-10-21).
- **Repo-tracked docs** (docs/plans, docs/solutions, CLAUDE.md, HANDOFF.md) stay in
  their repos — vaults are for notes that aren't code-adjacent.
