# Repo tooling: bin/dot, dry-run, topgrade, sudo, Desktop Commander

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## No heredocs in `bin/dot`
The Python that `dot doctor` and `dot bench` run lives in `bin/lib/*.py` as real files.
**Do not "simplify" it back into inline `python3 - <<'PY'` blocks.**

Bash backs a small heredoc with a **pipe** and performs redirections for a compound command
*before* executing anything inside it — so it writes the entire document before forking the
process that would read it. If that write ever blocks it blocks forever, because the only
reader is a process that does not exist yet. This deadlocked `dot doctor` in **~1 of 8 runs**:
hung in the first check, no output, and — the detail that makes it hard to diagnose — **no child
process to blame**. `sample <pid>` parks in `do_redirections → heredoc_write → write`.

Counter-intuitively, **small heredocs are the dangerous ones**; bash switches to a temp file for
large documents, so a 250 KB heredoc is safe where a 2 KB one is not. Payload size sweeps and
isolated pattern reproductions both come back clean — the only reliable reproduction is running
the real command in a loop and counting hangs.

For a payload already in a variable, use process substitution rather than a heredoc:
```bash
done < <(printf '%s\n' "$files")     # safe: writer is a separate process
```
This also keeps the loop in the current shell (a `printf | while` pipeline would subshell it and
lose any counter). Full write-up:
`docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md`.

`dot check` runs `python3 -m py_compile` over `bin/lib/*.py`, since a syntax error there would
otherwise only surface as a confusing runtime failure of doctor/bench.

## `--dry-run` and `DOTFILES_DRY_RUN`
`./install --dry-run` previews every Dotbot directive without applying it — zero
mutations to your *config* (no symlinks, dirs, or shell steps). The one thing the
wrapper does regardless of `--dry-run` is `git submodule sync` + `update --init
--recursive dotbot` (it needs the vendored Dotbot to run at all), so on a
brand-new clone the `dotbot/` submodule is checked out first — a one-time git
operation, not part of the preview. The Dotbot run itself is mutation-free.

- **Dotbot ≥ v1.23.0 handles the flag natively.** The vendored submodule is pinned at v1.24.1 (see `dotbot/` submodule state). All built-in plugins (`link`, `create`, `clean`, `shell`) support dry-run and emit `Would create path / Would create symlink / Would run command` lines instead of executing.
- **The `install` wrapper passes `--dry-run` through** to Dotbot. It also exports `DOTFILES_DRY_RUN=1` as defense-in-depth.
- **Shell blocks are skipped entirely on dry-run** by Dotbot's native plugin behavior, so helper scripts (`install_omz.sh`, `install_tmux.sh`, `install_nvim.sh`, `install_packages.sh`) aren't even invoked.
- The `DOTFILES_DRY_RUN` env-var guards in those helpers are redundant under the normal `./install --dry-run` path but matter when a helper is invoked directly (`bash helpers/install_omz.sh` for manual testing or ad-hoc debugging) — they provide a consistent preview message and prevent mutation in that direct-invocation case.

When adding a new state-mutating helper, keep the env-var guard pattern for direct-invocation safety:
```bash
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would ..."
  exit 0
fi
```

When bumping the Dotbot submodule, re-verify fresh-host dry-run remains mutation-free:
```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
for cfg in dotbot-conf/base.yaml dotbot-conf/linux.yaml; do
  DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c "$cfg" --dry-run
done
find "$FAKE" -mindepth 1 | wc -l   # must be 0 (Library/Caches/com.apple.python noise aside)
rm -rf "$FAKE"
```

## Topgrade config
`topgrade/topgrade.toml` uses the `disable` array under `[misc]` to skip steps.
Variant names must be exact (e.g., `jetbrains_idea`, not `jetbrains`). Run
`topgrade` with an invalid name to see the full list of valid variants.
`--only <step>` overrides `disable`, so `topgrade --dry-run --only vim` still runs a disabled
step. To check that a step is off, run a full `topgrade --dry-run` and look for its `―― <Name>`
header. `vim` is disabled because its Neovim step rewrote the tracked `nvim/lazy-lock.json`
(#211).

**Running topgrade from an agent shell (no TTY).** Claude Code's `!` command mode and its
Bash tool have no controlling terminal, so any step that shells out to `sudo` fails with
`a terminal is required to read the password`. `topgrade --dry-run | grep sudo` does **not**
predict this — it lists only topgrade's own commands, and a Homebrew *cask's* upgrade
script can invoke sudo internally (`docker-desktop` does). Set up Touch ID (below), or use
`topgrade --disable brew_cask`, or run it in a real terminal and `tee` the log. Failure is
fail-fast rather than a hang, but a cask can abort *after* unloading services — check what
it removed. Full write-up:
`docs/solutions/security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md`.

## Touch ID for sudo
Machine-local root config that **Dotbot cannot manage** (`/etc/pam.d/` is root-owned and
outside `$HOME`), so it is a documented manual step. Needed on every fresh Mac; it is what
makes `sudo` usable from a no-TTY agent shell, since `pam_tid` raises a biometric dialog
instead of asking for a typed password.

```bash
sudo tee /etc/pam.d/sudo_local >/dev/null <<'PAMEOF'
# sudo_local: local config file which survives system update and is included for sudo
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
PAMEOF
sudo chmod 444 /etc/pam.d/sudo_local
```

`pam_reattach` (Brewfile: `pam-reattach`) must come **first** — it is what makes Touch ID
work inside **tmux** by reattaching PAM to the GUI session. Without it Touch ID works in a
bare terminal but silently falls back to a password prompt under tmux. It is `optional`, so
a missing module degrades to the password path instead of locking sudo out. `pam_tid` is
`sufficient`, so on success the stack short-circuits before `pam_opendirectory`.

Keep a second terminal with an authenticated sudo session open while editing `/etc/pam.d/` —
a malformed file there can break sudo auth, and that session is the escape hatch.
Undo: `sudo rm /etc/pam.d/sudo_local`. Does not work over SSH (no sensor).

**Rejected alternatives** (do not reintroduce): `SUDO_ASKPASS` has no effect on plain
`sudo` — only `sudo -A` consults it, and brew calls plain `sudo`. `sudo -v` pre-caching
cannot help either (no TTY to authenticate from, and `tty_tickets` keys the cache to the
originating terminal). A NOPASSWD sudoers entry broad enough to cover cask scripts is
effectively passwordless root.

## Desktop Commander remote (LaunchAgent)

Desktop Commander's remote device lets claude.ai chats (phone, web) run commands and edit
files on the personal Mac. It runs as the LaunchAgent `com.dvillavicencio.desktop-commander-remote`
(VIL-571), installed by hand on the personal Mac only:

    bash helpers/install_desktop_commander_remote.sh            # install, or restart after a stop
    bash helpers/install_desktop_commander_remote.sh --remove   # undo

**Run both from a terminal on the Mac, never through Desktop Commander** (a claude.ai chat):
both stop the agent before they finish (`--remove` first thing, an install after staging),
and the agent is the process carrying the command, so the run would die before reloading it
and leave the Mac unreachable. The installer refuses when it finds
the remote device among its parent processes, or can't check one of them. (macOS `pgrep` leaves out its own ancestors, so
a `pgrep -f` run through Desktop Commander can't see Desktop Commander; add `-a`.)

A reinstall stages everything first, so a failed npm install leaves the running agent alone.
Both modes refuse (exit 1, saying why) while the agent is still loaded after `bootout`, while
any copy of the remote device is still running, or when `launchctl` or `pgrep` fails and so
can't tell. If the swap succeeds but the old package can't be deleted, the installer goes on;
when loading then succeeds too, it exits 1 with the path to delete.

The installer puts the pinned package (`DC_VERSION` in the installer) in
`~/Library/Application Support/desktop-commander-remote/pkg` (a symlink to a `pkg-XXXXXX`
directory, switched in one rename, so an old package stays usable until the new one is in;
an install and a `--remove` never overlap: both take the lock
`desktop-commander-remote.install.lock` beside that folder), copies
`helpers/desktop_commander_remote.sh` beside it as the job, and loads the plist. The job
finds Node through `NVM_DIR`/`NODE_VERSION` (zshenv), so a Node bump needs no reinstall.
Log: `~/Library/Logs/desktop-commander-remote.log`. The package keeps its own day logs and
the saved sign-in in `~/.desktop-commander-device/`, and npm's cache in `~/.npm` holds a copy
of the package.

**The log rotates itself (VIL-579).** The package prints every command it receives in full,
and this log holds that output unredacted, so the job keeps it bounded. At start-up and every
15 s while it runs, it rotates the log once it passes 1 MB or 7 days after the last rotation.
It first deletes every copy numbered `LOG_KEEP` (2) or higher, so lowering `LOG_KEEP` takes
effect at the next rotation. Then the old `.1` becomes `.2` and the log becomes `.log.1`.
When every step works, that caps the log at about 3 MB and about 3 weeks of history
(`LOG_MAX_BYTES`, `LOG_MAX_DAYS` and `LOG_KEEP` are at the top of the job). Every copy is
mode 600. The last rotation's time is the
mtime of `log-rotated-at` in the job's Application Support folder.
- **Copy, then truncate in place.** launchd keeps the log open, so renaming it would leave
  the job writing to the renamed file. macOS `newsyslog` can't copy-truncate, which rules it
  out (and it would need sudo). launchd opens the log for appending, so after the truncation
  every write lands at the new end.
- **A line can be lost**: one written in the few milliseconds between the copy and the
  truncation. At about 200 lines a second, a test lost one line per rotation. The real log
  gets a few hundred lines a day.
- **If a step fails**, the live log is still cleared, so it stays bounded. That covers a copy
  that can't be deleted or moved, and a new copy that can't be written (most likely a full
  disk). The rotation stops at that step. Steps already done stay done, so a copy may
  already be deleted or shifted up one, leaving a gap in the numbers. After a failed new
  copy, `.1` is missing, unless the partial copy couldn't be deleted either; then `.1` holds
  that partial copy and the log line says so. The lowest-numbered copy left is the newest.
  This log's contents aren't kept, and the next log line names the step that failed. Copies
  the job couldn't delete stay on disk until whatever blocked them is fixed. If the stamp
  can't be written, only the size counts.
- The package's day logs in `~/.desktop-commander-device/` bound themselves: per UTC weekday,
  1 MB × 3 files, last week's removed on first write, at most 21 MB. Those lines are redacted.
- `--remove` leaves the log and its copies in `~/Library/Logs/`. Delete them by hand if you
  want them gone.
- A change to the job reaches the Mac only through a reinstall from a terminal (the job runs
  from a copy; see above). Before that, run `ci/desktop-commander-remote-log-checks.sh`: it
  tests the rotation under a fake HOME, then runs the whole job against a fake package, and
  leaves the live agent alone.

Decisions (David, 2026-11-02):
- **A LaunchAgent, not a LaunchDaemon.** A daemon runs as root, so claude.ai would get a
  root shell. The agent runs as David and only while he's logged in.
- **The Mac stays awake.** The package runs `caffeinate` while it's up (the default), so the
  Mac doesn't idle-sleep, on battery too. A closed lid still sleeps it. `--disable-no-sleep`
  is the opt-out.
- **Pinned, bumped by hand.** `@latest` would run whatever the npm maintainers publish next.
  When bumping, re-check `SIGNIN_LINE` in the job against the new package.
- **Telemetry off**: `DESKTOP_COMMANDER_DISABLE_TELEMETRY=1`, at install and at run time.

**It reaches everything David's account can.** Its `allowedDirectories` setting limits only
the file tools, not its terminal tool, so treat it as a full shell for anyone signed into
David's claude.ai account (2FA is on).

**Never run a second copy** (`npx … remote` by hand) while the agent is loaded. Both copies
refresh the same rotating refresh token, and replaying a spent one can revoke the session
(the package's own note in `dist/remote-device/device.js`). The installer and the job both
refuse to start beside another copy. While running, the job checks every 15 s; when it finds a
copy started by hand it stops its own (which saves the sign-in on the way out), waits until
the other exits, then starts again by itself. Both copies can still run together for up to
15 s plus the time ours takes to shut down, so the habit still matters: after installing, don't use the `curl … | sh` command (it also runs
`@latest`, not the pinned version). For a hand-started copy, run `--remove` first.

**When it stops for good.** The job exits 0, and so stays down, when:
- the saved sign-in no longer works (the package starts a browser sign-in; under a restart
  loop that would open a tab each time),
- `~/.desktop-commander-device/device.json` is missing,
- it had five quick failures in a row: the package exiting within 60 s, or a start-up check
  failing (no Node at `NODE_VERSION`, a `pgrep` error), or
- it can't save that failure count.
The reason is in the log. The `stopped` file in its Application Support folder holds it too
and keeps the job down across logins; if that file can't be written, the log says so and the
job tries again at the next login. To fix a
sign-in: `bash helpers/install_desktop_commander_remote.sh --remove`, run
`npx --yes @wonderwhy-er/desktop-commander@<DC_VERSION> remote` in a terminal, finish the
browser sign-in, press Ctrl+C, then run the installer again. Waiting for the network at login
doesn't count as a failure.
