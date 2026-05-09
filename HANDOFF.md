# HANDOFF — 2026-05-08 (PDT, late morning)

Same-calendar-day continuation of yesterday's tooling-rebuild session. Two tiny dotfiles commits (mac-cleanup config-path fix + Shottr cask adoption), pushed direct to master. The bulk of the session was off-repo: triaging a `mac-cleanup-py` 16-hour DNS-cache hang, then a deep, *unsuccessful* triage chain on a Cowork hang in Claude Desktop 1.6608.0 — confirmed upstream, workarounds documented. **2 new commits, both pushed (`fe16ea9`, `a924db9`), no PRs, no new tickets, one carry-forward issue (#75).**

## What We Built

### `fe16ea9` — `docs(topgrade): document mac-cleanup dns_cache sudo-prompt trap + fix config path`

1 file / +8 / -1. Triggered by the user noticing `mac-cleanup-py` had hung 16 hours on the `dns_cache` step. Diagnosis: `mac-cleanup-py`'s `rich`-style progress bar swallows sudo's password prompt during the `dscacheutil -flushcache` / `killall -HUP mDNSResponder` calls. With no visible prompt, sudo waits on stdin forever (no internal timeout). Under topgrade's no-TTY env, sudo errors out fast and the wrapper's `|| true` keeps the run going, but the cleanup silently aborts mid-list and leaves later modules unrun.

- **`topgrade/topgrade.toml`** — added a 7-line caveat above the mac-cleanup `[commands]` entry warning future-self off enabling `dns_cache`. Also corrected the path the existing comment block claimed: `~/.config/mac_cleanup/config.json` → `~/.config/mac_cleanup_py/config.toml` (different dir, different format).
- **Local-only (uncommitted, no repo footprint):** edited `~/.config/mac_cleanup_py/config.toml` to drop both `dns_cache` (sudo trap) and `docker` (would prune Docker build cache and slow next OpenClaw rebuild). Remaining 11 enabled modules: `brew`, `chromium_caches`, `chrome`, `system_caches`, `system_log`, `trash`, `xcode`, `yarn`, `pnpm`, `npm`, `bun`.

### `a924db9` — `feat(brew): add shottr cask — bring existing screenshot-tool install under cask management`

1 file / +1. Shottr 1.9.1 was already running at `/Applications/Shottr.app` from a manual install (>90 days ago — predates this Claude session-history window per `/ce-sessions` search). Adopted under cask management via `brew install --cask --adopt shottr` so the existing app + TCC grants + configured hotkeys carry forward unchanged; no redownload, no settings reset.

- **`brew/Brewfile`** — `cask "shottr"` after `cask "pearcleaner"` (alpha order with the cask block at the bottom).
- Net effect: future `topgrade` runs upgrade Shottr automatically; fresh-install Macs (the work Mac, future replacements) get Shottr provisioned alongside the rest of the cask block.

### Off-repo: Claude Desktop Cowork hang triage (4 cumulative wipes, none fixed it)

User reported Claude Desktop "hanging" — narrowed to: hangs ONLY when going to Cowork tab and starting/opening a session. Worked through 4 progressively-deeper local-state hypotheses, **all wrong**. The actual bug is upstream and I burned ~40 mins shooting at the wrong layer.

Tried in order:
1. **Force-kill the wedged renderer** (PID 18393 → SIGTERM ignored → SIGKILL took). Restored launching but Cowork hang reproduced on first new-session attempt.
2. **Quarantined 5 orphan session dirs** (`local_ea8e3761`, `local_3ab90314`, `local_20a29b70`, `local_eb4d994a`, `local_1309cc84`) under `local-agent-mode-sessions/.../.broken-orphans-2026-05-08/`. Each was 8KB of empty audit scaffolding with no matching `.json` transcript file (healthy sessions have both). Theory: enumerator hangs on the missing transcripts. **Wrong** — orphans were a downstream symptom, not cause. Hang reproduced.
3. **Wiped the `Claude Safe Storage` keychain entry** (Electron's `safeStorage` master encryption key). Backed up first to `~/claude-safe-storage-backup-2026-05-08.txt`. **CAUSED A NEW BUG**: the IndexedDB files were encrypted with the deleted key, so on next launch `Uncaught (in promise) UnknownError: Internal error opening backing store for indexedDB.open` started firing four times in `claude.ai-web.log`. Made things worse.
4. **Move-aside the 5 Chromium browser-storage dirs** (`IndexedDB`, `Local Storage`, `Session Storage`, `Cookies`, `Cookies-journal`) under `*.broken-2026-05-08-corrupted/`. Forced fresh browser-state init on relaunch; required full sign-in. Cowork hang **identical signature**.

After all 4 attempts, the hang signature was character-for-character the same as the original log entry, with all local-state confounders eliminated:
```
LocalAgentModeSessions.start
oauth config { clientId: 'a473d7bb-17ac-43a7-abc0-a1343d7c2805',
               scope: 'user:inference user:file_upload user:profile' }
[oauth] performing fresh oauth exchange
[silence — no `obtained new token` line, ever]
```

Compare to the OAuth call that **works** in the same session (Chat, different client `89355bc3`, scope `user:inference user:office`): completes in 1ms. So the bug is specifically in the Cowork OAuth client + scope round-trip with Anthropic's backend in the version of Claude Desktop currently shipping (1.6608.0 — confirmed via in-app `Check for Updates`: "you're up to date").

**Cleanup at end of session:** all 4 quarantine artifacts deleted (`~/claude-safe-storage-backup-2026-05-08.txt`, the 5 Chromium-storage `.broken-*` dirs, the 5 orphan-session quarantine dirs). VM bundle (10GB) + 5 healthy cowork sessions + Claude Code-credentials keychain all preserved. State is back to baseline minus the (still-broken) Cowork.

## Decisions Made

- **`dns_cache` permanently OFF in `~/.config/mac_cleanup_py/config.toml`.** DNS cache flush is cosmetic — Wi-Fi cycle or reboot does the same thing — and the sudo-prompt trap is a hard hang interactively, silent partial-cleanup under topgrade. Documented in `topgrade/topgrade.toml`'s comment block so future-me doesn't re-derive.
- **`docker` also OFF in mac-cleanup config.** Reason: would clear Docker build cache and slow next OpenClaw rebuild on the VPS sync. Reversible (re-run `mac-cleanup` and edit the toml).
- **Shottr adopted via `--adopt`, not reinstalled.** Existing app, existing TCC grants, existing hotkey config all preserved. The "feat(brew)" framing matches the session's small-additive direct-to-master pattern from yesterday.
- **Push-immediately-after-commit rule saved as a feedback memory.** User said "Always" when asked whether to push. Updated `feedback_commit_approval.md` to add a Push rule next to the existing Carve-out rule: any commit I'm authorized to make under the carve-out (or any other commit), push immediately — never ask "want me to push?" Also bumped `MEMORY.md`'s pointer line.
- **Cowork-via-web is the recommended workaround** until Anthropic ships a fix. `claude.ai/task/new` in any browser uses the web's `claude.ai` cookie session and bypasses the broken desktop OAuth client `a473d7bb-...` entirely.
- **Reinstall would not have helped.** Confirmed via in-app update check: 1.6608.0 IS the current shipping version. A drag-to-Trash + redownload pulls the same binary, same compiled OAuth client, same bug. Pearcleaner-assisted nuke would also rebuild a 10GB VM and lose all 6 cowork sessions for nothing — only worth doing IF a newer build existed with the fix.

## What Didn't Work

- **`mac-cleanup --dry-run` does NOT bypass the dns_cache hang.** The dry-run preview shows what it would clean, then asks "Continue? [y/n]:" — answer `y` and it proceeds with the REAL cleanup, hitting the sudo trap immediately at the dns_cache step. Treat dry-run as preview only.
- **Quarantining orphan session dirs.** Removed visible artifacts but didn't fix the wedge. Each new failed Cowork attempt creates another orphan, so the quarantine refilled to size 1 within minutes.
- **Wiping `Claude Safe Storage` keychain entry.** Worse than no-op — orphaned the IndexedDB files, introduced a new error class (`Internal error opening backing store for indexedDB.open`) without addressing the OAuth bug. Lesson: Electron's safeStorage encrypts more than just OAuth tokens; deleting the key without also wiping the encrypted files leaves the app in a worse state. If we ever do this again, wipe browser-state dirs in the SAME action, not as a follow-up.
- **Move-aside of all 5 Chromium browser-storage dirs.** Forced fresh init, required full re-login, and the OAuth round-trip still hangs identically. Unambiguous proof the bug is in the OAuth round-trip itself, not local cache.
- **Vanilla drag-to-Trash + redownload reinstall.** Would not have helped — `~/Library/Application Support/Claude/`, `~/Library/Caches/...`, prefs plist, and keychain all survive macOS app uninstall. Only the binary refreshes. Same as `Check for Updates` in the menu.
- **Sign out + sign back in via Claude Desktop's UI.** User tried this first — gets logged right back in, doesn't drop the per-OAuth-client cached tokens that were the early hypothesis. (Also the early hypothesis turned out to be wrong, so even a "successful" sign-out wouldn't have fixed it.)

## What's Next

1. **(Carry-forward — STILL active, deadline 2026-06-02 = 25 days)** **Issue #75 — bump GH Actions SHA pins to Node-24-supporting versions before deadline.** Highest priority follow-up. `actions/checkout`, `docker/build-push-action`, `docker/login-action`, `docker/setup-buildx-action`, `actions/cache` all SHA-pinned to Node-20 versions. Each needs a fresh release-tag → SHA lookup; SHA-pinning convention from PR #57 still applies. Per the user's standing rule, this needs a new branch (no ticket work on master). Touches `.github/workflows/*.yml`.
2. **(User-side, manual) iCloud cleanup pass** — System Settings → Apple ID → iCloud → Manage Account Storage. Carry-forward from yesterday's session. Until done, the 4 reappearing CloudKit/Mobile-Documents paths (Numi, SnippetsLab, PilePro, Paste) keep coming back on `find` sweeps.
3. **(User-side, manual) Cancel Setapp subscription** at `https://my.setapp.com/account`. Carry-forward from yesterday.
4. **(Optional) Run `mac-cleanup --force` once** to free the ~20 GB the dry-run identified. Now safe — `dns_cache` and `docker` are deselected in `~/.config/mac_cleanup_py/config.toml`. After that, topgrade keeps it on autopilot.
5. **(Optional, when annoyed enough) File feedback to Anthropic about the Cowork OAuth bug.** Diagnostic payload ready: build `1.6608.0`, macOS Tahoe `26.4.1`, OAuth client `a473d7bb-17ac-43a7-abc0-a1343d7c2805`, scope `user:inference user:file_upload user:profile`, signature `[oauth] performing fresh oauth exchange` never followed by `[oauth] obtained new token`. Compare to working Chat OAuth (client `89355bc3`, scope `user:inference user:office`) in the same session for the cleanest report shape.

## Gotchas & Watch-outs

- **`mac-cleanup --dry-run` is a misleading name** — it shows the preview AND offers a "Continue? [y/n]:" gate to proceed with the real cleanup. The "dry-run" wrapper isn't a hard guard. Always exit out via Ctrl+C if you want true preview-only.
- **`mac-cleanup-py` config persists at `~/.config/mac_cleanup_py/config.toml`** (not `~/.config/mac_cleanup/config.json` as some docs claim). It's a single-line `enabled = [...]` array. Edit by hand — the picker only re-fires when the file is missing entirely, and ^C during the picker DOES persist your selection (write happens on `<enter>` confirm, before the cleanup loop starts).
- **Claude Desktop's `Claude Safe Storage` keychain entry is more than OAuth.** It's Electron's `safeStorage` master key for encrypting EVERYTHING in `~/Library/Application Support/Claude/` — IndexedDB, cookies, cached state. Deleting it without simultaneously wiping the encrypted dirs leaves the app worse than before (IndexedDB unreadable, errors flood the renderer log). Don't repeat this mistake.
- **Cowork OAuth in Claude Desktop 1.6608.0 is broken upstream** — the OAuth round-trip for client `a473d7bb-...` with scope `user:inference user:file_upload user:profile` simply doesn't return a token. Local fixes can't address this. Until Anthropic ships an update: use Cowork via web at `claude.ai/task/new`. Chat OAuth (different client/scope) still works fine in the desktop app.
- **`Claude Code-credentials` keychain entry (account `dvillavicencio`) is for the Claude Code CLI** — `~/.local/bin/claude` — and is COMPLETELY separate from `Claude Safe Storage` (Desktop, account `Claude`). Different `svce`, different `acct`, different account names. Operations on one cannot affect the other. The CLI keeps working through any Desktop reset.
- **`Claude Code-credentials` should never be deleted in a Desktop debugging session** — it would log you out of this Claude Code session you're currently using. Always grep keychain entries by exact `svce` name (`security find-generic-password -s "Claude Safe Storage"`), never by partial-match like `-s "Claude"`.
- **Cowork creates orphan dirs under `local-agent-mode-sessions/<userId>/<orgId>/local_<uuid>/` whenever a session-create fails.** Each is ~8KB of empty audit scaffolding. They accumulate silently. Healthy sessions have both a directory AND a `.json` file with the same UUID; orphans have only the directory. Worth a periodic sweep — but doesn't fix the upstream bug, just keeps the dir tidy.
- **`Network/` subdir doesn't exist on this Claude Desktop install** (newer Chromium versions have it, this build uses the older `Cookies` / `Cookies-journal` files at the top level). If a future cleanup script targets `~/Library/Application Support/Claude/Network/`, account for the absence.
- **`--no-verify` was NOT used this session.** Both commits passed gitleaks pre-commit cleanly. Continuing the streak.
