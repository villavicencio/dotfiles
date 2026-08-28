---
created_at: "2026-08-27T21:14:54-07:00"
branch: "master"
head: "bd10ba8"
---
# HANDOFF — 2026-08-27, evening (PDT)

A same-day continuation of the afternoon fleet-ops session. It opened by clearing the afternoon
handoff's leftovers, then turned into a planning session: David asked for an interview-driven plan
to move Atlas (Hermes on the VPS) from Telegram to Slack, and chose to have Argus execute it. The
tail was fleet repair — `atlas-tools ⚙` had been re-attached by hand outside the shim and tmux —
plus a permissions gotcha relayed from borealis. Three docs commits to master, one docs commit to
the agents repo, zero PRs, tree clean.

## What We Built

- **`~/Projects/agents/docs/plans/2026-08-27-001-feat-atlas-telegram-to-slack-migration-plan.md`**
  (agents `68722ed`) — the Argus brief. Interview decisions are in its table; the part that is not
  obvious from reading it: every VPS-side fact was verified live against prod (v0.20.0) *and* the
  Mac's reference checkout (v0.20.6), and the two differ in line numbers only. The embedded
  cutover script passes `bash -n`; it has **not** been run anywhere.
- **`9b87438`** — the afternoon's leftovers: cua-driver-rs `zshrc` lines reverted, lazy-lock bumps,
  handoff landed with #3306's real status.
- **`ef438b5`** — `CLAUDE.md` pane-recovery table gains a third case (hand-attached ssh outside the
  shim/tmux). The tell is `pane.process_info` showing a bare `ssh`; `layout.export` and the screen
  both look healthy.
- **`bd10ba8`** — `CLAUDE.md` permissions section: `Write(path)` rules are inert; only `Edit(path)`
  is matched, and it covers all file-editing tools.

## Decisions Made

- **Argus runs the Slack migration, not this session.** David's call after the plan was drafted
  here; this session's deliverable shrank to the brief + commit. Argus had already started by the
  time of this handoff (agents repo shows a fresh `docs: update handoff` at `2e98be3`).
- **Migration shape** (all David's answers, recorded in the brief's table): existing personal
  workspace; DM-only — Finance/Agents groups and the pinned dashboard do not carry over; the
  orphaned `finance_ops.py` suite is retired, not ported; hard cut in one gateway restart; Slack
  first on 0.20.0 *after* today's `hermes-upgrade-v0.20.6` pytest sweep finishes, then the upgrade
  SOP as its own window; `syncthing-daily-check.sh`'s alert moves to Slack; the Mac `telegram-mcp`
  is used once for the history export and then removed; export → remove creds → BotFather revoke;
  one idempotent script that David runs.
- **`SLACK_HOME_CHANNEL=U<member id>`** is the DM target — both delivery lanes resolve `U`/`W` ids
  through `conversations.open`. `SLACK_ALLOWED_USERS` fails closed. `reactions:write` must be added
  to the generated manifest by hand. `--no-assistant`, never `--agent-view` (irreversible).
- **`hermes gateway install --force` is not needed** — the loaded unit already reads
  `TimeoutStopUSec=3min 30s`, `NeedDaemonReload=no`; the 8/21 warning is stale and clears on
  restart. The plan's "opportunistic fixes" reduce to the timezone.
- **`atlas-tools ⚙` was repaired in place, not rebuilt**: `/exit` → `exit` ×2 → `exec` the shim →
  `claude --continue` → rename. Same session resumed (`ab7cc371…`, ctx unchanged).
- **Borealis's `Write(…)` deny was deleted rather than converted** — the `Edit(…)` twin was already
  present on the line above, so the rule set was already correct and the `Write` entry was pure
  noise. Backup left beside the file.
- **Ruled out:** rebuilding `w1:t7` (this pane) — still deliberately degraded; `snapshot` carries
  its command and `repair` fixes it at the next restart.

## What Didn't Work

- **The handoff claimed herdrdev/herdr#3306 was open with no response.** It had been closed
  `NOT_PLANNED` by `akbash-bot` 17 minutes after filing — the same bot that closed #2966. Their
  position: post-restart panes returning as fresh shells is documented behaviour; a change is an
  Ideas discussion. Corrected in the handoff at `9b87438`.
- **`telegram-mcp` is registered under the stale project key `~/Projects/openclaw`** in
  `~/.claude.json`, so it is not loaded in `~/Projects/agents` at all. The brief routes the export
  through a one-off `uv run` script instead of the MCP for this reason.
- **`fleet-check verify` briefly read `sites ✦ w9:pM` as undetected** — it was a live Claude Code
  on PR #163 with three subagents running. Transient; not a repair target.

## What's Next

1. **Nothing is pending in dotfiles.** Tree clean, master pushed, no PRs.
2. **The Slack migration is Argus's** — check `~/Projects/agents/HANDOFF.md` and the brief's
   Execution log, not this file, for where it stands. Two things worth watching from here: the
   0.20.6 pytest sweep must finish before Phase 3's cutover script runs, and the migration must
   finish before today's upgrade window or the SOP's Phase-4 round-trip has no surface.
3. **David's choice, still open from the afternoon:** adopt `claude --continue || claude` as the
   fleet pane-template default now that upstream has declared command loss intended (#3306).
4. **`davidv.sh` email setup** (`/ops/email`) — human job, not started.

## Gotchas & Watch-outs

- **A pane can show a full, healthy Claude Code TUI and still read `unknown`.** If someone typed
  `ssh -t root@…` from the fallback shell and launched claude by hand, the local process is `ssh`
  (not the `claude-code` alias) and the remote claude has no tmux — it dies with the next
  disconnect. `pane.process_info` is the only tell. Repair recipe: `CLAUDE.md` pane-recovery
  table, third row.
- **Renames still release when the agent process dies** — obscura and vice had lost theirs again
  and were re-bound this session. `fleet-check verify` catches it; run it after any pane surgery.
- **`Write(path)` in a permissions list does nothing.** Claude Code warns at startup; the fix is
  an `Edit(path)` rule, which covers Write too. No other project or user-scope file carried one.
- **`browse-gateway` MCP failed to connect at this session's start** — the tunnel may have been
  healthy the whole time (the client never retries). Check `lsof -nP -iTCP:8080 -sTCP:LISTEN`
  before touching launchd; a new session is the fix.
- **A `--continue` in a remote project dir picks the most recent transcript there** — for
  atlas-tools that was `ab7cc371…` (20:44), not the older 3 MB `c8f68b83…`; verify mtimes before
  relying on it after any hand-launched session.
