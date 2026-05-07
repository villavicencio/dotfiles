# HANDOFF — 2026-05-07 (PDT, late afternoon)

Same-calendar-day continuation of the morning's `/pickup` (which itself opened on a clean tree post-#70-#74 merge train). This session is a tooling rebuild: Browserbase platform installed and wired durably into dotfiles; Maccy replaces Paste as clipboard manager; CleanMyMac replaced with a free stack (`mac-cleanup-py` + `kondo` + `pearcleaner`) and wired into `topgrade`; Setapp + 13 of its apps fully purged; a new global behavior rule (web tool ladder) lives in `~/.claude/CLAUDE.md`. **7 new commits, no PRs (all direct to master), no open PRs, one open issue (#75 — Node 24 deadline).**

## What We Built

### `b2f4f01` — `feat(npm): add @browserbasehq/cli to global npm requirements + bb shim`

2 files / +3 lines. First half of Browserbase install. After `npm install -g @browserbasehq/cli` succeeded:

- **`npm/npm-requirements.txt`** — `@browserbasehq/cli` added at top (alpha order — `@` sorts before `bash-language-server`).
- **`zsh/zshrc`** (lines 115-123 NVM lazy-loader block) — added `bb` to the `unset -f` line and `bb() { _load_nvm; command bb "$@"; }` shim, per the documented convention in `claude/CLAUDE.md` ("any npm-globally-installed CLI must be added as a shim").
- **Decorative-shim caveat documented**: the eager `DEFAULT_NODE_PATH` block at zshrc:110-113 already adds the NVM bin dir to PATH on fresh shell start, so the shim is conventional/redundant for `bb` resolution. Shim still added because the convention exists and the cost is zero.

### `afbb539` — `docs(solutions): browserbase skill-bundle install + chain-of-trust pattern`

1 file / +106 lines. Captures the install moment as a *generalizable* pattern for any future vendor-CLI install with a meta-installer step (Stagehand, Steel.dev, Playwright Cloud, etc. — anything with `npm install -g <vendor>/cli` + `<vendor> skills --install` shape).

- **`docs/solutions/best-practices/browserbase-skill-bundle-install-and-trust-2026-05-07.md`**
- **Locks down four things** that would otherwise have to be re-derived: (1) the two distinct harness halt categories — *code-from-external scouting* vs *self-modification* — and that AskUserQuestion `Yes` does NOT unblock self-modification (only a `.claude/settings.json` permission rule or user-runs-it-themselves via `!` prefix does); (2) the dotfiles wiring shape (npm-requirements + NVM shim get committed; skill content under `~/.agents/skills/` stays as per-machine state with no git audit); (3) the PATH gotcha (DEFAULT_NODE_PATH covers fresh zsh, but pre-existing shells need rehash/source/absolute-path); (4) the **2026-05-07 risk-assessment baseline** for the 13 installed skills (`fetch`=Critical Gen; `browser`/`cookie-sync`/`event-prospecting`=Critical Snyk).
- **Recipe section** spells out the conservative scope for any future similar install.

### `3ec1d7b` — `docs(claude): re-rank web tool ladder — Browserbase as tier 2, verify-cite as tier 3`

1 file / +31 / -17. Replaces the old "Realtime Facts" section in `~/.claude/CLAUDE.md` (symlinked to `claude/CLAUDE.md`) with an explicit three-tier "Web Tool Ladder":

- **Tier 1**: `WebFetch` — default for static HTML
- **Tier 2**: `browser` skill (Browserbase) — preferred for non-static fetches AND for realtime-fact queries; manual freshness discipline (quote literal page content + source URL + fetch timestamp, or decline)
- **Tier 3**: `/verify-cite` — strict-contract fallback for high-stakes claims (financial, medical, legal, public-record), when the user explicitly asks for verified citations, or when relying on skill-enforced substring-assert is preferable to manual discipline

User has generous Browserbase usage and explicitly preferred this re-ranking. `/verify-cite` stays in the toolkit, just demoted from default to fallback. The "never quote a realtime fact from training data without a freshness tag" rule is preserved — applies regardless of which tier did the fetch.

### `b0afec6` — `feat(brew): add maccy cask — clipboard manager replacing Paste app`

1 file / +1. Maccy 2.6.1 installed locally via `brew install --cask maccy` and added to Brewfile.

- **`brew/Brewfile`** — `cask "maccy"` after `cask "git-credential-manager"` (alpha order with the cask block at the bottom).
- **Why**: Paste app was previously installed via Setapp; user wanted free MIT-licensed replacement. Maccy is keyboard-first, lightweight, requires macOS Sonoma 14+, auto-updates via cask.
- **Spec source verified through the new `browser` skill** — first end-to-end use of Browserbase. Read https://github.com/p0deje/Maccy README, extracted version + install method + macOS minimum + license + features.
- **Maccy is running** (PID 43487, configured by user — Accessibility granted, hotkey set, login-item enabled in their walkthrough).

### `5ed5c28` — `feat(npm): add @browserbasehq/browse-cli + browse shim`

2 files / +8 / -6. Pairs with the first Browserbase commit — `browse-cli` is the binary the `browser` skill drives. The original SKILL.md called this Step 4 ("optional"), but using the skill at all requires it.

- **`npm/npm-requirements.txt`** — `@browserbasehq/browse-cli` added before `@browserbasehq/cli` (alpha: `browse-cli` < `cli`).
- **`zsh/zshrc`** — `browse` added to NVM `unset -f` list and `browse()` shim function added, matching the `bb` pattern.

### `c885573` — `feat(brew): replace CleanMyMac with free stack — mac-cleanup-py + kondo + pearcleaner`

1 file / +3 lines. Three free, focused tools to replace CleanMyMac (subscription).

- **`brew/Brewfile`** — `brew "kondo"` after `brew "jrnl"`; `brew "mac-cleanup-py"` after `brew "luv"`; `cask "pearcleaner"` after `cask "maccy"`. All three installed locally.
- **`mac-cleanup-py`** (formula) — CLI cleanup. Trash, logs, caches, Homebrew, Docker, npm/pnpm/yarn, Xcode derived data/archives, iOS backups, browser caches. Always run `--dry-run --verbose` first.
- **`kondo`** (formula) — dev-project cleanup (node_modules, build/, target/, .next/, etc.). README describes itself as "rm -rf with a prompt". **Manual single-shot use only — never schedule.** Misclassifying an active project as inactive risks uncommitted work.
- **`pearcleaner`** (cask) — app-uninstall leftover scrubber. Open source, has CLI hooks (`pear list-orphaned`, `pear uninstall-all`, etc.).
- **Skipped intentionally**: AppCleaner (Pearcleaner replaces it), Onyx (redundant with macOS background maintenance), CleanMyMac AV (Gatekeeper + XProtect built in; Patrick Wardle suite for serious analysis if ever needed).

### `9e88bbf` — `feat(topgrade): wire mac-cleanup-py into the topgrade run`

1 file / +11. Adds `[commands]` section to topgrade.toml so cache cleanup happens on the same cadence as other tooling updates.

- **`topgrade/topgrade.toml`** — new `[commands]` table with `"Clean macOS caches (mac-cleanup-py)" = "command -v mac-cleanup >/dev/null 2>&1 && yes y | mac-cleanup --force || true"`.
- **Three subtleties documented inline** with a 7-line comment block above:
  1. `command -v` guard makes it a clean no-op on the VPS (where mac-cleanup isn't installed) — the same `topgrade.toml` is symlinked on Mac and Linux.
  2. `yes y |` feeds the post-dry-run "Continue? [y/n]:" prompt — `--force` accepts warnings but does NOT skip that final confirmation, and topgrade is non-interactive so a hanging stdin would block.
  3. Module config lives in `~/.config/mac_cleanup/config.json` after the first interactive run. If absent, the inquirer-based picker fires and crashes immediately under topgrade (no TTY) — intentionally loud rather than silently picking defaults.

### Out-of-band cleanup (no commits — all live filesystem mutations)

Massive deletion sweep, all post-authorization. Numbers:

- **Paste app residue**: 16+ user-level paths across Containers, HTTPStorages, WebKit, Application Scripts, Logs, Group Containers, CloudKit cache, Daemon Containers, Logi icon cache.
- **CleanMyMac residue**: 33 user-level paths + 1 system-level privileged helper (`/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac-setapp.Agent`) + 1 system-level diagnostic report + 2 system-level Skylum-related paths in `/Library/Application Support/`.
- **Setapp + 13 Setapp-managed apps**: 124 user-level paths swept + 4 booted-out launchctl services (SetappAgent, SetappLauncher, SetappAssistant, SetappUpdater) + 3 killed processes + `~/Library/Application Support/Setapp/` (LaunchAgent backup) + `/Applications/Setapp.app` already-Trashed by Pearcleaner emptied.
- **Adobe/Skylum Photoshop plug-in**: `/Library/Application Support/Adobe/Plug-Ins/CC/Skylum/` (one Touch ID via osascript).

Tooling used: direct `rm -rf` for most; **Finder-via-AppleScript** (`tell application "Finder" ... delete ...`) for `~/Library/Mobile Documents/iCloud~*` (the only thing that bypasses CloudDocs daemon's Permission-denied for `rm`/`mv`); **osascript-with-administrator-privileges** for system-level (`/Library/...`) paths to get a Touch ID dialog instead of the no-TTY sudo failure.

## Decisions Made

- **Web tool ladder re-ranking** (now in global CLAUDE.md): User has generous Browserbase usage and explicitly preferred Browserbase as default-fetch over `/verify-cite`. Manual freshness discipline (quote-literal + source URL + fetch timestamp + decline-with-reason) lives at the agent level rather than skill-enforced. `/verify-cite` reserved for high-stakes (financial/medical/legal/public-record) and when the user explicitly asks.
- **Pearcleaner over AppCleaner** for the uninstall-leftover-scrubber slot. Open source, more modern, has CLI hooks (`pear list-orphaned`, `pear uninstall-all`). Atlas's recommendation; verified by use during this session — though the CLI's `list-orphaned` had **false positives** (flagged `org.p0deje.Maccy` as orphaned even though Maccy was running) so use the GUI for evaluation, not the CLI's blanket `remove-orphaned`.
- **kondo install but never schedule.** Atlas flagged it as "rm -rf with a prompt" — accurate. User commits/pushes frequently (multiple per session), so most projects are "active" by any sensible definition; danger of misclassification too high to wire into topgrade. Manual-only single-shot use.
- **Skipped Onyx and the CleanMyMac AV piece.** Onyx runs maintenance scripts macOS already runs in the background (redundant with mac-cleanup-py); the AV piece is theater (Gatekeeper + XProtect are built in; Patrick Wardle's free suite covers serious analysis if ever needed).
- **mac-cleanup-py wired into topgrade with `yes y | mac-cleanup --force`.** Auto-cleans on the same cadence as other tooling updates rather than living as a separate manual cycle. The `command -v` guard makes it a clean no-op on the VPS — same `topgrade.toml` is symlinked on Mac + Linux.
- **`bb` and `browse` get the NVM lazy-loader shim per convention** even though `DEFAULT_NODE_PATH` at zshrc:110-113 already covers PATH. Cost is zero, convention is documented in CLAUDE.md, future-self benefits from consistency.
- **Skill content stays out of repo.** `~/.agents/skills/` (where `bb skills --install` deposited 13 skills) is per-machine state. No git audit trail for the install moment except the dated `docs/solutions/` doc — that's a deliberate trade-off (committing a vendor-managed skill bundle would be a maintenance burden for marginal value).
- **Setapp subscription cancellation is on the user.** I can't do it — must be done at https://my.setapp.com/account.
- **iCloud-managed paths handed off to user's iCloud cleanup pass.** The 4 reappearing paths (`Mobile Documents/iCloud~com~nikolaeu~numi-setapp`, `iCloud~com~renfei~SnippetsLab-setapp`, `Caches/CloudKit/com.aramapps.PilePro-setapp`, `Caches/CloudKit/com.wiheads.paste-setapp`) keep coming back because iCloud is syncing them from the canonical store. Local rm is futile until iCloud-side data is purged via System Settings → Apple ID → iCloud → Manage Account Storage. User will handle as part of broader iCloud cleanup.

## What Didn't Work

- **`bb skills --install` blocked by harness with "Self-Modification" reason** — installing skill bundles into the agent's own skill directory based on instructions from an unverified domain (browserbase.com SKILL.md) needs pre-authorization at the permission-rule level. AskUserQuestion `Yes` does NOT unblock this class. User ran via `!` prefix instead.
- **`mac-cleanup-py` requires real TTY** — uses `inquirer` for interactive prompts. Bash subshells inside the agent (and even `!` prefix invocations) do NOT have a real TTY. `--force` accepts warnings but does NOT bypass the inquirer config picker on first run. User ran from real terminal.
- **`sudo` over `!` prefix fails** — "a terminal is required to read the password." Workaround: `osascript -e 'do shell script "..." with administrator privileges'` pops a GUI Touch ID dialog (one-shot for multiple commands chained in the shell-script string).
- **`~/Library/Containers/` is TCC-protected for `rm` even when path is owned by user** — the container's metadata file (`.com.apple.containermanagerd.metadata.plist`) is owned by `containermanagerd`, and the dir is part of macOS Data Vault. `rm` and `mv` both fail with "Operation not permitted." Even `sudo` doesn't bypass it cleanly. Fix: drag from Finder to Trash (Finder has the entitlement; gets a Touch ID prompt).
- **`~/Library/Mobile Documents/iCloud~*` is CloudDocs-protected** — same shape but a different daemon (`bird`). `rm` and `mv` both fail with "Permission denied." **Even Finder doesn't always show these folders** because if the parent app is uninstalled, Finder's iCloud Drive view filters them out. Fix that DID work: AppleScript-driven Finder (`tell application "Finder" ... delete (POSIX file "...") as alias`) — Finder has the entitlement, AppleScript can drive it from outside Finder's UI. May need a second attempt if iCloud immediately re-syncs from another device.
- **Pearcleaner's CLI `list-orphaned` has false positives** — flagged `org.p0deje.Maccy` (running RIGHT NOW), `com.skylum.luminar4-setapp` (Setapp app), and many other still-active app data dirs. Likely because Pearcleaner doesn't fully scan `/Applications/Setapp/` and similar non-standard install locations. **Don't ever run `pear remove-orphaned` blindly.** Use the GUI for evaluation, or `pear uninstall-all <specific-bundle-path>` for known targets.
- **CleanMyMac wasn't catchable by Pearcleaner GUI** because the `/Applications/CleanMyMac.app` bundle was already gone — Pearcleaner's "orphan" detection requires the bundle to either be present (for "uninstall this") or to have left a residue Pearcleaner recognizes as belonging to a known-uninstalled app. With the bundle pre-removed, the residue was invisible to its scanner. Manual `find ~/Library -iname "*macpaw*"` + `rm -rf` was the actual cleanup tool.
- **iCloud tug-of-war** — deleted ~/Library/Caches/CloudKit/com.* entries reappear because the local CloudKit daemon recreates them as long as the Apple ID is associated with the apps' CloudKit containers. Permanent fix is account-side, not disk-side.

## What's Next

1. ***(Carry-forward — STILL active, deadline 2026-06-02 = 26 days)*** **Issue #75 — bump GH Actions SHA pins to Node-24-supporting versions before deadline.** Filed during this session. `actions/checkout`, `docker/build-push-action`, `docker/login-action`, `docker/setup-buildx-action`, `actions/cache` are all SHA-pinned to Node-20 versions. June 2 forces them to Node 24; September 16 removes Node 20. Each pin needs a fresh release-tag → SHA lookup; SHA-pinning convention from PR #57 still applies (mutable-tag supply-chain risk). Highest-priority follow-up.
2. **(User-side, manual) iCloud cleanup pass** — go to System Settings → Apple ID → iCloud → "Manage Account Storage" (or iCloud.com web UI for fully-uninstalled apps) and delete data for `Numi`, `SnippetsLab`, `PilePro`, `Paste`, plus the broader sweep the user spotted. Until done, the 4 local CloudKit/Mobile-Documents paths will keep reappearing on each `find` sweep — they're not a real problem, just iCloud doing its job.
3. **(User-side, manual) Cancel Setapp subscription** at https://my.setapp.com/account. Until done, billing continues regardless of local app removal.
4. **(Optional) Run `mac-cleanup` (without `--dry-run`) once** to actually free the 20.81 GB the dry-run identified. After that, topgrade will keep it on autopilot per the topgrade integration commit.

## Gotchas & Watch-outs

- **`bb` shim in `zshrc` is decorative.** `DEFAULT_NODE_PATH` at zshrc:110-113 already adds the NVM bin dir to PATH on shell start. Same applies to `browse`. The shims still match the documented convention in CLAUDE.md and cost nothing — leave them. If `DEFAULT_NODE_PATH` block ever gets removed, the shims become load-bearing.
- **Browserbase agent skills live at `~/.agents/skills/` and are symlinked into Claude Code.** Machine-scoped, not project-scoped. There's no per-project disable knob — only "uninstall the skill globally." Worth knowing if you ever need a Browserbase-aware skill set on `dotfiles` but NOT on, say, `openclaw`.
- **`~/Library/Containers/` and `~/Library/Mobile Documents/` are macOS Data-Vault / CloudDocs protected.** `rm` and `mv` fail (with "Operation not permitted" / "Permission denied") **even when path is owned by user, even with `sudo`**. Only Finder has the entitlement — escape hatch is `open <parent> -R <target>` to surface in Finder, then drag to Trash. For iCloud Mobile Documents specifically: if the parent app is uninstalled, Finder hides the folder from the iCloud Drive view — use AppleScript-driven Finder (`tell application "Finder" ... delete (POSIX file "...") as alias`) to bypass that filtering.
- **`sudo` does not work via Claude Code's `!` prefix** ("a terminal is required to read the password"). Workaround: `osascript -e 'do shell script "..." with administrator privileges'` — chain multiple commands in the shell-script string for one Touch ID prompt. This pattern came up THREE times this session (CleanMyMac helper, Skylum Adobe plug-in, system-level Skylum Application Support).
- **Vendor SKILL.md installs trigger the harness's "Self-Modification" halt** when their meta-installer would write into the agent's own skill directory. AskUserQuestion `Yes` does NOT unblock this class. Either pre-authorize via `.claude/settings.json` permission rule, or have the user run via `!` prefix. Documented in `docs/solutions/best-practices/browserbase-skill-bundle-install-and-trust-2026-05-07.md`.
- **`mac-cleanup-py` and `bb skills --install` both require real TTY.** Can't run from inside the agent — `!` prefix doesn't allocate one either. User must run from a real terminal app (iTerm, Terminal.app).
- **Pearcleaner CLI `list-orphaned` is over-eager** — flags Maccy and many active Setapp apps as orphaned. Never run `pear remove-orphaned` without explicit per-target review. GUI-driven evaluation is fine; CLI is dangerous.
- **Setapp persists via `~/Library/Application Support/Setapp/LaunchAgents/Setapp.app`** — even after `/Applications/Setapp.app` is in the Trash, this backup copy is registered as a LaunchAgent and keeps `SetappAgent`, `SetappLauncher`, and `FinderSyncExt` running. Full purge requires `launchctl bootout gui/$UID/<service>` for each Setapp service + kill any straggler processes + `rm -rf` the Application Support copy. Same trick may exist for other Setapp-installed apps — be vigilant on future similar uninstalls.
- **iCloud sync recreates locally-deleted CloudKit/Mobile-Documents data.** Permanent purge requires going to System Settings → Apple ID → iCloud → Manage Account Storage (or iCloud.com web). Don't waste time on local `rm` for these — will keep losing the tug-of-war.
- **`--no-verify` was NOT used this session.** All 7 commits passed gitleaks pre-commit cleanly. Continuing the streak from yesterday's correction (the only `--no-verify` slip was on a throwaway seed branch, since deleted).
- **HANDOFF.md is current-session-state-only.** Yesterday's handoff (`57972ec`, captures the morning + late-afternoon CleanMyMac ramp + the carryover-queue drain) lives in git history. This file gets overwritten each `/handoff`.
