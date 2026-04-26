# HANDOFF — 2026-04-26 (Sunday afternoon PDT)

Multi-day session that started Friday 2026-04-24 morning. Four PRs merged, three issues closed, board is clean: zero open PRs, zero open issues, zero pending Forge tickets.

## What We Built

### 1. PR #48 — Forge write-access for dotfiles project artifacts (closes gh#47)

`claude/commands/handoff.md:105` and `:145` patched with trailing `chown 1000:1000 "$DEST"` after ssh-as-root `cat >>` writes to `workspace-forge/projects/…`. Fixes the silent first-write ownership trap: `ssh root@host '>> path'` creates absent files as root; subsequent appends preserve that ownership; Forge (node, uid 1000) inside the container then can't update them. `cadence-log.md` for dotfiles was the symptom — fix extended to Step 5 (`_shared/*.md` writes) defensively. One-time VPS chown applied to the existing root-owned `cadence-log.md` and the `pending/done/` dir created via ssh during ticket archiving.

### 2. PR #49 — `~/.local/bin` symlink refresh in `helpers/install_node.sh`

After `nvm install` completes, idempotent `ln -sf` refreshes `~/.local/bin/{node,npm,npx}` to the managed `$NODE_VERSION` binaries. Fixes the manual hand-symlink state set up yesterday after the Intel-Node-12-breaks-CC-hooks incident. Bumping `NODE_VERSION` now auto-refreshes on next `./install`. Review caught a P1 — added `set -eo pipefail` so failed `nvm install` / `npm install -g` aborts before the symlinks are touched (commit `042c0fd`); also relocated the dry-run guard so `./install --dry-run` on a fresh machine without NVM yet doesn't error before printing the preview.

### 3. PR #51 — Sibling chown patches for archive/comms paths (closes gh#50)

Three more ssh-as-root sites patched with the trailing-chown invariant from #48: `pickup.md:88` (Forge inbox archival), `pickup.md:97-99` (pending-ticket archival), `handoff.md:119` (Step 5.5 Forge-bridge sync log). Review caught a P2 — the `;`-vs-`&&` chaining defect was masking mv/cat failures because ssh returned chown's exit instead. Fixed in commit `eaef5f6` by switching `find -exec mv {} \;` → `find -exec mv -t DEST {} +` (the `\;` form discards the exec'd command's exit code; `+` propagates it) and flipping the comms-log `;` → `&&`. One-time VPS repair on `wedding-site/pending/done/` (was the only Forge project with the `root:root` drift).

### 4. PR #53 — Sibling exit-propagation fixes on master (closes gh#52)

The same `;`-vs-`&&` defect existed at `handoff.md:108` (Step 5.3 `_shared/*.md` write-back) and `:151` (Step 6.2 cadence-log append) — they landed on master via #48 and were outside #51's diff at review time. Both flipped to `&&` so append failures propagate through ssh's exit code. Step 5.3 fix actually wires up the `.forge-pending` fallback to fire on append failure; Step 6.2 fix lets the "note the failure and continue" path actually trigger. Also corrected a misleading "fallback below" comment from #51 (audit log path has no automated fallback). Review found one directional doc nit (line 110 said "above" instead of "below"), fixed in `197cae5`.

### 5. Cross-project Forge learning pushed

`_shared/patterns.md` got: "ssh-as-root + `>>` redirect on a container-shared volume creates absent files as root, locking container-scoped uids out of subsequent writes. Defensive mitigation: trailing `chown` after ssh-as-root writes. Source: dotfiles#47."

### 6. Housekeeping

- Pending Forge ticket `ticket-20260423-224300-fix-oh-my-zsh-update-starship-timeout-warning.md` archived without a GH issue (root cause was 2019 Intel Node 12, fixed earlier).
- Pending Forge ticket `ticket-20260423-015700-fix-forge-write-access-for-project-artifacts.md` promoted to gh#47, archived.
- Cadence log appended via the patched Step 6 (live acceptance test for #48).

## Decisions Made

- **Extended each chown fix to all sibling sites in scope** even when the ticket only cited one. Same bug class, zero blast radius on already-correct files, future-proof.
- **Archived the Starship pending ticket without creating a GH issue** since its root cause was already fixed yesterday — creating an issue just to close it adds noise.
- **Switched from `find -exec mv {} \;` to `-t DEST {} +`** after empirically verifying the exec exit-code propagation difference (semicolon form discards mv's exit; plus form propagates). Comments inline at pickup.md:88.
- **Filed gh#52 as a follow-up rather than expanding #51's scope** to keep PR review surface narrow. Same review-cycle hygiene applied: gh#50 follow-up to #48, gh#52 follow-up to #51.
- **Did NOT patch /pickup Step 2c's archive move with docker-exec-as-node rewrite** — the defensive trailing chown is correct, minimal, and consistent with the other sites.

## What Didn't Work

- `gh issue create --label "workflow-hygiene,forge,permissions"` failed twice — repo lacks all three labels. Used `enhancement,cleanup,cross-machine` instead. If we open more Forge-adjacent issues, adding a `forge` label would help triage.
- Tried to harness-test stubbed `nvm install` failure via PATH-injected fake binary — NVM is a sourced function, can't be shadowed that way. Fell back to verifying `set -eo pipefail` semantics via `bash -c 'set -eo pipefail; false; echo X'` and trusting the pattern. Reviewer independently replayed the failure scenarios on PR #49 round 2.
- First pass at PR #51's archive command used `find -exec mv {} \;` — looked correct but actually swallows mv's exit. Caught by reviewer P2; fixed by switching to `+` form.

## What's Next

No in-flight work. Candidate next items, in rough priority order:

1. **Drop the `brew shellenv | grep -vE '^eval .*path_helper'` filter in `zsh/zshrc:30`** — modern `brew shellenv` no longer emits the path_helper eval line, so the filter is a no-op. Pure simplification, one-line delete. Carried from earlier session.
2. **Compound a solution doc for the ssh-as-root chown + exit-propagation learning.** `_shared/patterns.md` has the one-liner; a `docs/solutions/…` entry would capture symptom → diagnosis → fix → invariant for future `/pickup` surfaceability. Two related defects (ownership trap + chaining-mask) make a clean joint write-up.
3. **Wait for an inbound signal** — close the session, let fresh work arrive.

## Gotchas & Watch-outs

- **Multi-day session straddling 2026-04-24 → 2026-04-26.** Some squash-merge commits roll up earlier-session diffs because branches forked off a local master that had 2 unpushed commits at the time (`d684234` and `e8c7a31` each contain settings.json + prior HANDOFF diffs in addition to their titled work). Not harmful; surfaces if anyone does `git log --follow <file>` archaeology.
- **Cached /handoff skill content is stale during a long session.** Both /handoff invocations this session showed the pre-edit version of Step 5/6 examples even after the on-disk file was patched. The file IS what executes; Claude Code just doesn't re-read skill content after session start. Inline-executed the patched commands explicitly. Next /handoff in a fresh session will pick up the merged version.
- **`~/.local/bin/{node,npm,npx}` are now auto-maintained by `./install`.** Bumping `NODE_VERSION` in `zsh/zshenv` + re-running `./install` refreshes the symlinks. No manual `ln -sf` step.
- **`find -exec ... \;` discards the exec'd command's exit code.** Use `+` form when you need failure propagation. This is a class of latent bug worth grepping for elsewhere if it shows up.
- **All ssh-as-root writes to `workspace-forge/projects/` and `shared/` now trailing-chown** — invariant established across `/pickup` and `/handoff` SOPs. Any future SSH write to these volumes should follow the same pattern.
- **Carry-forward (still valid):** `##`-escape rule for hex colors in tmux `#{?...}` ternaries; `tmux display-message -p` is the canonical format-string diagnostic; statusline edits can blank pre-existing Claude sessions — always test from fresh `claude` invocation, not `--continue`; straight-to-master pushes do NOT auto-trigger `sync-vps.yml` (use `gh workflow run sync-vps.yml -f host=openclaw-prod -f dry_run=false`); HANDOFF.md stays on master only — never commit mid-branch.
