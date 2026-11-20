# The Obsidian vault (Mac)

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

Standard rev. 2026-11-19 (VIL-727): one vault with a section per project; supersedes the vault-per-project standard of 2026-07-15.

The vault is `~/Obsidian/scriptorium/`. Each project's notes and memory live in its section,
which is a top-level folder. Section names may change (VIL-742). A project's own
instructions (its `CLAUDE.md`/`AGENTS.md`, `## Vault`) name its section.

- Every agent may read the whole vault. Each section belongs to another agent, so read it
  as theirs.
- An agent writes only in its own section, `~/Obsidian/scriptorium/<section>/`. To leave a
  note for another section's owner, write it in that section's `<section>/inbox/`.
  Nowhere else.
- `david/` is David's. Any agent may create and edit notes anywhere in it without asking.
  Deleting, moving or renaming a note, or a bulk rewrite (the same change across more than
  about five notes), needs a plan shown to David and his go. `david/inbox/` is where to
  leave him a note. The Matter plugin writes `david/Matter` and may overwrite an edit made
  there.
- Agents on hal write nothing in the vault while hal's copy is download-only.
- `syd` is a separate vault and stays out of these rules.
- Source of these rules: obsidian-scriptorium `CLAUDE.md`, "Direction" (decided by David
  on 2026-11-19, VIL-727).

- Claude Code projects keep harness memory *physically in their vault*:
  `~/.claude/projects/<slug>/memory` is a **symlink** to `~/Obsidian/scriptorium/<section>/memory`.
- **New-project bootstrap** — a new Mac CC project gets a section, not a vault:
  1. Check that the vault is set up on this Mac and that `~/Obsidian/scriptorium` is a real
     folder, not a symlink:
     `test ! -L ~/Obsidian/scriptorium && test -d ~/Obsidian/scriptorium/.obsidian`.
     If it fails, stop and tell David the vault isn't set up here. Setting it up is
     Scribe's work in the obsidian-scriptorium repo; don't create the folder yourself.
  2. Ask David for the section's name (until VIL-742 settles names).
  3. `mkdir -p ~/Obsidian/scriptorium/<section>/memory ~/Obsidian/scriptorium/<section>/inbox`
  4. If `~/.claude/projects/<slug>/memory` exists as a real dir, move its contents into
     the section's `memory/`; either way replace it with a symlink to it.
  5. Add a `## Vault` section to the project's `CLAUDE.md`/`AGENTS.md` naming its section.
  There is no `.obsidian` stamp to add; step 1 confirms the vault already has one.
- **Standard vault config and theming** belong to the private repo
  `villavicencio/obsidian-scriptorium` (`~/Projects/obsidian-scriptorium`, agent Scribe,
  Linear project Scriptorium) since 2026-11-11. The standard is its `standard/.obsidian/`;
  rev 1 is the template that used to be `obsidian/vault-template/` here (harvested from
  hermes 2026-07-15), copied byte for byte. Changing a theme, snippet, plugin or plugin
  setting, applying the standard to a vault, and seeding a new standard are Scribe's work:
  the procedures and rules are in that repo's `CLAUDE.md`. This file keeps what dotfiles
  still owns: the vault's layout and write rules, the memory symlink, the bootstrap, and
  the hal mirror.
  - 17 vaults on 2026-11-11. 15 are on the standard, `hermes` is the standard plus
    `gridexplorer`, and `syd` has its own config and is outside Scribe's scope.
- **Synced vaults (Syncthing ↔ VPS): only `hermes`** (David+Atlas — personal/feeds/brain/
  TaskNotes) **and `axiom`** (work), until they migrate into the vault; both are served by
  the single syncthing-hermes container. Project sections are Mac-local by design — do not
  add shares for them unless asked.
- **Projects that live on hal** (as `david`: `skills`, `bryancola.com`) write memory on hal,
  at `/Users/david/.claude/projects/<slug>/memory/`, which is a real folder there (hal has no
  Obsidian). The LaunchAgent `com.dvillavicencio.hal-memory-pull` copies each one hourly into
  a section of the one vault: `~/Obsidian/scriptorium/<section>/memory/` on the personal Mac
  (`skills` → `skills`, `bryancola.com` → `bryancola`; VIL-721). It's one-way: the section's
  `memory/` is a read-only mirror, and an edit made there is replaced on the next run, even if
  nothing changed on hal. The replaced folder moves to
  `~/.local/state/hal-memory-pull/backups/<section>/<UTC stamp>.<suffix>/memory/`, outside the
  vault, rather than being deleted.
  - The job writes only `<section>/memory`. It never creates the vault, a section or an
    `.obsidian`: obsidian-scriptorium's `bin/migrate` makes each section, and refuses one it
    didn't place. A section that doesn't exist yet is skipped and logged every run.
  - **Cutover state.** Until VIL-723 runs the cutover, the copy installed on the Mac is an older
    one that writes `~/Obsidian/<vault>/memory/` and keeps backups in
    `~/Obsidian/<vault>/.sync-backup/`, and `bin/migrate` refuses a vault that has that folder.
    The order is: stop the job, move `.sync-backup/` out of the old vault, `bin/migrate <vault>`,
    then install the job from `master`. Installing it any earlier is safe but stops the old
    vault's mirror. `bash helpers/install_hal_memory_pull.sh --check` reports each section and
    writes nothing.
  - A project moved to hal gets a row in the table in `helpers/hal_memory_pull.sh` and needs its
    section in `scriptorium` first, then `bash helpers/install_hal_memory_pull.sh` (personal Mac
    only, from the main checkout) reloads the job. `hal-bench` writes memory on hal but has no
    section, so it has no row and isn't mirrored (it never was: its row was added in #247, but
    the job was never reinstalled with it).
  - Log: `~/Library/Logs/hal-memory-pull.log`. It gets a line for each change and each
    failure. Some lines repeat on every run while their cause lasts, though the run succeeds:
    a section that doesn't exist yet, a memory folder that is missing or empty on hal, and a
    run skipped because another holds the lock. An unchanged mirror logs nothing. `~/.local/state/hal-memory-pull/` must be on the same volume as each section the job
    writes and its `memory/` (the job checks before each swap and refuses otherwise; the
    installer checks before loading the job), so each swap is a rename, never a copy. An
    `Operation timed out` from ssh is the network (the Mac just woke, or hal or Tailscale was
    unreachable), not the job; the next hourly run catches up. Tests:
    `ci/hal-memory-pull-checks.sh` (temp folders, fake ssh, stub launchctl). Not rsync: the
    Mac's `/usr/bin/rsync` is openrsync, which exited 0 without updating a changed file when
    tested (2026-10-21).
- **Repo-tracked docs** (docs/plans, docs/solutions, CLAUDE.md, HANDOFF.md) stay in
  their repos — vaults are for notes that aren't code-adjacent.
