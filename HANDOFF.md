---
created_at: "2026-11-03T14:23:26-08:00"
branch: "master"
head: "b90df04"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "check the 2026-11-03 01:30 PST hal pilot run (VIL-546, VIL-544, VIL-550 briefs), still not looked at; reopen partial tickets after merges"
---
# HANDOFF — 2026-11-03, afternoon (PST)

This session picked up the morning handoff (`206975d`). It meant to check last night's hal pilot run, but David switched to Linear housekeeping instead. VIL-551 was re-scoped, and a `someday` label now parks ideas, with a weekly Atlas reminder. **The pilot run is still unchecked.**

## What We Built
- **VIL-551 re-scoped:** it now evaluates pdf_oxide (github.com/yfedoseev/pdf_oxide), not PaperPilot, for agent PDF reading and local RAG ingestion. The FedEx invoice angle is dropped. The ticket body holds the facts (fetched 12:40 PT) and the test plan: compare parsers, then a retrieval check (known-answer questions, hit rate in the top 5). It now has the `someday` and `Spike` labels and no priority, and stays in Backlog. The PaperPilot link stays on it for history.
- **Linear label `someday`** (VIL team, grey): a parked idea that agents don't suggest. The label's description in Linear carries the rule.
- **Rule in `claude/CLAUDE.md` and `codex/AGENTS.md`** (Linear section), commits `2da3472` and `b90df04`:
  - Never suggest `someday` issues unless David asks.
  - "Maybe someday" means: add the label and set no priority.

  `.claude/commands/ticket.md` points at the label. `david`'s clone on hal is pulled to `b90df04`.
- **Atlas on hal** (as `hal`, through `ssh hal-orca`):
  - Daily-plan cron job `bbd383a26726` (MergeWren daily plan): its READY definition now excludes `someday`, and the prompt has a "never pick or suggest" line.
  - New script-only job `572d2f167b79`, "Someday reminder (Linear, weekly)", runs Fridays at 16:00 PT. It runs `~/.hermes/scripts/someday_digest.py`, which uses `lin.py` from the same folder, and delivers to Slack. It's silent when the list is empty.
  - Run by hand, the script listed VIL-551. Its first real Slack post is Fri 2026-11-06. Not yet seen.
  - Backup: `~/.hermes/cron/jobs.json.bak-20261103-someday`.

## Decisions Made
- **The label is a label, not a workflow status.** It adds nothing to the VIL team's workflow, which other projects share, and Backlog stays as it is. `/ticket` already used Backlog to mean "someday or needs a decision". The label separates the parked ideas.
- **The reminder is script-only, with no model run**, so it costs nothing. David can move the Friday 16:00 PT slot.
- **Atlas's interactive memory wasn't edited.** Hermes manages `~/.hermes/memories/*.md`, and they use lock files. David may tell Atlas the rule himself.
- **FedEx invoice use case dropped from VIL-551** (David: it doesn't come up often enough to matter).

## What Didn't Work
- `jobs.json` is `{"jobs": [...], "updated_at": …}`, not a bare list, so iterate `d["jobs"]`.

## What's Next
1. **Check the 11-03 01:30 PST pilot run (carried over, still not done):** `ssh hal` (as `david`), `tail ~/runs/log/runner.log`, then the `run.json` files for vil-546, vil-544 and vil-550. Hand passing PRs to MergeWren with the evidence.
2. After any pilot merge, reopen its parent ticket (VIL-546, VIL-544 or VIL-550). Each brief covered only part of its ticket (VIL-543).
3. **Tonight before 22:00 PT, David picks the next briefs.** hal-pilot owns the reminder, if David pasted its prompt.
4. **David, in the MergeWren session:** mergewren#105 (VIL-448) and mergewren#103 (VIL-345), carried over.
5. **Friday after 16:00 PT:** confirm the someday reminder posted to Slack. If it didn't, run `hermes cron runs 572d2f167b79` as `hal`.
6. Backlog: VIL-552, VIL-553 and VIL-554 (hal-pilot); VIL-581 (remote QA, needs David at the Mac).

## Gotchas & Watch-outs
- **Atlas's daily plan covers only the MergeWren project.** Its `someday` skip matters for MergeWren ideas only. Dotfiles tickets never reach it anyway.
- **Atlas job prompts use `/home/node/...` paths** (for example the plan's `workdir` and its `lin.py` path), but the real files are in `/Users/hal/.hermes/scripts/`. The jobs run, so leave those paths alone unless one breaks.
- **Edit Hermes cron jobs with `hermes cron edit|create`** (as `hal`, `PATH="$HOME/.local/bin:$PATH"`), not by editing `jobs.json` by hand: the ticker holds a lock on it.
- **Carried over:**
  - Desktop Commander installer race: re-run the installer from a Mac terminal if it says "still loaded after launchctl bootout". See `docs/reference/tooling.md`.
  - Never run `npx … remote` by hand while the agent is loaded.
  - Nothing else may run on hal's local models from 01:30 to 05:00 PST.
  - MergeWren gates pilot merges on David's own per-PR approval, so don't relay approvals.
