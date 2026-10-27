---
created_at: "2026-10-27T15:06:24-07:00"
branch: "master"
head: "5286b4a"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "morning check of the first hal-pilot batch (runner.log, run.json, [pilot] PRs in mergewren) and close VIL-515 if the 01:30 run started from ~/Projects/hal-pilot"
---
# HANDOFF — 2026-10-27, afternoon (PDT)

This session moved the hal pilot runner out of dotfiles into its own private repo (VIL-515), fixed two auto-mode classifier blocks at their root, and restarted the pilot's measurements by queueing a batch of 8 mergewren tickets. The pilot queue had been empty since the 01:30 PT run on Sun 10-25, so the 10-26 and 10-27 runs measured nothing.

## What We Built
- **`villavicencio/hal-pilot`** (private): `pilot/`'s 8 commits (subtree split, gitleaks clean), plus `375041f` (paths now `~/Projects/hal-pilot`) and `8b6df58` (project `CLAUDE.md`: hal's clone is production, deploy = `git -C ~/Projects/hal-pilot pull --ff-only` as `david`, test on hal in a scratch clone, token never covers this repo). David has since added more lines to that `CLAUDE.md` himself (`docs/solutions`, `ce-compound`, `ce-noslop`).
  - **On hal (`david`):** cloned to `~/Projects/hal-pilot`, `install.sh` run. David reloaded `dev.hal.pilot` as `admin`, and `launchctl print` shows `/Users/david/Projects/hal-pilot/runner.py`. The dry run from the new path ended `dry-run`.
  - **On this Mac:** cloned to `~/Projects/hal-pilot`, added to Orca, vault `~/Obsidian/hal-pilot/` with the memory symlink and standard config.
- **#255** (merged `5286b4a`): `pilot/` removed from dotfiles, the four docs now point at hal-pilot. On hal, a dotfiles pull left every hal-pilot tracked file unchanged (hash before = after).
- **`docs/reference/claude-code-config.md`** (`3dec426`, `d85d38e`, straight to master): `autoMode.environment` sets the classifier's trust boundary, and `autoMode.allow` clears resolving review threads. Read both paragraphs before touching classifier problems.
- **Live `~/.claude/settings.json`** (David ran both; `autoMode` is untracked by design, so there's nothing to capture). Backups are `settings.json.bak-20261027` and `bak-20261027b`.
  - `autoMode.environment`'s `**Source control**` line now covers the whole `villavicencio` GitHub account.
  - `autoMode.allow` = `["$defaults", <resolve review threads on a villavicencio PR the agent works on, after pushing the fix>]`.
- **Pilot batch 1:** 8 files in hal's `~/runs/queue/` (as `david`), modification times 14:04–14:11 in order:
  - `15-vil-516`, `16-vil-449`, `17-vil-451`
  - `18-vil-452` (item 3 only), `19-vil-521` (2 items only)
  - `20-vil-428`, `21-vil-345` (part a only), `22-vil-450`

  All are mergewren and all are labelled `hal-overnight`. The drafts are in this session's scratchpad (`queue-batch1/`); hal's copies are the source of truth.
- **Linear:**
  - VIL-515 is In Progress, with a progress comment; its step 7 moved to VIL-454 (comment there says what to copy from `timing.py`).
  - VIL-537 (onboard hal-pilot to MergeWren) is David's, in progress.
- **MergeWren session** ("VIL-317 and VIL-400 pilot merges", Remote Control) was told about mergewren#90's conflicts and about the 8 incoming pilot PRs. It took #90 with David's OK. Delivery is unconfirmed: that route reports nothing back.

## Decisions Made
- **hal-pilot code is written on the Mac (Orca); hal's clone only runs it.** A second, editable clone on hal would sit under the same account the worker runs as. David considered making the run copy unwritable by `david` and chose to change nothing for now.
- **Review gate for hal-pilot: MergeWren** (David; VIL-537). Until it lands, `CLAUDE.md` there still says "not decided yet". Update it when onboarding is done.
- **VIL-515 closes after tonight's 01:30 run starts from the new path.** Steps 6 and 7 don't hold it: step 6 is decided and tracked in VIL-537, and step 7 moved to VIL-454.
- **Batch 1 excluded on purpose:**
  - Anything in MergeWren's review logic (E13, baseline rules, read evidence, findings rules, VIL-336, VIL-406), because the pilot must not edit the reviewer that grades it.
  - VIL-423: its bug is tests writing the real lane lock, which on hal could stop MergeWren.
  - VIL-529 and VIL-531: the incident-lock area the MergeWren session is working in. VIL-531's replay tests also need the `hal` account's run files.
  - VIL-448: wait for mergewren#89, whose citation checker can verify the fix.
  - VIL-127: has an open design question for David (success results carry the failure class or not).
- **Pilot end state** (from P-VIL-11 and VIL-398): a two-week verdict, measured against VIL-398's bar (≥60% accepted unchanged or with small fixes, no high or critical finding merged, review cheaper than doing the ticket).
  - VIL-398 is still Backlog. The 22 real runs since 10-18 were mostly a shakedown: 3 passed, 7 opened `[failed]` PRs, 7 failed before opening a PR, 3 runner errors, 2 declines.
  - If the verdict is yes, the README's accepted risk needs fixing (own account or Seatbelt) and VIL-397 (queue intake from Linear) gets built.

## What Didn't Work
- **An allow rule for `gh repo create`:** `Bash(gh repo:*)` was already allowed and the classifier still blocked it, because allow rules don't move its trust boundary. The fix was the `autoMode.environment` line.
- **Resolving a review thread through the API** is an "External System Writes" soft block even on the agent's own PR. That rule's exception for working on a PR covers only posting comments and editing the title or body. The `autoMode.allow` entry fixed it. A command that bundles a blocked step gets the whole command denied, so split the risky step out.
- **`stat -f` over SSH on hal** resolved to GNU coreutils and failed, so a before/after snapshot hash was meaningless. Use `/usr/bin/stat`, or `find -mmin`/`-cmin`.

## What's Next
1. **Morning check of batch 1** (on hal, as `david`):
   - `~/runs/log/runner.log` for tonight's entries;
   - the new `~/runs/log/<run>/run.json` files;
   - `[pilot]` PRs in mergewren.

   If the 01:30 run started from `~/Projects/hal-pilot`, mark VIL-515 Done with a comment linking VIL-537 and VIL-454. Batch 1 runs at most 3 tickets a night, so it lasts through the night of Thu 10-29.
2. **hal-pilot `CLAUDE.md`:** replace the "Review gate: not decided yet" line once VIL-537 lands (MergeWren, plus how to wait for its comment). Edit `~/Projects/hal-pilot` on the Mac, then pull on hal.
3. **Batch 2:** VIL-448 after mergewren#89 merges, and VIL-127 if David decides its success-result question. Queue more before batch 1 runs dry, or the two-week clock stalls again.
4. **mergewren#89 (VIL-381 part A)** is waiting for David's approval, and the MergeWren session owns it. When it and #90 merge, VIL-391 can close, and VIL-381 part B unblocks.
5. **Carried from before:** this Mac still has both `tldr` and `tlrc` until the next `./install`. Old pilot branches #79 and #81 on mergewren's origin wait for David's OK to delete.
6. **Optional, David's call:** move the browse-gateway-only lines out of the user-scope `autoMode.environment`. `autoMode` isn't read from a repo's `.claude/settings*.json`, so they'd need another home or rewording as account-wide. The two tool-pattern entries in `autoMode.soft_deny` (`Bash(rm -rf private/*)`, `Bash(git push --force*)`) are read as prose; a hard block belongs in `permissions.deny`.

## Gotchas & Watch-outs
- **hal's `~/Projects/hal-pilot` is production:**
  - Never edit or branch there. Deploy is a pull.
  - A plist template change also needs `install.sh` plus David's `admin` reload: `ssh -t admin@hal '…'`, since `!` can't take a sudo password.
- **The pilot worker runs as `david` and can write `~/Projects/hal-pilot`** through any test it runs. This is known and accepted for now (see Decisions).
- **Auto-mode classifier:** check `claude auto-mode config` before adding allow rules. `autoMode` is user-scope only, and its entries are prose.
- **Queue file order is by modification time, not name.** Set mtimes when copying (`touch -t`) and move with `mv` so they're kept. Check each file with the runner's own `parse_ticket` before queueing.
- **A pilot ticket's "Environment on hal" block** is in every batch-1 file. Copy it into new mergewren tickets.
- **The MergeWren session gets messages over Remote Control with no delivery receipt.** It replied once this session, so it reads them, but don't assume it has.
