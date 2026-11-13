---
created_at: "2026-11-12T16:48:34-08:00"
branch: "master"
head: "4445447"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-12, late afternoon (PT)

This session picked up the 2026-11-10 handoff on the evening of 11-11, found most of its mergewren list already done by the MergeWren session, and then went somewhere else: David pasted an old prompt for a new Obsidian theming project, and the session built it. A side request checked what Seaglass holds before David cancels it. The carried items from 11-10 (Garmin, Hermes on hal, the stopgap watcher) were not touched.

## What We Built
- **`villavicencio/obsidian-scriptorium`** (private, `main`, cloned at `~/Projects/obsidian-scriptorium` on the personal Mac). The agent is called Scribe. Its `CLAUDE.md` holds the rules; `standard/.obsidian/` is the old dotfiles template, compared file by file and identical. `overrides/`, `templates/` and `bin/` are empty: no apply, diff or snapshot script exists yet.
- **PR #266** (`4445447`): `obsidian/vault-template/` left this repo. `helpers/install_hal_memory_pull.sh` now stamps new mirror vaults from the Scriptorium clone (`SCRIPTORIUM_DIR` overrides the path) and fails with a clear message only when a vault needs stamping and the clone is missing. `docs/agents/obsidian-vaults.md` points at the new owner. The apply and seed procedures moved to Scriptorium's `CLAUDE.md`.
- **Orca project** `obsidian-scriptorium` registered (`orca repo add`); its name and icon are set in the app, by David.
- **Vault** `~/Obsidian/scriptorium/` with the standard config, and the Claude Code memory link for the project slug `-Users-dvillavicencio-Projects-obsidian-scriptorium`.
- **Linear:** project Scriptorium (P-VIL-14, scroll icon) and VIL-703, the MergeWren onboarding ticket, modeled on VIL-537. VIL-703 is in Backlog.
- **Seaglass export** at `~/Documents/seaglass-export-2026-11-11/` on the personal Mac: the household money plan snapshot and the three other memories, verbatim. Seaglass held 3 pages, 1 document and 11 memories in total.

## Decisions Made
- **Name:** `obsidian-scriptorium`, agent Scribe (David's pick, option 6 of 10).
- **The template moved out of public dotfiles** into the private repo (David). The old copies stay in this repo's public git history; no token was found in them. The `.gitleaks.toml` allowlist entry stays so a history scan still passes.
- **The `syd` vault is out of Scribe's scope** (David). It has its own git repo and config.
- **Scriptorium stays on the personal Mac** (David, 11-12). He asked to move it to hal as `david`; hal has no `~/Obsidian` and cannot SSH to the Mac, so Scribe there could edit the repo but not read or change a vault. Offered: edit on hal and apply on the Mac, or give hal SSH into the Mac. He chose no move.
- **Seaglass is being cut** (David: not worth paying for). Everything in it also exists elsewhere: the export, the MergeWren session's own memory file on hal (account `hal`, `fix-rounds-regression-based.md` in the review-stack project memory), and the Scriptorium repo. This session stopped writing to it after one memory.
- **`orca.yaml` for Scriptorium was skipped.** The repo has no dependencies and no gitignored local files, so there is nothing for a setup script to do yet. Scribe's first session can add it with `dv:orca-setup`.
- **David will ask the MergeWren session to work on VIL-703 himself.** This session did not send it.

## What Didn't Work
- **The search for an earlier "Obsidian agent" conversation found nothing** in this project's memory, handoffs, Linear, Seaglass or 45 days of Claude Code transcripts on the Mac. The origin turned out to be a side-question answer David had kept on his clipboard. Side questions are not in the transcripts.
- **The first macos-server CI run on #266 failed** in `helpers/install_tmux.sh`: the TPM clone got "could not read Username for https://github.com" on the runner. A re-run of the failed job passed. Not caused by the change.

## What's Next
1. **VIL-703: MergeWren onboards obsidian-scriptorium.** David is asking the MergeWren session. No Scriptorium PR opens before it lands; until then only docs go straight to `main` there.
2. **Seaglass cutover, David's steps:** check the export; remove the Seaglass Memory connector in claude.ai Settings → Connectors (it is a claude.ai connector, so that covers the Mac and hal); cancel the plan at the Seaglass site. Not confirmed done. Until the connector is removed, every session is still told to call it and write to it.
3. **Scribe's first session** (in `~/Projects/obsidian-scriptorium`): write the snapshot, diff and apply scripts in `bin/`; read the `.stignore` of `hermes` and `axiom` to learn whether `.obsidian/` syncs; decide on `orca.yaml`.
4. **`~/Obsidian/hal-bench` does not exist** although the hourly hal pull lists it. `bash helpers/install_hal_memory_pull.sh` from the main checkout (personal Mac) creates it, now from the Scriptorium clone. Check `~/Library/Logs/hal-memory-pull.log` for how long it has been failing.
5. **Carried from 11-10, untouched:** re-measure the Garmin 502s (was due 11-11); Hermes on hal looked down; unload the stopgap watcher before `hal` next logs in at the Mac mini's desktop (`ssh hal-orca 'launchctl bootout user/503/com.mergewren.watch; launchctl bootout user/503/com.mergewren.console'`); the `compinit` fix command for this Mac; the optional Mac items.
6. **Unverified mergewren leftovers:** PRs 116, 122, 123 and 124 and VIL-679 were not in the last 25 rows of the dispatch log on 11-11; nobody read further back. VIL-411 is reopened to Todo and VIL-601 waits on David's activation decision.

## Gotchas & Watch-outs
- **The helper in this public repo depends on a private clone's path.** Moving or renaming `standard/.obsidian/` in Scriptorium breaks `install_hal_memory_pull.sh` for any vault that still needs stamping. Scriptorium's `CLAUDE.md` says so; change both together.
- **`docs/agents/obsidian-vaults.md` says the synced vaults sync "to the VPS".** `hermes`, `axiom` and `syd` carry Syncthing markers, but where the far end is now was not checked. Don't rely on that line.
- **A `/login` drops the local `linear` MCP.** The claude.ai Linear connector (`mcp__claude_ai_Linear__*`) still works in the meantime; `/mcp` signs the local one back in.
- **PR #265 (auto-compact at 600k) merged from another session** during this one. The memory note that says "hand off at 200k, auto-compact at 400k" is now out of date on the second number.
- **The MergeWren watcher works:** it reviewed #265 and #266 within about two minutes of each push. It is still the stopgap in the `user/503` launchd domain, which a reboot of hal removes.
- **Carried over:** nothing else may use hal's local models from 01:30 to 05:00 PT; never run `npx … remote` by hand while the Desktop Commander agent is loaded; a mergewren merge closes its VIL ticket within seconds, so re-check a multi-part one.
