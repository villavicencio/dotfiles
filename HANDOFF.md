---
created_at: "2026-11-17T20:48:11-08:00"
branch: "master"
head: "0aa17d1"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "VIL-761 — brief an engineer to write the dv:manager-mode skill (skills repo), then the dotfiles PR"
---
# HANDOFF — 2026-11-17, evening (PT)

A short grooming session in Manager Mode, about 19:45–20:50 PT. No repo changes: the session groomed VIL-761 (Manager Mode), took three decisions from David, rewrote the ticket, and filed three more. The work before it (VIL-700 part 2 on hal) is unchanged and still waits for its next-day check.

## What We Built
- **VIL-761** (Backlog, moved to the Argus project): rewritten as "Manager Mode as a dv: skill: one text, one on/off switch". Decisions, to-do, done-means and agent notes are in the ticket; read it and its one comment (David's input from the eagle-hover-save session) before briefing.
- **VIL-796** (Backlog, Dotfiles, blocked by VIL-761): the rollout. Replaces the copies in obsidian-scriptorium, mergewren-web and dotfiles memory with pointers, and adds the vault notes.
- **VIL-797** (Backlog, Dotfiles): one ticket format for every project. Written in the proposed format as a sample. David said he has thoughts to add before it is worked; do not start it.
- **VIL-798** (Backlog, Argus): an Orca plugin that shows a session's mode, context fill and ticket id in the Orca chat UI. Starts with a spike; six open questions are listed in it.

## Decisions Made
All David, 2026-11-17, by multiple-choice dialog unless noted:
- **Home of the Manager Mode text:** a `dv:` skill in the skills repo holds it and is the on/off switch. A project that wants it standing adds one line to its `CLAUDE.md`/`AGENTS.md`. The earlier plan (`docs/agents/manager-mode.md` in dotfiles) is dropped.
- **Base text:** the copy in dotfiles memory (`feedback_manager_mode_sop.md`), with "The team" replaced by `~/Obsidian/eagle-hover-save/manager-mode-team-section-draft.md` (model and effort per hire).
- **Split:** VIL-761 is text, home and switch; VIL-796 is rollout.
- **VIL-761 moves to Argus** (said in chat).
- **Mode display is an Orca plugin** (said in chat), after David confirmed the CLI statusline does not show in the Orca chat UI.
- **Owner of the text:** the ticket says the dotfiles agent still maintains it, through skills PRs. That is the manager's reading of David's 2026-11-16 instruction now that the home moved; he has not confirmed it.

## What Didn't Work
- **Fetching the hal draft.** `/private/tmp/claude-503/…/scratchpad/manager-mode-prompt.md` is not on hal's disk (checked as `hal`; the scratchpad folder exists, 87 entries, none matching). David had it open in a tab and pasted it. By a read, not a mechanical diff, it matches the memory copy except for layout. The memory file and this session's transcript are now the only copies of that text.
- **Ticket format.** The manager wrote VIL-761 and VIL-796 without following `/ticket`'s template; that gap is what VIL-797 records.

## What's Next
1. **VIL-761.** Brief one engineer for the skill in the skills repo (`~/Projects/skills` is the assumed path; verify), then a second unit for the dotfiles PR (`docs/agents/code-review.md` review-round rules; one Subagents line in `claude/CLAUDE.md` and `codex/AGENTS.md`). Name a model and effort on each hire with a reason, per David's comment on the ticket. The skill's test: a fresh session that invokes it dispatches an engineer instead of editing.
2. **VIL-700, on 2026-11-18, outside 01:30–06:00 PT and 18:00 PT** (carried, not touched this session):
   - `ssh hal-as-hal '/opt/homebrew/bin/jq ".jobs[] | select(.id==\"637debb93470\") | {last_status, last_error, failure_streak, last_run_at}" ~/.hermes/cron/jobs.json'` → `last_status: "ok"`, `failure_streak: 0`. Also any Slack DM from the check overnight.
   - `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh verify'` → exit 0.
   - Then `retire-old-clone` (dry run first); it moves `hal`'s old clone aside, never deletes. Then mark VIL-700 Done.
   - hal's shared clone was on `c8cefce` at midday; `master` is 3 commits ahead (#276, #277, `0aa17d1`). Pull it as `david` (`ssh hal`). Whether those commits touch `helpers/hal_dotfiles_sync_check.sh` was not checked.
3. **VIL-798 spike**, when David picks it. Agree the mode state file's path and fields with VIL-761 before either ships; VIL-761 can ship first without it.
4. **Owed doc:** the MergeWren mailbox in `docs/agents/code-review.md` (through an engineer; the memory file `feedback_mergewren_owns_mergewren.md` has the text).
5. **VIL-736** (Todo, Low), after VIL-700.
6. **Carried, still unticketed:** the Garmin MCP connection timeouts (seen again this session); whether Hermes on hal is up; the MergeWren stopgap watcher after hal's reboot on 2026-11-11; the `compinit` fix for this Mac.

## Gotchas & Watch-outs
- **Manager Mode is standing here.** The manager session does not edit repo files; it briefs engineers. Linear, memory and handoffs stay with the manager.
- **Cost rule from David's comment on VIL-761:** never let a hired agent inherit the session's model. In the eagle-hover-save session, agents that inherited it cost about $239 of $281.
- **Four copies of the prompt exist** and they differ: dotfiles memory (full), obsidian-scriptorium `CLAUDE.md`/`AGENTS.md` and mergewren-web `CLAUDE.md` (both stop after "Running the team"), plus the eagle team-section draft. Only the first and last feed VIL-761.
- **mergewren-web belongs to the MergeWren session.** Its pointer change (VIL-796) goes through that session or with its agreement; mailbox `/Users/hal/agent-mail/mergewren/` over `ssh hal-as-hal`.
- **Codex and `dv:` skills:** unchecked whether Codex sessions can invoke the skill. VIL-761 tells the engineer to find out.
- **Orca plugin facts are read, not tested:** everything in VIL-798's agent notes comes from `orca skills get orca-plugin-authoring` on app 1.4.257.
- **A PR that names a `VIL-` id can auto-close it at merge.** VIL-761 will have two PRs (skills, dotfiles); re-check its state after the first merges. Same for VIL-700.
- **Pulling on hal:** pull `david`'s clone as `david`. Never run git in it as `hal`. A merge that changes `helpers/hal_dotfiles_sync_check.sh` needs `sync-check` re-run as `hal`.
- **Rollback if hal misbehaves:** `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh relink-rollback'`; full order in `docs/reference/install-and-server.md`, "One dotfiles clone on hal".
- **Another session's worktree:** `.claude/worktrees/vil-721-hal-memory-sections` (detached at `a9af0f3`); leave it.
- **Lead reports arrive HTML-escaped** (`&amp;`, `&lt;`). Never copy a command for David out of one.
