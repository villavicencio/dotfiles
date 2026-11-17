---
created_at: "2026-11-16T16:39:58-08:00"
branch: "master"
head: "0ce43ba"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-16, afternoon (PT)

A long session from 2026-11-13 to 11-16. It started as housekeeping (MCP sign-ins, a plugin, the Linear backlog, both dotfiles clones on hal), then David made Manager Mode the standing way of working in this repo, and the rest was VIL-700 run that way: the main session as manager, Opus leads doing the engineering. Part 1 of VIL-700 is merged. Part 2 waits on four steps only David can do, and on his go.

## What We Built
- **PR #270** (`0ce43ba`), part 1 of VIL-700: `helpers/add_hal_as_hal_key.sh` adds the Mac's main public key to the `hal` account on hal, and `ci/hal-as-hal-key-checks.sh` checks it by hand (21 checks, pass from the main checkout). The helper has never run against hal; David's run is the first. Setup steps, exit codes and recovery are in `docs/reference/install-and-server.md`, "Reaching hal as `hal`".
- **PR #269** (`25ed90c`): `model` and `theme` are machine-local settings. The list lives in two places that must match, `STRIP_KEYS` in `helpers/lib/claude-settings-keys.sh` and `MACHINE_LOCAL` in `helpers/migrate_claude_settings.py`; `dot check` fails if they differ.
- **PR #267** (`b4ce800`): the synced `product-management` plugin is off in `claude/settings.json` and `windows/claude-settings.json`. David never used its skills.
- **Linear, Dotfiles backlog groomed:** VIL-273 (now "hal: monitoring, phone alerts and backups", High, rewritten as an ordered plan), VIL-426, VIL-539, VIL-581 retitled or updated. VIL-736 filed: the server profile should skip install steps an account can't do.
- **Memory:** `feedback_manager_mode_sop.md` holds David's Manager Mode text and four notes learned in use. Its index line in `MEMORY.md` says to read it at session start.
- **hal:** both dotfiles clones (`david`'s and `hal`'s) were pulled and installed at `b4ce800` on 2026-11-14. `master` has moved four commits since; neither clone was pulled again.

## Decisions Made
- **Manager Mode is standing procedure in dotfiles** (David, 2026-11-14, until he says otherwise). The main session never edits code, tests, config, repo docs or scripts. One Opus lead at high effort per unit of work; it may use Sonnet sub-agents. The manager still does memory, Linear, PR bodies, and existing commands (git, gh, tests, merge, `mergewren_review`, `wt`).
- **VIL-700 design, all David's picks:**
  - David runs the key helper himself; agents do not add keys.
  - `david` owns the one shared dotfiles clone on hal, and `hal`'s links point into it. He chose this against the security recommendation (that `hal` own it). Recorded on the ticket; not to be reopened.
  - Replace Atlas's dotfiles sync-check job rather than patch it, and add a tamper alarm to the replacement.
  - `hal`'s `~/.claude/CLAUDE.md` becomes a link; the current regular file is kept beside it as `.pre-vil700`.
  - Installer changes for the shared clone go to VIL-736, not VIL-700.
  - `hal` never gets a lasting `safe.directory` entry for the shared clone.
- **After setup, agents act as `hal` only through `ssh hal-as-hal`**, never `hal-orca` or `hal-svc` (rule in `CLAUDE.md` and `AGENTS.md`). The read-only use of `hal-orca` David approved for the phase 1 lead ended with phase 1.
- **One MergeWren finding on #270 was declined** (medium, `564cb09#1`): when making the backup fails and removing the failed backup also fails, the helper does not name the leftover file. `authorized_keys` is untouched in that case. Reason is on the thread and in the PR body. The two-line warning is owed in the part 2 PR.

## What Didn't Work
- **A long shell command in a doc.** The first version of the key step was a pasted command. MergeWren found a new hole in it every round (matching the key body only, a missing final newline, a hidden `ssh-keygen` failure). It became a tracked helper with a check script, and the findings stopped. #270 took seven fix rounds; four were doc wording.
- **A fact from a handoff, passed to a lead unchecked.** The last handoff said hal's pilot window ends 05:00 PT. The repo says 06:00 (`docs/reference/hermes-commands.md`). The wrong time went into a doc and cost a review round.
- **`wt done` on a lead's worktree.** A lead that runs `dot check` initializes the `dotbot` submodule, and `wt done` then refuses. The path that works is in the memory file and in `docs/agents/code-review.md`.
- **`claude mcp remove` on a claude.ai connector.** It can't; connectors are removed at claude.ai settings. David removed Strava there.
- **`./install` as `david` on hal** exits 1 at `brew bundle`, because `hal` owns Homebrew. Expected; this is VIL-736.

## What's Next
1. **David's four steps for VIL-700**, on the personal Mac, in iTerm2, from the main checkout. They are listed in the last comment on VIL-700 and in the doc section named above:
   1. `bash helpers/add_hal_as_hal_key.sh` (`DOTFILES_DRY_RUN=1` first to preview). Exit 3 means the key is already there with other options; it changes nothing and that case is David's call.
   2. Paste the `Host hal-as-hal` block into `~/.ssh/config`, above `Host *`.
   3. `ssh -o BatchMode=yes hal-as-hal 'id -un'` prints `hal`.
   4. Add `Bash(ssh hal-as-hal:*)` to `permissions.allow` in `~/.claude/settings.json`.
2. **VIL-700 part 2, after those steps and David's go.** Dispatch a fresh Opus lead with a full brief. The runbook: pull both clones to one commit; let `hal` pass through `david`'s home directory; replace the Atlas sync-check job, with the tamper alarm; re-point `hal`'s 23 links; link `hal`'s `CLAUDE.md`; verify; leave it one night; then move the old clone aside. The old clone is moved, never deleted. Keep clear of 01:30 to 06:00 PT and 18:00 PT. The PR also owes: the declined warning above, the shared-clone docs, and the setup lines in `docs/agents/1password.md` that are now stale. Branch `<type>/vil-700-<slug>`; the merge will close VIL-700 again, so reopen it if work remains.
3. **VIL-736** (Todo, Low), after part 2.
4. **Carried since 2026-11-10, still untouched and unticketed:** the Garmin 502s; whether Hermes on hal is up; the MergeWren stopgap watcher after hal's reboot on 2026-11-11; the `compinit` fix for this Mac. Either ticket them or drop them.

## Gotchas & Watch-outs
- **Phase 1 findings the part 2 lead needs** (full report is in the VIL-700 comments):
  - `hal` cannot enter `david`'s home directory (mode 700). The fix is one ACL entry, run as `david`.
  - Atlas's cron job `637debb93470` runs `git fetch` in `hal`'s own clone. It must be replaced before that clone moves.
  - The `hal-orca` key is pinned to the Mac's one tailnet IPv4 address. The helper pins the new key the same way, so a connection over IPv6 would be refused.
  - `./install` as `hal` from a clone `david` owns is predicted to fail at steps that write into the repo. Not tested.
- **The lead's draft scripts for part 2 are not in the repo.** Copies are in the untracked handoff store, `.git/handoffs/vil-700-phase2-scratch/` in the main checkout: the replacement sync-check (`04`), the relink (`05`) and its rollback (`06`). They are drafts no reviewer has seen. `01-add-key.sh` there is stale (it calls into a removed worktree); use the helper.
- **A lead's report reaches the manager with `<`, `>` and `&` HTML-escaped.** Never copy a command for David out of a report. Have the lead write commands to files.
- **Another session owns `.claude/worktrees/vil-721-hal-memory-sections`** (detached HEAD). Leave it. That session also asked that nobody run `bash helpers/install_hal_memory_pull.sh`; the hal-bench vault is superseded by VIL-733, VIL-721 and VIL-723. David said to wait on the vault.
- **macOS CI runners:** GitHub twice failed to assign an arm64 macOS runner to #270 and cancelled the leg. A re-run passed. Not caused by the change.
- **`browse-gateway` (Obscura) did not connect** in this session (connection refused). Check its tunnel job before relying on it.
- **hal's swap was 14.3 of 15.4 GB on 2026-11-14.** Not looked at since. VIL-273 covers monitoring; its runbook path is missing on the Mac.
- **Carried over:** never `./install` from a worktree; never run `npx … remote` by hand while the Desktop Commander agent is loaded; a merge closes any VIL ticket its branch or PR names, so re-check a multi-part one.
