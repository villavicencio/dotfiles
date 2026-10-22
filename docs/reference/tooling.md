# Repo tooling: bin/dot, dry-run, topgrade, sudo

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
