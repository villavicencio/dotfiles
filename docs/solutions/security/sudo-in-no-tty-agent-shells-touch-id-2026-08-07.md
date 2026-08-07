---
title: "sudo in a no-TTY agent shell — why topgrade's cask upgrades fail, and Touch ID as the fix"
date: 2026-08-07
category: security
module: sudo
problem_type: config_error
component: tooling
symptoms:
  - "`brew upgrade --cask docker-desktop` fails with `sudo: a terminal is required to read the password`"
  - "topgrade run from Claude Code's `!` command mode reports `Brew Cask (ARM): FAILED` while most steps pass"
  - "Setting `SUDO_ASKPASS` has no effect — plain `sudo` never invokes the helper"
  - "A cask upgrade removes launchctl services and privileged helpers, then aborts, leaving the app on the old version"
root_cause: design_limitation
resolution_type: config_change
severity: Medium
related_components:
  - development_workflow
  - topgrade
tags:
  - sudo
  - pam
  - touch-id
  - tty
  - topgrade
  - homebrew
  - claude-code
---

# sudo in a no-TTY agent shell

## Problem

Claude Code's `!` command mode (and its Bash tool) run with **no controlling terminal**:

```
$ [ -t 0 ] && echo tty || echo "no tty"
no tty
$ tty
not a tty
```

sudo reads passwords from the terminal. With no TTY it cannot prompt, so anything that
shells out to `sudo` fails:

```
sudo: a terminal is required to read the password; either use the -S option
      to read from standard input or configure an askpass helper
sudo: a password is required
```

## Why `topgrade --dry-run` does not predict this

The obvious pre-flight check is to dry-run and grep for `sudo`:

```bash
topgrade --dry-run --no-self-update 2>&1 | grep -i sudo   # no matches
```

**This is not sufficient, and it is a trap.** The dry-run lists only the commands
*topgrade* plans to invoke. It cannot see inside them. A Homebrew **cask's own upgrade
script** may invoke sudo internally — `docker-desktop` does, to remove
`/Library/PrivilegedHelperTools/com.docker.socket`:

```
==> Upgrading docker-desktop 4.82.0,233772 -> 4.85.0,235549
==> Removing launchctl service com.docker.helper
==> Removing launchctl service com.docker.socket
==> Removing launchctl service com.docker.vmnetd
==> Removing files:
/Library/PrivilegedHelperTools/com.docker.socket
sudo: a terminal is required to read the password
Error: docker-desktop: Failure while executing;
  `/usr/bin/sudo -E -- /usr/bin/xargs -0 -- /bin/rm -r -f --` exited with 1
```

There is no way to know in advance which cask will need root.

## The partial-failure hazard

The cask aborted **after** unloading three launchctl services and **before** restoring
anything. Docker stayed on 4.82.0 and `/Library/PrivilegedHelperTools/` was left with no
Docker helpers.

A failed privileged step is not necessarily a no-op. Check what it removed before it died.

**Do not read a working `docker` command as evidence the cask is fine.** `docker info`
kept answering throughout, which initially read as "Docker Desktop is healthy." It wasn't —
`docker context ls` shows **colima** is the active context on this machine, so the CLI was
talking to the colima VM the whole time and Docker Desktop's broken state was invisible.
Check `docker context ls` before concluding anything about Docker Desktop from CLI
behavior. (Docker Desktop reinstalls its privileged helpers on first launch of the app,
not during `brew upgrade --cask`.)

## `SUDO_ASKPASS` alone does NOT work

Tempting fix, and it is wrong:

| Invocation | `SUDO_ASKPASS` set | Helper invoked? |
|---|---|---|
| `sudo -A true` | yes | **yes** |
| `sudo true` | yes | **no** |

Plain `sudo` ignores the environment variable. Since brew's cask scripts call plain
`sudo`, exporting `SUDO_ASKPASS` accomplishes nothing. sudo's own error message points at
the real knob — the **sudoers** `Defaults askpass=` option, not the env var.

A sudoers askpass helper would work, but it applies to every no-TTY sudo system-wide and
lets any local process raise a legitimate-looking password dialog. Touch ID achieves the
same result without that phishing surface, so this repo does not use askpass.

## `sudo -v` pre-caching does not work either

Two independent reasons:

1. You cannot run `sudo -v` from the agent shell — no TTY to type into. Same wall.
2. sudo defaults to `tty_tickets`, which keys each credential cache to the terminal that
   created it. Authenticating in a real terminal does not hand its ticket to a
   no-TTY process.

## Do NOT use a NOPASSWD sudoers entry

Cask scripts run arbitrary `sudo rm -rf` against system paths. A NOPASSWD grant broad
enough to cover them is effectively passwordless root. Not an acceptable trade for
unattended package upgrades.

## Resolution — Touch ID for sudo

Touch ID does not need a TTY: `pam_tid` raises a biometric dialog instead of asking a PAM
conversation function for a typed password, which is the step that fails without a
terminal. macOS ships the hook already wired — `/etc/pam.d/sudo` begins with
`auth include sudo_local`, and `/etc/pam.d/sudo_local.template` exists for exactly this.

**Confirmed working from a no-TTY shell (2026-08-07).** After applying the step below,
plain `sudo true` succeeds from Claude Code's Bash tool with `tty` reporting "not a tty" —
the same invocation that failed beforehand. End-to-end proof: `brew upgrade --cask
docker-desktop`, the exact privileged operation that failed during the topgrade run,
completed from that shell and took the cask 4.82.0 → 4.85.0.

One-time root step (cannot be Dotbot-managed — `/etc/pam.d/` is root-owned and outside
`$HOME`):

```bash
sudo tee /etc/pam.d/sudo_local >/dev/null <<'PAMEOF'
# sudo_local: local config file which survives system update and is included for sudo
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
PAMEOF
sudo chmod 444 /etc/pam.d/sudo_local
```

`pam_reattach` (Brewfile: `pam-reattach`) must come **first** and is what makes Touch ID
work inside **tmux** — it reattaches the PAM stack to the user's GUI (Aqua) session.
Without it, Touch ID works in a bare terminal and silently falls back to a password prompt
inside tmux. It is `optional` so a missing or broken module degrades to the password path
rather than locking sudo out.

Ordering matters: `pam_tid` is `sufficient`, so on success the stack short-circuits and
`pam_opendirectory` (password) is never reached.

### Safety when editing PAM

Keep a second terminal with an already-authenticated sudo session open while changing
`/etc/pam.d/`. A malformed file there can break sudo authentication; an open authenticated
session is the escape hatch for reverting. To undo: `sudo rm /etc/pam.d/sudo_local`.

### Known limits

- Touch ID for sudo does not work over SSH — a remote session has no biometric sensor.
- The `sudo_local` file survives macOS updates by design (that is the point of the
  template split), but is machine-local and lost on a fresh install. It is documented
  here and in `CLAUDE.md` rather than tracked, since Dotbot cannot symlink into
  `/etc/pam.d/`.

## Practical guidance for topgrade

- Everything except privileged cask upgrades runs fine in a no-TTY agent shell.
- `topgrade --disable brew_cask` avoids the whole class if Touch ID is not set up.
- Otherwise run topgrade from a real terminal and tee the log if an agent needs to read it:
  `topgrade 2>&1 | tee /tmp/topgrade-full.log`
- Failure mode is fail-fast, not a hang: sudo errors immediately with no TTY, so the run
  completes rather than stalling. (Contrast the `dns_cache` case noted in
  `topgrade/topgrade.toml`, which hung for 16 hours *interactively* because a progress bar
  swallowed the prompt.)
