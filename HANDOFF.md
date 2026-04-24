# HANDOFF — 2026-04-24 (late evening PDT)

Same-day continuation of 2026-04-23. No commits landed this session — both fixes addressed runtime/system state rather than repo contents.

## What We Built

### 1. tmux window glyphs restored after server restart

**Symptom:** After continuum restored windows, all 5 tabs (Home, FedEx, Eagle, Dotfiles, Wedding) rendered with no glyph and no palette color — `@win_glyph` and `@win_glyph_color` were unset across the board.

**Root cause:** `~/.config/tmux/window-meta.json` keys entries by session name. All 6 entries sat under top-level key `"main"`, but the current session is named `local` — the rename shipped 2026-04-22 in commit `d5cd1b3` as part of the LOCAL/VPS session-pill work. `tmux/scripts/restore-window-meta.sh:18` does `jq '.[$session][$window]'` with `$session=local`, so it found nothing and set no options. `save-window-meta.sh` is only invoked by the tmux-window-namer skill (not on the client-attached hook) — so no fresh writes happened under `local` between the rename and today.

**Fix:** Renamed the top-level JSON key `main` → `local` using jq, re-ran `restore-window-meta.sh`. All 5 windows now have glyphs + colors set. No code changes; the restore logic was correct — the data key was stale.

### 2. `SessionStart:resume hook error` (3 errors on every resume)

**Symptom:** Screenshot showed three identical hook errors on every `claude --continue`:
```
└ SessionStart:resume hook error
└ Failed with non-blocking status code: internal/modules/cjs/loader.js:1007
```

**Root cause (three-way collision):**
1. **Stale Intel Homebrew Node 12.13.0 (Oct 2019, x86_64) at `/usr/local/bin/node`** — leftover from pre-Apple-Silicon migration. `/usr/local/Cellar` does not exist (Intel brew is orphaned), but `/usr/local/bin/node` + symlinked npm/npx survived. `loader.js:1007` is Node 12's CJS loader error line — modern `.mjs` ESM crashes it.
2. **PATH ordering puts `/usr/local/bin` ahead of `/opt/homebrew/bin` in non-zsh contexts** — `/etc/zprofile` runs `path_helper -s` which prepends `/etc/paths` contents (first entry: `/usr/local/bin`). In non-zsh subshells (POSIX sh, bash) spawned by Claude for hook execution, zshrc never runs, so NVM's node is never added to PATH. Bare `node` resolves to the 2019 Intel binary.
3. **Vercel plugin v0.40.0 `hooks/hooks.json` registers 3 `SessionStart` hooks** matching `startup|resume|clear|compact`, each invoking bare `node` on an `.mjs` file: `session-start-seen-skills.mjs`, `session-start-profiler.mjs`, `inject-claude-md.mjs`. Exactly matches the 3 errors per resume.

**Fix (two parts):**
- **Removed** `/usr/local/bin/{node,npm,npx}` (all user-owned, no sudo) and `/usr/local/lib/node_modules/` (contained only npm's self-install, no global packages of value).
- **Symlinked** NVM's v24.13.0 binaries into `~/.local/bin/{node,npm,npx}`. `~/.local/bin` is on base PATH via zshenv's `$LOCAL_SHARE_BIN` and is inherited by any subshell Claude spawns. Verified both `bash -c 'node --version'` and `/bin/sh -c 'node --version'` resolve to `~/.local/bin/node` → Node v24.13.0.

**Same root cause as pending Forge ticket** about Starship `/usr/local/bin/node` timeout after `omz update` — this fix eliminates it too. Ticket should be closeable after confirmation.

## Decisions Made

- **Did NOT change PATH ordering.** Considered moving `/opt/homebrew/bin` ahead of `/usr/local/bin` as a structural fix. Decided against: with the only broken binary at `/usr/local/bin/node` removed, the remaining contents of `/usr/local/bin` are inert third-party installer dropoffs (Docker Desktop, Cursor, Kiro, Kubectl, Tailscale, Ollama — all symlinks into .app bundles). None conflict with `/opt/homebrew/bin`. Adding PATH-reorder logic would be complexity without benefit.
- **Did NOT uninstall Intel Homebrew `/usr/local/Homebrew/` script.** It's inert (no Cellar, no packages), not on PATH, and removing it requires root. Leave it alone.
- **tmux-window-namer kept session-scoped JSON schema.** User's call: renames should be rare, not worth redesigning the schema to be session-agnostic. Immediate fix (rename JSON key) only.
- **Symlinks pin to `v24.13.0` specifically**, not a "default" NVM alias. If node upgrades, symlinks go stale. Follow-up intent is to build symlink refresh into `helpers/install_node.sh` (or a new helper) so Dotbot's node install step creates them on every run — then `NODE_VERSION` bumps in zshenv naturally keep them current.

## What Didn't Work

- **`_load_nvm` default-node prepend was not firing in `zsh -i -c` tests,** despite NVM_DIR and nvm.sh present and v24.13.0 installed. The zshrc DEFAULT_NODE_PATH block (lines 110–113) should prepend NVM's node to zsh PATH on interactive start, but `zsh -i -c 'echo $PATH'` did not show it. Didn't chase further — secondary to the main fix and possibly a `zsh -i -c` semantics thing. Worth revisiting if future shell-startup perf work is done.
- **`brew shellenv | grep -vE '^eval .*path_helper'`** filter in `zsh/zshrc:30` is now a no-op — modern `brew shellenv` (≥4.x) no longer emits `eval $(path_helper -s)` lines. The filter does nothing today. Could be removed as simplification, but also harmless. Left in place to avoid disturbing a known-working block.

## What's Next

Prioritized:

1. **Confirm `SessionStart:resume hook error` is gone** in the clean Claude session the user is about to open. If clean → close pending Forge ticket `ticket-20260423-224300-fix-oh-my-zsh-update-starship-timeout-warning.md` with note that root cause was same Intel Node 12 binary.
2. **Commit `claude/settings.json`** — 5 new keys added via the Claude Code UI earlier today: `permissions.defaultMode: "auto"`, `skipAutoPermissionPrompt: true`, `preferredNotifChannel: "iterm2"`, `remoteControlAtStartup: true`, `agentPushNotifEnabled: true`. Plus `tui: "fullscreen"` relocated within the file (no value change). These should be committed so fresh machines inherit them.
3. **Add symlink refresh to `helpers/install_node.sh`** — after NVM installs the `NODE_VERSION` node, create/refresh `~/.local/bin/{node,npm,npx}` symlinks into that version. Keeps the hook-PATH workaround in sync on node upgrades. Small addition, idempotent, guarded by `DOTFILES_DRY_RUN`.
4. **Pending Forge ticket — Forge write access for `cadence-log.md`** (medium). Still un-created as a GitHub issue. File was root-owned in `workspace-forge/projects/dotfiles/`; Forge can write to `pending/` but not the cadence log itself. User to decide whether to promote to a board issue.
5. **OpenClaw MCP-reaper leak accelerating** — two inbox alerts fired tonight (kill counts 65 and 75 vs threshold 25; baseline 5–15). Archived to `shared/inbox/forge/archive/`. Not a dotfiles concern, but worth flagging to openclaw-forge session. Reference: `docs/solutions/infrastructure-issues/mcp-subprocess-leak-reddit-garmin-OpenClawGateway-20260417.md`.

## Gotchas & Watch-outs

- **tmux-window-namer schema is session-scoped.** Any future session rename will silently strip glyphs until the JSON key is renamed. Failure mode is visible (empty tab icons) but root cause is not obvious. If this happens again, check `jq keys ~/.config/tmux/window-meta.json` vs current `tmux display-message -p '#S'`.
- **`~/.local/bin/{node,npm,npx}` symlinks pin to `v24.13.0`.** On NVM node upgrade without the planned install_node.sh helper, the symlinks go stale. Mitigation: run the `ln -sf` lines manually, or follow-up #3 above eliminates the manual step.
- **Claude Code plugin hooks use bare `node` in command strings.** Vercel plugin's `hooks/hooks.json` calls `node ${CLAUDE_PLUGIN_ROOT}/...mjs` — fragile across user environments. Not our bug to fix, but any new plugin that follows the same pattern will fail on machines without a PATH-resolvable modern node. Part B of this session's fix (symlinks in `~/.local/bin`) is the defensive mitigation.
- **`/usr/local/bin` still on PATH** — at position 14 in zsh, position 2 in bare bash/sh. No longer contains a broken `node`, but any future third-party installer that drops a binary there could silently shadow an `/opt/homebrew/bin` binary. If you notice a tool behaving like an older version than `brew list --versions` reports, check `command -v <tool>` first.
- **Forge inbox still receives MCP-reaper alerts nightly.** They're not dotfiles alerts — the reaper lives in OpenClaw. `/pickup` on this project will keep archiving them. If more than 2–3 pile up between pickups, the leak has regressed further and belongs in openclaw-forge.
- **Carry-forward (still valid):** `##`-escape rule for hex colors in tmux `#{?...}` ternaries; `tmux display-message -p '<format>'` is the canonical format-string diagnostic; straight-to-master pushes do NOT auto-trigger `sync-vps.yml` (use `gh workflow run sync-vps.yml -f host=openclaw-prod -f dry_run=false`); statusline edits can blank pre-existing Claude sessions — always test from a fresh `claude` invocation, not `--continue`.
