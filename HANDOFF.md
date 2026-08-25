---
created_at: "2026-08-25T12:00:13-07:00"
branch: "master"
head: "8d0e5a1"
---
# HANDOFF — 2026-08-25, midday (PDT)

Same-day continuation of the morning session (previous handoff at `289225d`). The morning's
resume focus was already done on pickup — both CodeRabbit changelists (skills `6837f5d`/#37,
borealis `45a91c4`/#13) had landed, closing that arc entirely. The session's real work was new:
the strategy brief for **Vice Gage**, a second Hermes agent running natively on this Mac, plus
the herdr fleet entry for it and the fallout fixes from the build. Model switched to Fable 5
mid-session; the build itself is executing in `argus ◉`, not here.

## What We Built

- **The Vice Gage strategy brief** —
  `~/Projects/agents/docs/plans/2026-08-25-001-feat-vice-gage-local-hermes-plan.md`
  (agents repo, commit `65b7c4d`). Written for an Opus executor in argus; 7 phases, 3 ▶ human
  stops, 5-prompt blind gate. What the doc doesn't say: every command in it was verified live
  this session (VPS reads of Atlas's runtime, Mac reads, upstream docs fetched), and the
  detail level is deliberate — the executor should never need the VPS. Full persona charter and
  scope decisions live there, not here (this repo is public; the agents repo is private).
- **dotfiles PR #175 (merged, squash `5824601`)** — the `vice ♠` fleet entry: jump key
  `prefix+shift+v` in `herdr/config.toml`, roster rows in CLAUDE.md/AGENTS.md. The workspace
  itself was created live over the socket (wG, pane template with `hermes chat`, agent renamed
  `vice`); the PR tracks config+docs so a rebuild reproduces it. CodeRabbit: 2 findings, 1
  partially applied (the vice rebuild one-liner now in CLAUDE.md), `$BREW_PREFIX` declined on
  both threads — see the PR body for the triage record.
- **`8d0e5a1` (docs, straight to master)** — three durable Herdr-section updates from the argus
  session's handoff, each independently verified here before writing: the ⚠ Hermes-installer-
  clobbers-`~/.local/bin/hermes-agent` warning (latent break of Atlas's shim; re-run
  `helpers/install_herdr_agents.sh` after any Hermes (re)install), the "argv[0] trick is for ssh
  panes only" correction, and the `layout.export`-ignores-`workspace_id` gotcha (reproduced
  live: returns the *focused* workspace with believable data — address by `tab_id`).
- **Live fleet state**: workspace `vice ♠` up and detected natively as `hermes` (venv python,
  no shim needed — the brief's detection-risk fallback was never used), key binding
  hot-reloaded (`herdr server reload-config` → applied).

## Decisions Made

- **Vice is pinned to Atlas's Hermes tag (v0.20.0), not `main`** — one upgrade SOP covers both.
  David can reverse at Phase 1; the argus session installed matching v0.20.0.
- **No OpenRouter fallback for Vice** — Atlas's is dead anyway (402); the block is in the brief
  commented out.
- **Public-repo discretion**: dotfiles is PUBLIC, so the roster row and this handoff describe
  Vice as "personal media curation (Obscura + Eagle MCPs)" and point at the private agents-repo
  brief for the rest. Keep that split when touching either file.
- **Declined CodeRabbit's `$BREW_PREFIX` finding on #175, on the record** — `[[keys.command]]`
  runs in herdr's bare launchd env where `BREW_PREFIX` doesn't exist; absolute paths are this
  repo's documented rule for exactly that context (herdr#2960). Thread replies + PR body carry
  the reasoning; don't relitigate.
- **No re-review requested for #175's second commit** — docs-only delta on a COMMENTED (not
  CHANGES_REQUESTED) verdict, declines recorded. Deliberate, per the Code Review SOP.

## What Didn't Work

- **A classifier-blocked SSH read**: pulling Atlas's `mcp_servers` block with sed-masking of
  auth values was denied. Worked around by deriving the shape from upstream docs + the agents
  repo SOPs instead; the brief flags the two spots (auth syntax, fallback key shape) for the
  executor to verify on the box rather than trusting either source.
- **`workspace.create` spawns a default pane** before `layout.apply` adds the templated one —
  left a stray plain-shell tab (wG:t1) that had to be `tab.close`d. If you script workspace
  creation again, expect the extra tab.

## What's Next

1. **The Vice build continues in `argus ◉`**, not here — remaining phases: SOUL authoring
   (▶ David reads it), MCP registration (▶ `obscura keys new vice` — restarts the gateway,
   pick a quiet moment for Atlas), blind gate. Nothing for this session to do unless another
   handoff arrives.
2. **Two dotfiles follow-ups spotted but not started** (config changes → branch/PR):
   add `obscura` to the NVM lazy-loader shims in `zsh/zshrc` (invisible in fresh shells until
   `node` runs), and decide whether `uv` + a Python 3.11 join the Brewfile (both currently
   installed out-of-band and untracked; the Hermes runtime now depends on uv).
3. **VIL-82 unchanged** — still Backlog, blocked upstream; recheck rides the next Claude Code
   version bump. (Note: its Linear *state* is Backlog; "blocked" lives only in the title.)

## Gotchas & Watch-outs

- **⚠ Hermes's installer clobbers `~/.local/bin/hermes-agent`** — Atlas's auto-reconnect shim,
  and the break is *latent* (a running pane looks healthy until its next restart). Already
  fixed today by re-running `helpers/install_herdr_agents.sh`; the standing rule + detection
  check are now in CLAUDE.md's Herdr section. Recurs on every Hermes (re)install.
- **`layout.export` silently ignores `workspace_id`** and returns the focused workspace —
  believable data for the wrong target. `tab_id` only. Now documented next to the other two
  (fail-fast) API gotchas.
- **CodeRabbit's check on #175 read "Review completed"** — that's the string that means a
  review actually ran; `pending` / `Review rate limited` / `Review skipped` all pass without
  one. The check-description, not the pass state, is the signal.
- The `vice ♠` pane survives herdr restarts only as a shell (resume-on-restore is
  claude/codex-only); relaunch is typing `hermes chat`. Rebuild-after-#2966 recipe is in the
  roster now.
- Fleet roster and pane template: CLAUDE.md Herdr section, freshly corrected — trust it over
  older session notes.
