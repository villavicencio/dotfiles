---
title: "herdr agent fleet (retired 2026-10-22): what it was, what was removed, and the lessons that outlive it"
date: 2026-10-22
category: integration-issues
module: herdr
problem_type: integration_issue
component: tooling
severity: Low
status: retired
root_cause: superseded
resolution_type: removal
tags: [herdr, orca, claude-code, hooks, retired]
---

# herdr agent fleet — retired

`herdr` was a tmux-shaped client/server multiplexer with native agent awareness. From
2026-08-18 it hosted the Mac's Claude Code agents, one workspace per project, each with a jump
key. It also tracked their state and resumed their conversations across server restarts. David
stopped using it around 2026-10-09 and paused it on 2026-10-10. Orca replaced it on 2026-10-21,
and VIL-422 uninstalled it on 2026-10-22. This file condenses the ~360-line "Herdr" section that
`CLAUDE.md` and `AGENTS.md` carried. It's here as history, so sessions no longer load it.

## What was removed (VIL-422)

| Piece | Where it was |
|---|---|
| Homebrew formula `herdr` (0.9.1), plus `terminal-notifier` (only for herdr's system toasts) | `brew/Brewfile` |
| Config, linked to `~/.config/herdr/config.toml` | `herdr/config.toml`, `dotbot-conf/base.yaml` |
| Fleet snapshot/verify/repair tool | `herdr/fleet-check.py` |
| Auto-reconnect ssh shim for remote panes (`claude-code`), and its installer | `herdr/shims/`, `helpers/install_herdr_agents.sh`, `dotbot-conf/darwin.yaml` |
| `SessionStart`/`UserPromptSubmit` hook that labelled a context-free pane "blank" | `claude/hooks/herdr-blank-state.sh`, its link in `darwin.yaml`, its registrations in `claude/settings.json`, the migration in `helpers/migrate_claude_settings.py` |
| herdr's own integration hooks (`herdr-agent-state.sh`) | live `~/.claude/settings.json` and `~/.codex/hooks.json`, removed with `herdr integration uninstall` |
| Runtime state (logs, `session.json`, `fleet-snapshot.json`) | moved from `~/.config/herdr/` to `~/Projects/_archive/herdr-config/` |
| Two unmerged branches, `chore/herdr-retire-axiom` (#183) and `chore/herdr-retire-atlas-tools` (#184) | deleted; the full uninstall superseded them |

To bring it back: revert the VIL-422 PR, `brew install herdr`, `./install`, and
`herdr integration install claude` / `codex` (a human step: it writes the agent's own config).

## Lessons that still apply

- **An app that rewrites its config in place can be symlinked; one that writes a temp file and
  renames it can't.** herdr kept the inode (`herdr config reset-keys`, 0.8.0), so a Dotbot link
  was safe and live edits showed up as `M herdr/config.toml`. Claude Code's `settings.json` is the
  opposite case. See `otty-config-symlink-hostile-atomic-rename-2026-08-07.md`.
- **launchd-spawned processes have a bare environment.** herdr's key bindings and integration
  probes failed silently on command-not-found. See
  `launchd-service-bare-environment-silent-failures.md`.
- **Check the instrument before trusting a negative.** `ps eww` can't read another process's
  environment on modern macOS, which once faked a "variable absent" result. See
  `../best-practices/verify-the-instrument-before-trusting-a-negative.md`.
- **Claude Code hooks:** `SessionStart` and `UserPromptSubmit` inject the hook's stdout into the
  model's context, so a display-only hook has to stay silent on stdout. Subagent events carry
  `agent_id`, so ignore them or they fire spuriously. `SessionStart` reports how the session
  began (`startup`, `clear`, `resume`, `compact`).
- **`claude --continue` resumes the most recent session for that cwd**, not a particular pane's
  thread. In a directory that two surfaces share (orrery: Forge's ACP sessions and a terminal),
  it can resume the other surface's conversation. `claude --continue || claude` needs the
  fallback, because `--continue` exits 1 in a directory with no prior session.
- **A pane that never closes itself:** `claude --continue || claude; exec /bin/zsh -il` in a login
  shell (`zsh -l -c`). When the agent exits, the pane drops to a shell instead of disappearing.
  The login shell rebuilds PATH from `zshenv` for processes spawned with launchd's environment.
- **A hook symlinked into the repo breaks on a branch switch.** That's where
  `herdr-blank-state.sh` taught it; the rule is in `CLAUDE.md`.

## herdr-specific gotchas (only if herdr comes back)

- **Restore boot race:** a pane whose `command` failed at restore (ssh before the network was up)
  came back as a plain shell, with the command dropped from the layout (herdrdev/herdr#2966).
  Upstream closed #3306 as `NOT_PLANNED`, so post-restart panes coming back as fresh shells is
  documented behaviour. That's why the template above resumes the agent itself.
- **Socket API (NDJSON on `~/.config/herdr/herdr.sock`; `herdr api schema` lists it):**
  - `layout.apply` takes `tab_id` or `workspace_id`, never both.
  - Every request needs a `params` key, even `{}`.
  - `layout.export` ignores `workspace_id` and returns the focused workspace, so address it by
    `tab_id`.
  - `layout.apply` mints a new tab id.
  - `layout.apply` kills the pane's live agent.
- **Diagnosing a pane that read `unknown`:** look at its foreground process (`pane.process_info`)
  first.

  | `layout.export` shows | Cause | Repair |
  |---|---|---|
  | No `command` | #2966 dropped it | `layout.apply` |
  | `command` present, fallback `zsh` | clean ssh detach | `herdr pane run <id> 'exec <cmd>'` |
  | `command` present, foreground `ssh` | someone re-attached by hand | exit back to the local shell, then as above |

- **Agent names don't survive the process.** `herdr agent rename` bindings are released when the
  agent process dies, even when the pane id is reused. Re-apply them after any repair.
- **Detection:** herdr matched ssh panes by the ssh child's process name, so each remote agent
  needed a shim with a manifest alias as its name. Local claude/hermes panes were detected
  natively. The `HERDR_AGENT` env hint didn't apply to ssh foregrounds (herdrdev/herdr#2961).
- **Nested tmux:** the remote tmux needed `set-titles on` and
  `set-titles-string "#{pane_title}"` (in a per-socket `-f` conf) for herdr to read the agent's
  state through it.
- **`herdr agent wait --until done` never fires on a focused pane.** Wait on `idle` or `blocked`.
- **Display-only metadata** (`herdr pane report-metadata`: `--state-label`, `--token`, `--ttl-ms`)
  overlaid a pane's sidebar row without touching agent identity.

## The roster at retirement

Local panes, by then all on the template above: `melos ♪`, `sites ✦`, `borealis ❆`, `argus ◉`,
`obscura ✇`, `eidos ❖` and `orrery ☉` (Forge-resident, with its pane cwd the physical
`~/.forge-projects/<codename>` path). `skills ⚒` left on #235. Remote panes over the ssh shim:
`axiom ∴` (retired 2026-09-02, when Axiom moved to Hermes) and `atlas-tools ⚙` (VPS-era). Atlas
and Vice moved to Hermes Desktop on 2026-09-01.

Phone access (Moshi over SSH/mosh to the Mac) used to end by typing `herdr` to attach the
fleet. That last step no longer exists.
